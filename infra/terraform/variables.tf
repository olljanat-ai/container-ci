###############################################################################
# Subscription / placement
###############################################################################

variable "subscription_id" {
  type        = string
  default     = null
  description = "Azure subscription ID that hosts the registry. Falls back to `ARM_SUBSCRIPTION_ID` when null."
}

variable "location" {
  type        = string
  default     = "westeurope"
  description = "Azure region for the resource group and the registry's home replica."
}

variable "resource_group_name" {
  type        = string
  default     = "rg-container-registry"
  description = "Name of the resource group holding the registry. Created when `create_resource_group` is true."
}

variable "create_resource_group" {
  type        = bool
  default     = true
  description = "Create the resource group. Set to false to deploy into an existing one."
}

variable "registry_name" {
  type        = string
  description = <<DESCRIPTION
Globally unique name of the Azure Container Registry. 5-50 characters, alphanumeric only
(no hyphens). The login server becomes `<registry_name>.azurecr.io`.
DESCRIPTION

  validation {
    condition     = can(regex("^[a-zA-Z0-9]{5,50}$", var.registry_name))
    error_message = "registry_name must be 5-50 alphanumeric characters with no hyphens or underscores."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to every resource created by this configuration."
}

###############################################################################
# Registry configuration
###############################################################################

variable "sku" {
  type        = string
  default     = "Premium"
  description = <<DESCRIPTION
Registry SKU. Premium is the highest tier and the default here because this
configuration depends on Premium-only features: ABAC repository permissions used
for multi-tenancy, geo-replication, scope maps and tokens, cache rules, IP network
rules, and the untagged-manifest retention policy.
DESCRIPTION

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.sku)
    error_message = "sku must be one of Basic, Standard or Premium."
  }
}

variable "zone_redundancy_enabled" {
  type        = bool
  default     = true
  description = "Spread the registry across availability zones in its home region. Requires Premium and a region that offers zones."
}

variable "geo_replications" {
  type = list(object({
    location                  = string
    regional_endpoint_enabled = optional(bool, true)
    zone_redundancy_enabled   = optional(bool, true)
  }))
  default     = []
  description = <<DESCRIPTION
Additional regions to replicate the registry to. Each replica serves pulls from the
region closest to the client. Do not repeat `var.location` here.

- `location` - Azure region for the replica.
- `regional_endpoint_enabled` - Publish a region-specific data endpoint. Defaults to true.
- `zone_redundancy_enabled` - Spread the replica across zones. Defaults to true.
DESCRIPTION
}

variable "public_network_access_enabled" {
  type        = bool
  default     = true
  description = <<DESCRIPTION
Keep the registry reachable from the public internet. Left on by default so that
hosted CI runners (GitHub-hosted, GitLab SaaS, Microsoft-hosted Azure DevOps agents)
can push and pull without private networking. Access is still authenticated - see
`var.tenants` for how each project is limited to its own repositories.
DESCRIPTION
}

variable "allowed_ip_ranges" {
  type        = list(string)
  default     = []
  description = <<DESCRIPTION
Optional CIDR allowlist. Leave empty (the default) to accept traffic from any address,
which is what hosted CI runners with rotating egress IPs need. When you populate this
list the registry switches to deny-by-default and only these ranges are accepted.
DESCRIPTION
}

variable "network_rule_bypass_option" {
  type        = string
  default     = "AzureServices"
  description = "Allow trusted Azure services through the network rules. `AzureServices` or `None`."
}

variable "anonymous_pull_enabled" {
  type        = bool
  default     = false
  description = "Allow unauthenticated pulls from every repository in the registry. Off by default; it cannot be scoped per tenant."
}

variable "data_endpoint_enabled" {
  type        = bool
  default     = true
  description = "Serve layer downloads from dedicated per-region data endpoints instead of a shared wildcard endpoint. Makes client-side firewall rules tractable."
}

variable "quarantine_policy_enabled" {
  type        = bool
  default     = false
  description = "Hold newly pushed images in quarantine until a scanner marks them clean. Requires tooling that flips the quarantine flag; leave off unless that exists."
}

variable "retention_policy_in_days" {
  type        = number
  default     = 30
  description = "Days to keep untagged manifests before the registry deletes them. Set to null to keep untagged manifests forever."
}

variable "export_policy_enabled" {
  type        = bool
  default     = true
  description = "Allow artifacts to be exported from the registry. Can only be disabled when public network access is also disabled."
}

variable "role_assignment_mode" {
  type        = string
  default     = "AbacRepositoryPermissions"
  description = <<DESCRIPTION
Repository authorization mode.

- `AbacRepositoryPermissions` - "RBAC Registry + ABAC Repository Permissions". Required for
  the per-tenant repository scoping this configuration builds. Legacy `AcrPull`/`AcrPush`/
  `AcrDelete` role assignments are NOT honoured in this mode.
- `LegacyRegistryPermissions` - registry-wide `AcrPull`/`AcrPush` only, no repository scoping.

Switching an existing registry between modes invalidates cached registry credentials.
See docs/index.html or the ACR migration guide before changing this on a live registry.
DESCRIPTION

  validation {
    condition     = contains(["LegacyRegistryPermissions", "AbacRepositoryPermissions"], var.role_assignment_mode)
    error_message = "role_assignment_mode must be either LegacyRegistryPermissions or AbacRepositoryPermissions."
  }
}

variable "lock_registry" {
  type        = bool
  default     = false
  description = "Apply a CanNotDelete management lock to the registry. Recommended for production."
}

###############################################################################
# Diagnostics
###############################################################################

variable "log_analytics_workspace_resource_id" {
  type        = string
  default     = null
  description = "Resource ID of a Log Analytics workspace to send registry logs and metrics to. Diagnostics are skipped when null."
}

variable "diagnostic_log_categories" {
  type        = list(string)
  default     = ["ContainerRegistryLoginEvents", "ContainerRegistryRepositoryEvents"]
  description = "Registry log categories forwarded to Log Analytics. Login events give you the audit trail of who authenticated; repository events cover push, pull and delete."
}

###############################################################################
# Upstream caching
###############################################################################

variable "cache_rules" {
  type = map(object({
    name              = string
    source_repository = string
    target_repository = string
  }))
  default = {
    docker_hub_library = {
      name              = "docker-hub-library"
      source_repository = "docker.io/library/*"
      target_repository = "cache/docker-hub/library/*"
    }
    mcr = {
      name              = "mcr"
      source_repository = "mcr.microsoft.com/*"
      target_repository = "cache/mcr/*"
    }
  }
  description = <<DESCRIPTION
Pull-through cache rules. Builds that reference `<login_server>/cache/...` base images
pull through the registry instead of hitting Docker Hub directly, which removes the
anonymous rate limit from the critical path of every build.

The defaults cache unauthenticated upstreams only. Add `credential_sets` if you need
authenticated Docker Hub pulls.
DESCRIPTION
}

variable "credential_sets" {
  type = map(object({
    name         = string
    login_server = string
    auth_credentials = list(object({
      name                       = optional(string, "Credential1")
      username_secret_identifier = string
      password_secret_identifier = string
    }))
  }))
  default     = {}
  description = "Key Vault backed credentials for authenticated pull-through caching. Each credential set's managed identity needs `Key Vault Secrets User` on the referenced secrets."
}

###############################################################################
# Multi-tenancy
###############################################################################

variable "shared_read_namespaces" {
  type        = list(string)
  default     = ["shared/", "cache/"]
  description = <<DESCRIPTION
Repository prefixes every tenant may read, on top of its own namespaces. Use this for
golden base images and the pull-through cache. Each entry must end with `/` so that
`shared/` cannot accidentally match `shared-secrets/`.
DESCRIPTION

  validation {
    condition     = alltrue([for prefix in var.shared_read_namespaces : endswith(prefix, "/")])
    error_message = "Every entry in shared_read_namespaces must end with a trailing slash."
  }
}

variable "tenants" {
  type = map(object({
    display_name          = optional(string, null)
    repository_namespaces = optional(list(string), null)
    extra_read_namespaces = optional(list(string), [])
    catalog_lister        = optional(bool, false)

    principals = optional(map(object({
      object_id      = string
      access         = string
      principal_type = optional(string, "ServicePrincipal")
      description    = optional(string, null)
    })), {})

    ci_identities = optional(map(object({
      access   = optional(string, "push")
      issuer   = string
      subject  = string
      audience = optional(string, "api://AzureADTokenExchange")
    })), {})

    token = optional(object({
      access          = optional(string, "pull")
      repositories    = list(string)
      password_expiry = optional(string, null)
    }), null)
  }))
  default     = {}
  description = <<DESCRIPTION
Tenants (projects or teams) sharing this registry. Each tenant owns one or more
repository namespaces and can only reach repositories under those prefixes. The map
key is the tenant's short name and is used to derive defaults.

- `display_name` - Human readable name used in role assignment descriptions. Defaults to the map key.
- `repository_namespaces` - Repository prefixes the tenant owns. Defaults to `["<key>/"]`.
  Every entry must end with `/`; without the trailing slash `team-a` would also match
  `team-a-archive/nginx`.
- `extra_read_namespaces` - Additional prefixes this tenant may read but not write.
- `catalog_lister` - Grant `Container Registry Repository Catalog Lister`. This role does not
  support ABAC conditions, so it lets the tenant list every repository name in the registry
  (names only, no content). Off by default.
- `principals` - Existing Entra identities to grant access to. `object_id` is the principal's
  object ID (for a managed identity, its principal ID; for an app registration, the service
  principal object ID, not the application ID). `access` is one of:
  - `pull`       -> Container Registry Repository Reader
  - `push`       -> Container Registry Repository Writer  (read + write, no delete)
  - `contribute` -> Container Registry Repository Contributor (read + write + delete)
- `ci_identities` - User-assigned managed identities created for this tenant's pipelines,
  each with a federated credential so the pipeline authenticates without a stored secret.
  `issuer` and `subject` come from the CI platform - see infra/terraform/README.md.
- `token` - Optional non-Entra repository-scoped token (username + password) for runners that
  cannot do workload identity federation. `repositories` must list full repository names;
  ACR scope maps do not accept prefixes. Prefer `ci_identities` wherever possible.
DESCRIPTION

  validation {
    condition = alltrue([
      for tenant in values(var.tenants) :
      alltrue([for prefix in coalesce(tenant.repository_namespaces, ["placeholder/"]) : endswith(prefix, "/")])
    ])
    error_message = "Every repository_namespaces entry must end with a trailing slash, e.g. \"team-a/\"."
  }

  validation {
    condition = alltrue([
      for tenant in values(var.tenants) :
      alltrue([for prefix in tenant.extra_read_namespaces : endswith(prefix, "/")])
    ])
    error_message = "Every extra_read_namespaces entry must end with a trailing slash."
  }

  validation {
    condition = alltrue(flatten([
      for tenant in values(var.tenants) : [
        for principal in values(tenant.principals) : contains(["pull", "push", "contribute"], principal.access)
      ]
    ]))
    error_message = "principals[*].access must be one of pull, push or contribute."
  }

  validation {
    condition = alltrue(flatten([
      for tenant in values(var.tenants) : [
        for identity in values(tenant.ci_identities) : contains(["pull", "push", "contribute"], identity.access)
      ]
    ]))
    error_message = "ci_identities[*].access must be one of pull, push or contribute."
  }

  validation {
    condition = alltrue([
      for tenant in values(var.tenants) :
      tenant.token == null ? true : contains(["pull", "push", "contribute"], tenant.token.access)
    ])
    error_message = "token.access must be one of pull, push or contribute."
  }
}
