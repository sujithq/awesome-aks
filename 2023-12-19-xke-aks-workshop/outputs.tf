# output "module_outputs" {
#   value = flatten(module.xke[*])
# }

# output "user_password" {
#   value     = random_password.xke.result
#   sensitive = true
# }

# locals {
#   all_locations = [
#     for deploy in var.deployment_locations : deploy.location
#   ]

#   all_users = flatten([
#     for loc in local.all_locations :
#     flatten([
#       for deploy in module.xke.* : deploy[loc].users
#     ])
#   ])

#   all_resource_groups = flatten([
#     for loc in local.all_locations :
#     flatten([
#       for deploy in module.xke.* : deploy[loc].resource_groups
#     ])
#   ])

#   all_aks_clusters = flatten([
#     for loc in local.all_locations :
#     flatten([
#       for deploy in module.xke.* : deploy[loc].aks_clusters
#     ])
#   ])
# }

# output "users" {
#   value = local.all_users
# }

# output "resource_groups" {
#   value = local.all_resource_groups
# }

# output "aks_clusters" {
#   value = local.all_aks_clusters
# }