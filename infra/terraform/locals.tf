locals {
  ###########################################################################
  # ACR repository data actions, grouped by access level.
  #
  # An ABAC condition only constrains the actions it names. Any data action
  # left out of the condition stays registry-wide, so each level must list
  # every data action its role carries.
  #
  #   Container Registry Repository Reader      -> repository_actions.pull
  #   Container Registry Repository Writer      -> repository_actions.push
  #   Container Registry Repository Contributor -> repository_actions.contribute
  ###########################################################################
  repository_actions = {
    pull = [
      "Microsoft.ContainerRegistry/registries/repositories/content/read",
      "Microsoft.ContainerRegistry/registries/repositories/metadata/read",
    ]
    push = [
      "Microsoft.ContainerRegistry/registries/repositories/content/read",
      "Microsoft.ContainerRegistry/registries/repositories/content/write",
      "Microsoft.ContainerRegistry/registries/repositories/metadata/read",
      "Microsoft.ContainerRegistry/registries/repositories/metadata/write",
    ]
    contribute = [
      "Microsoft.ContainerRegistry/registries/repositories/content/delete",
      "Microsoft.ContainerRegistry/registries/repositories/content/read",
      "Microsoft.ContainerRegistry/registries/repositories/content/write",
      "Microsoft.ContainerRegistry/registries/repositories/metadata/delete",
      "Microsoft.ContainerRegistry/registries/repositories/metadata/read",
      "Microsoft.ContainerRegistry/registries/repositories/metadata/write",
    ]
  }

  repository_roles = {
    pull       = "Container Registry Repository Reader"
    push       = "Container Registry Repository Writer"
    contribute = "Container Registry Repository Contributor"
  }

  # Scope map actions use a different grammar to ABAC conditions:
  # `repositories/<repository>/<content|metadata>/<verb>`.
  scope_map_actions = {
    pull       = ["content/read", "metadata/read"]
    push       = ["content/read", "content/write", "metadata/read", "metadata/write"]
    contribute = ["content/delete", "content/read", "content/write", "metadata/delete", "metadata/read", "metadata/write"]
  }

  ###########################################################################
  # Tenant normalisation
  ###########################################################################
  tenants = {
    for key, tenant in var.tenants : key => {
      display_name = coalesce(tenant.display_name, key)

      # Namespaces the tenant may write to.
      write_namespaces = coalesce(tenant.repository_namespaces, ["${key}/"])

      # Namespaces the tenant may read: its own, plus registry-wide shared
      # namespaces, plus anything explicitly granted to it.
      read_namespaces = distinct(concat(
        coalesce(tenant.repository_namespaces, ["${key}/"]),
        var.shared_read_namespaces,
        tenant.extra_read_namespaces,
      ))

      catalog_lister = tenant.catalog_lister
      principals     = tenant.principals
      ci_identities  = tenant.ci_identities
      token          = tenant.token
    }
  }

  ###########################################################################
  # Every principal that needs a repository-scoped role assignment, flattened
  # into a single map keyed by "<tenant>-<name>-<access>".
  #
  # `pull` grants use the read namespaces so a tenant can also consume shared
  # base images; `push` and `contribute` stay inside the tenant's own
  # namespaces, so nobody can write into another tenant's or the shared space.
  ###########################################################################
  tenant_principal_grants = merge([
    for tenant_key, tenant in local.tenants : {
      for principal_key, principal in tenant.principals :
      "${tenant_key}-${principal_key}-${principal.access}" => {
        tenant_key     = tenant_key
        access         = principal.access
        object_id      = principal.object_id
        principal_type = principal.principal_type
        namespaces     = principal.access == "pull" ? tenant.read_namespaces : tenant.write_namespaces
        description = coalesce(
          principal.description,
          "${tenant.display_name}: ${principal.access} on ${join(", ", principal.access == "pull" ? tenant.read_namespaces : tenant.write_namespaces)}"
        )
      }
    }
  ]...)

  ci_identity_grants = merge([
    for tenant_key, tenant in local.tenants : {
      for identity_key, identity in tenant.ci_identities :
      "${tenant_key}-${identity_key}" => {
        tenant_key = tenant_key
        access     = identity.access
        issuer     = identity.issuer
        subject    = identity.subject
        audience   = identity.audience
        namespaces = identity.access == "pull" ? tenant.read_namespaces : tenant.write_namespaces
        # User-assigned managed identity names are limited to 3-128 characters
        # of letters, digits and hyphens.
        name        = "id-${var.registry_name}-${tenant_key}-${identity_key}"
        description = "${tenant.display_name} CI identity ${identity_key}: ${identity.access}"
      }
    }
  ]...)

  # `pull` identities also need to reach the shared read namespaces, which are
  # outside their own write namespaces. Push and contribute identities already
  # get read access to shared namespaces through this second assignment.
  ci_identity_shared_read_grants = {
    for key, grant in local.ci_identity_grants : key => grant
    if grant.access != "pull" && length(setsubtract(local.tenants[grant.tenant_key].read_namespaces, grant.namespaces)) > 0
  }

  catalog_lister_principals = merge([
    for tenant_key, tenant in local.tenants : merge(
      {
        for principal_key, principal in tenant.principals :
        "${tenant_key}-${principal_key}" => {
          object_id      = principal.object_id
          principal_type = principal.principal_type
          description    = "${tenant.display_name}: list repository names"
        } if tenant.catalog_lister
      },
      {
        for identity_key, identity in tenant.ci_identities :
        "${tenant_key}-ci-${identity_key}" => {
          object_id      = azurerm_user_assigned_identity.ci["${tenant_key}-${identity_key}"].principal_id
          principal_type = "ServicePrincipal"
          description    = "${tenant.display_name}: list repository names"
        } if tenant.catalog_lister
      },
    )
  ]...)

  ###########################################################################
  # Repository-scoped tokens (scope maps) for runners that cannot federate.
  ###########################################################################
  tenant_scope_maps = {
    for tenant_key, tenant in local.tenants :
    tenant_key => {
      name        = "sm-${tenant_key}"
      description = "${tenant.display_name}: ${tenant.token.access} on ${join(", ", tenant.token.repositories)}"
      actions = flatten([
        for repository in tenant.token.repositories : [
          for action in local.scope_map_actions[tenant.token.access] : "repositories/${repository}/${action}"
        ]
      ])
      registry_tokens = {
        default = {
          name    = "tok-${tenant_key}"
          enabled = true
          passwords = {
            password1 = {
              expiry = tenant.token.password_expiry
            }
          }
        }
      }
    } if tenant.token != null
  }
}

###############################################################################
# Renders one ABAC condition per grant.
#
# The condition reads: "unless the caller is performing one of these repository
# data actions, this assignment says nothing; if they are, the repository name
# must start with one of the tenant's prefixes."
#
# Actions the condition does not name are unaffected, which is why
# local.repository_actions lists every data action the matching role carries.
###############################################################################
locals {
  abac_conditions = {
    for key, grant in merge(local.tenant_principal_grants, local.ci_identity_grants) :
    key => format(
      "(\n (\n  %s\n )\n OR \n (\n  %s\n )\n)",
      join("\n  AND\n  ", [
        for action in local.repository_actions[grant.access] : "!(ActionMatches{'${action}'})"
      ]),
      join("\n  OR\n  ", [
        for namespace in sort(grant.namespaces) :
        "@Request[Microsoft.ContainerRegistry/registries/repositories:name] StringStartsWithIgnoreCase '${namespace}'"
      ]),
    )
  }

  # Read-only condition covering the shared namespaces a push/contribute
  # identity is not otherwise allowed to read.
  shared_read_conditions = {
    for key, grant in local.ci_identity_shared_read_grants :
    key => format(
      "(\n (\n  %s\n )\n OR \n (\n  %s\n )\n)",
      join("\n  AND\n  ", [
        for action in local.repository_actions.pull : "!(ActionMatches{'${action}'})"
      ]),
      join("\n  OR\n  ", [
        for namespace in sort(local.tenants[grant.tenant_key].read_namespaces) :
        "@Request[Microsoft.ContainerRegistry/registries/repositories:name] StringStartsWithIgnoreCase '${namespace}'"
      ]),
    )
  }
}
