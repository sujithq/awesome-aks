terraform {
  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "= 2.45.0"
    }

    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 3.80.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }

    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}

data "azurerm_client_config" "xke" {}
data "azuread_domains" "xke" {}

resource "random_password" "xke" {
  length  = 16
  special = true
}

resource "random_string" "xke" {
  length  = 4
  lower   = true
  upper   = false
  special = false
}

resource "azurerm_resource_group" "xke" {
  name     = "rg-shared-xke"
  location = "westeurope"
  tags = {
    environment = "xke"
  }
}

resource "azurerm_log_analytics_workspace" "xke" {
  name                = "alogshared${random_string.xke.result}"
  resource_group_name = azurerm_resource_group.xke.name
  location            = azurerm_resource_group.xke.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = azurerm_resource_group.xke.tags
}

resource "azurerm_dashboard_grafana" "xke" {
  name                              = "amgshared${random_string.xke.result}"
  resource_group_name               = azurerm_resource_group.xke.name
  location                          = azurerm_resource_group.xke.location
  api_key_enabled                   = true
  deterministic_outbound_ip_enabled = true
  public_network_access_enabled     = true

  identity {
    type = "SystemAssigned"
  }
  tags = azurerm_resource_group.xke.tags
}

resource "azurerm_monitor_workspace" "xke" {
  name                = "amonshared${random_string.xke.result}"
  resource_group_name = azurerm_resource_group.xke.name
  location            = azurerm_resource_group.xke.location
  tags                = azurerm_resource_group.xke.tags
}

resource "azurerm_role_assignment" "xke_amg_rbac_me" {
  scope                = azurerm_dashboard_grafana.xke.id
  role_definition_name = "Grafana Admin"
  principal_id         = data.azurerm_client_config.xke.object_id
}

resource "azurerm_role_assignment" "xke_amon_rbac_amg" {
  scope                = azurerm_monitor_workspace.xke.id
  role_definition_name = "Monitoring Data Reader"
  principal_id         = azurerm_dashboard_grafana.xke.identity[0].principal_id
}

resource "azurerm_role_assignment" "xke_amon_rbac_me" {
  scope                = azurerm_monitor_workspace.xke.id
  role_definition_name = "Monitoring Data Reader"
  principal_id         = data.azurerm_client_config.xke.object_id
}

resource "azurerm_load_test" "xke" {
  name                = "altshared${random_string.xke.result}"
  resource_group_name = azurerm_resource_group.xke.name
  location            = azurerm_resource_group.xke.location
  tags                = azurerm_resource_group.xke.tags
}

module "xke" {
  source = "./modules/xke"

  for_each = { for u in var.deployment_locations : u.location => u }

  # user_count                        = each.value["count"]
  # user_offset                       = each.value["offset"]
  users    = each.value["users"]
  location = each.value["location"]
  vm_sku   = each.value["vm_sku"]
  # user_password                     = random_password.xke.result
  primary_domain                    = data.azuread_domains.xke.domains[6].domain_name
  unique_string                     = random_string.xke.result
  shared_resource_group_id          = azurerm_resource_group.xke.id
  shared_log_analytics_workspace_id = azurerm_log_analytics_workspace.xke.id
  managed_grafana_resource_id       = azurerm_dashboard_grafana.xke.id

  tags = azurerm_resource_group.xke.tags

  depends_on = [
    azurerm_resource_group.xke,
    azurerm_dashboard_grafana.xke,
    azurerm_monitor_workspace.xke,
    azurerm_role_assignment.xke_amg_rbac_me,
    azurerm_role_assignment.xke_amon_rbac_amg,
    azurerm_role_assignment.xke_amon_rbac_me,
  ]
}