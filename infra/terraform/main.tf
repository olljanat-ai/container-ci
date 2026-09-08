data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "this" {
  count = var.create_resource_group ? 1 : 0

  location = var.location
  name     = var.resource_group_name
  tags     = var.tags
}

data "azurerm_resource_group" "existing" {
  count = var.create_resource_group ? 0 : 1

  name = var.resource_group_name
}

locals {
  resource_group_name = var.create_resource_group ? azurerm_resource_group.this[0].name : data.azurerm_resource_group.existing[0].name
}

###############################################################################
# User-assigned managed identities for tenant pipelines.
#
# Each identity carries one federated credential, so a pipeline exchanges its
# own OIDC token for an Azure token. No client secret is created, stored or
# rotated anywhere.
###############################################################################
resource "azurerm_user_assigned_identity" "ci" {
  for_each = local.ci_identity_grants

  location            = var.location
  name                = each.value.name
  resource_group_name = local.resource_group_name
  tags                = merge(var.tags, { tenant = each.value.tenant_key })
}

resource "azurerm_federated_identity_credential" "ci" {
  for_each = local.ci_identity_grants

  audience            = [each.value.audience]
  issuer              = each.value.issuer
  name                = "fic-${each.key}"
  parent_id           = azurerm_user_assigned_identity.ci[each.key].id
  resource_group_name = local.resource_group_name
  subject             = each.value.subject
}

###############################################################################
# The registry itself.
###############################################################################
module "container_registry" {
  source  = "Azure/avm-res-containerregistry-registry/azurerm"
  version = "0.8.0"

  location            = var.location
  name                = var.registry_name
  resource_group_name = local.resource_group_name

  sku                     = var.sku
  zone_redundancy_enabled = var.zone_redundancy_enabled
  georeplications = [
    for replica in var.geo_replications : {
      location                  = replica.location
      regional_endpoint_enabled = replica.regional_endpoint_enabled
      zone_redundancy_enabled   = replica.zone_redundancy_enabled
    }
  ]

  # Public by design: hosted CI runners have no stable egress address, and a
  # private endpoint would put every pipeline behind a self-hosted runner.
  # Authorization, not network reachability, is what keeps tenants apart.
  public_network_access_enabled = var.public_network_access_enabled
  network_rule_bypass_option    = var.network_rule_bypass_option
  network_rule_set = length(var.allowed_ip_ranges) > 0 ? {
    default_action = "Deny"
    ip_rule        = [for cidr in var.allowed_ip_ranges : { ip_range = cidr }]
  } : null

  # The admin account is a shared username/password that bypasses every
  # per-tenant boundary this configuration builds. It stays off.
  admin_enabled          = false
  anonymous_pull_enabled = var.anonymous_pull_enabled
  data_endpoint_enabled  = var.data_endpoint_enabled

  export_policy_enabled     = var.export_policy_enabled
  quarantine_policy_enabled = var.quarantine_policy_enabled
  retention_policy_in_days  = var.retention_policy_in_days

  role_assignment_mode = var.role_assignment_mode

  managed_identities = {
    system_assigned = true
  }

  cache_rules     = var.cache_rules
  credential_sets = var.credential_sets

  scope_maps = local.tenant_scope_maps

  role_assignments = merge(
    # Repository-scoped access for identities that already exist.
    {
      for key, grant in local.tenant_principal_grants : key => {
        role_definition_id_or_name = local.repository_roles[grant.access]
        principal_id               = grant.object_id
        principal_type             = grant.principal_type
        description                = grant.description
        condition                  = local.abac_conditions[key]
        condition_version          = "2.0"
      }
    },
    # Repository-scoped access for the pipeline identities created above.
    {
      for key, grant in local.ci_identity_grants : "ci-${key}" => {
        role_definition_id_or_name = local.repository_roles[grant.access]
        principal_id               = azurerm_user_assigned_identity.ci[key].principal_id
        principal_type             = "ServicePrincipal"
        description                = grant.description
        condition                  = local.abac_conditions[key]
        condition_version          = "2.0"
      }
    },
    # A push identity still needs to pull shared base images and cached
    # upstreams, which sit outside its own namespaces.
    {
      for key, grant in local.ci_identity_shared_read_grants : "ci-${key}-sharedread" => {
        role_definition_id_or_name = local.repository_roles.pull
        principal_id               = azurerm_user_assigned_identity.ci[key].principal_id
        principal_type             = "ServicePrincipal"
        description                = "${grant.description} (shared read)"
        condition                  = local.shared_read_conditions[key]
        condition_version          = "2.0"
      }
    },
    # Catalog listing cannot be scoped to a namespace - the role does not
    # accept ABAC conditions - so it is opt-in per tenant.
    {
      for key, principal in local.catalog_lister_principals : "catalog-${key}" => {
        role_definition_id_or_name = "Container Registry Repository Catalog Lister"
        principal_id               = principal.object_id
        principal_type             = principal.principal_type
        description                = principal.description
      }
    },
  )

  diagnostic_settings = var.log_analytics_workspace_resource_id == null ? {} : {
    to_law = {
      name                           = "diag-${var.registry_name}"
      workspace_resource_id          = var.log_analytics_workspace_resource_id
      log_categories                 = var.diagnostic_log_categories
      metric_categories              = ["AllMetrics"]
      log_analytics_destination_type = "Dedicated"
    }
  }

  lock = var.lock_registry ? {
    kind = "CanNotDelete"
    name = "lock-${var.registry_name}"
  } : null

  tags = var.tags

  depends_on = [azurerm_federated_identity_credential.ci]
}
