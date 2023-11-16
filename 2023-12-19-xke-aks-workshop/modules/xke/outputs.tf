# output "users" {
#   value = flatten([data.azuread_user.xke.*.user_principal_name])
# }

# output "resource_groups" {
#   value = flatten([azurerm_resource_group.xke.*.name])
# }

# output "aks_clusters" {
#   value = flatten([azurerm_kubernetes_cluster.xke.*.name])
# }