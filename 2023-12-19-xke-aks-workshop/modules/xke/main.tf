data "azurerm_client_config" "xke" {}

data "azuread_user" "xke" {
  for_each = var.users
  user_principal_name = "${each.key}@${var.primary_domain}"
}

resource "azurerm_resource_group" "xke" {
  for_each = var.users
  name     = "rg-user-${each.key}"
  location = var.location
}

resource "azurerm_role_assignment" "xke_rg_rbac_user" {
  for_each = var.users
  role_definition_name = "Owner"
  scope                = azurerm_resource_group.xke[each.key].id
  principal_id         = data.azuread_user.xke[each.key].object_id
}

# resource "azuread_application" "xke" {
#   for_each = var.users
#   display_name = "xke user ${each.key}"
#   owners       = [data.azuread_user.xke[each.key].object_id]
# }

# resource "azuread_service_principal" "xke" {
#   for_each = var.users
#   client_id               = azuread_application.xke[each.key].client_id
#   app_role_assignment_required = true
#   owners                       = [data.azuread_user.xke[each.key].object_id]
# }

# resource "azurerm_role_assignment" "xke_sp_rbac" {
#   for_each = var.users
#   scope                = azurerm_resource_group.xke[each.key].id
#   role_definition_name = "Owner"
#   principal_id         = azuread_service_principal.xke[each.key].object_id
# }

resource "azurerm_container_registry" "xke" {
  for_each = var.users
  name                   = "acruser${each.key}${var.unique_string}"
  resource_group_name    = azurerm_resource_group.xke[each.key].name
  location               = azurerm_resource_group.xke[each.key].location
  sku                    = "Standard"
  admin_enabled          = true
  anonymous_pull_enabled = true
}

# locals {
#   filtered_users = [for user in var.users : user 
#                     if data.azuread_user.xke[user].object_id != data.azurerm_client_config.xke.object_id]
# }

variable "filtered_users" {
  description = "List of users that meet the condition"
  type        = list(string)
  default     = []
}

locals {
  filtered_users_map = {
    for user_key, user in var.users :
    user_key => user if data.azuread_user.xke[user_key].object_id != data.azurerm_client_config.xke.object_id
  }

  filtered_users = [for user_key, _ in local.filtered_users_map : user_key]
}

resource "azurerm_kubernetes_cluster" "xke" {
  for_each = var.users
  name                = "aks-user-${each.key}"
  resource_group_name = azurerm_resource_group.xke[each.key].name
  location            = azurerm_resource_group.xke[each.key].location
  dns_prefix          = "aks-user-${each.key}"

  default_node_pool {
    name                = "default"
    enable_auto_scaling = true
    max_count           = 2
    min_count           = 1
    vm_size             = var.vm_sku
  }

  oms_agent {
    log_analytics_workspace_id = var.shared_log_analytics_workspace_id
  }

  identity {
    type = "SystemAssigned"
  }

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "1m"
  }

  service_mesh_profile {
    mode = "Istio"
    external_ingress_gateway_enabled = true
  }

  workload_autoscaler_profile {
    keda_enabled = true
  }

  # web_app_routing {
  #   dns_zone_id = ""
  # }

  lifecycle {
    ignore_changes = [
      monitor_metrics
    ]
  }
}

resource "azurerm_role_assignment" "xke_acr_rbac_aks" {
  for_each = var.users
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.xke[each.key].id
  principal_id                     = azurerm_kubernetes_cluster.xke[each.key].kubelet_identity[0].object_id
  skip_service_principal_aad_check = true
}

# use local provisioner to enable istio ingress gateway on each AKS cluster
resource "null_resource" "xke" {
  for_each = var.users

  provisioner "local-exec" {
    command = "az aks mesh enable-ingress-gateway --resource-group ${azurerm_resource_group.xke[each.key].name} --name ${azurerm_kubernetes_cluster.xke[each.key].name} --ingress-gateway-type external"
  }

  depends_on = [
    azurerm_kubernetes_cluster.xke,
  ]
}

# resource "azurerm_storage_account" "xke" {
#   count                    = var.user_count
#   name                     = "sauser${each.key}${var.unique_string}"
#   resource_group_name      = azurerm_resource_group.xke[each.key].name
#   location                 = azurerm_resource_group.xke[each.key].location
#   account_tier             = "Standard"
#   account_replication_type = "LRS"
# }

# resource "azurerm_storage_share" "xke" {
#   for_each = var.users
#   name                 = "cloudshell"
#   storage_account_name = azurerm_storage_account.xke[each.key].name
#   access_tier          = "Hot"
#   quota                = 6
# }

resource "azurerm_user_assigned_identity" "xke" {
  for_each = var.users
  location            = azurerm_resource_group.xke[each.key].location
  resource_group_name = azurerm_resource_group.xke[each.key].name
  name                = "aks-user${each.key}-identity"
}

resource "azurerm_federated_identity_credential" "xke_ava" {
  for_each = var.users
  name                = "aks-user${each.key}-federated-default"
  resource_group_name = azurerm_resource_group.xke[each.key].name
  issuer              = azurerm_kubernetes_cluster.xke[each.key].oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.xke[each.key].id
  subject             = "system:serviceaccount:default:azure-voting-app-serviceaccount"
  audience = [
    "api://AzureADTokenExchange"
  ]
}

resource "azurerm_federated_identity_credential" "xke_rat" {
  for_each = var.users
  name                = "aks-user${each.key}-federated-ratify"
  resource_group_name = azurerm_resource_group.xke[each.key].name
  issuer              = azurerm_kubernetes_cluster.xke[each.key].oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.xke[each.key].id
  subject             = "system:serviceaccount:gatekeeper-system:ratify-admin"
  audience = [
    "api://AzureADTokenExchange"
  ]
}

resource "azurerm_key_vault" "xke" {
  for_each = var.users
  name                       = "akvuser${each.key}${var.unique_string}"
  location                   = azurerm_resource_group.xke[each.key].location
  resource_group_name        = azurerm_resource_group.xke[each.key].name
  tenant_id                  = data.azurerm_client_config.xke.tenant_id
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  sku_name                   = "standard"

  access_policy {
    tenant_id = data.azurerm_client_config.xke.tenant_id
    object_id = data.azurerm_client_config.xke.object_id

    certificate_permissions = [
      "Backup",
      "Create",
      "Delete",
      "DeleteIssuers",
      "Get",
      "GetIssuers",
      "Import",
      "List",
      "ListIssuers",
      "ManageContacts",
      "ManageIssuers",
      "Purge",
      "Recover",
      "Restore",
      "SetIssuers",
      "Update"
    ]

    key_permissions = [
      "Backup",
      "Create",
      "Decrypt",
      "Delete",
      "Encrypt",
      "Get",
      "Import",
      "List",
      "Purge",
      "Recover",
      "Restore",
      "Sign",
      "UnwrapKey",
      "Update",
      "Verify",
      "WrapKey",
      "Release",
      "Rotate",
      "GetRotationPolicy",
      "SetRotationPolicy"
    ]

    secret_permissions = [
      "Backup",
      "Delete",
      "Get",
      "List",
      "Purge",
      "Recover",
      "Restore",
      "Set"
    ]

    storage_permissions = [
      "Backup",
      "Delete",
      "DeleteSAS",
      "Get",
      "GetSAS",
      "List",
      "ListSAS",
      "Purge",
      "Recover",
      "RegenerateKey",
      "Restore",
      "Set",
      "SetSAS",
      "Update"
    ]
  }

  access_policy {
    tenant_id = data.azurerm_client_config.xke.tenant_id
    object_id = data.azuread_user.xke[each.key].object_id

    certificate_permissions = [
      "Backup",
      "Create",
      "Delete",
      "DeleteIssuers",
      "Get",
      "GetIssuers",
      "Import",
      "List",
      "ListIssuers",
      "ManageContacts",
      "ManageIssuers",
      "Purge",
      "Recover",
      "Restore",
      "SetIssuers",
      "Update"
    ]

    key_permissions = [
      "Backup",
      "Create",
      "Decrypt",
      "Delete",
      "Encrypt",
      "Get",
      "Import",
      "List",
      "Purge",
      "Recover",
      "Restore",
      "Sign",
      "UnwrapKey",
      "Update",
      "Verify",
      "WrapKey",
      "Release",
      "Rotate",
      "GetRotationPolicy",
      "SetRotationPolicy"
    ]

    secret_permissions = [
      "Backup",
      "Delete",
      "Get",
      "List",
      "Purge",
      "Recover",
      "Restore",
      "Set"
    ]

    storage_permissions = [
      "Backup",
      "Delete",
      "DeleteSAS",
      "Get",
      "GetSAS",
      "List",
      "ListSAS",
      "Purge",
      "Recover",
      "RegenerateKey",
      "Restore",
      "Set",
      "SetSAS",
      "Update"
    ]
  }

  access_policy {
    tenant_id = data.azurerm_client_config.xke.tenant_id
    object_id = azurerm_user_assigned_identity.xke[each.key].principal_id

    key_permissions = [
      "Get",
    ]

    secret_permissions = [
      "Get",
    ]

    certificate_permissions = [
      "Get"
    ]
  }
}

resource "azurerm_key_vault_certificate" "ratify-cert" {
  for_each = var.users
  name         = "ratify"
  key_vault_id = azurerm_key_vault.xke[each.key].id

  certificate_policy {
    issuer_parameters {
      name = "Self"
    }

    key_properties {
      exportable = true
      key_size   = 2048
      key_type   = "RSA"
      reuse_key  = true
    }

    lifetime_action {
      action {
        action_type = "AutoRenew"
      }

      trigger {
        days_before_expiry = 30
      }
    }

    secret_properties {
      content_type = "application/x-pkcs12"
    }

    x509_certificate_properties {
      extended_key_usage = ["1.3.6.1.5.5.7.3.3"]

      key_usage = [
        "digitalSignature",
      ]

      subject            = "CN=example.com"
      validity_in_months = 12
    }
  }
}

resource "azurerm_role_assignment" "xke_amg_rbac_user" {
  for_each = { for user in var.filtered_users : user => local.filtered_users_map[user] }
  scope                = var.managed_grafana_resource_id
  role_definition_name = "Grafana Admin"
  principal_id         = data.azuread_user.xke[each.key].object_id
}

resource "azurerm_role_assignment" "xke_amg_rbac_useridentity" {
  for_each = var.users
  scope                = var.managed_grafana_resource_id
  role_definition_name = "Grafana Admin"
  principal_id         = azurerm_user_assigned_identity.xke[each.key].principal_id
}

resource "azurerm_role_assignment" "xke_mcrg_rbac_user" {
  for_each = { for user in var.filtered_users : user => local.filtered_users_map[user] }
  role_definition_name = "Owner"
  scope                = azurerm_kubernetes_cluster.xke[each.key].node_resource_group_id
  principal_id         = data.azuread_user.xke[each.key].object_id
}

resource "azurerm_role_assignment" "xke_sharedrg_rbac_user" {
  for_each = { for user in var.filtered_users : user => local.filtered_users_map[user] }
  role_definition_name = "Owner"
  scope                = var.shared_resource_group_id
  principal_id         = data.azuread_user.xke[each.key].object_id
}