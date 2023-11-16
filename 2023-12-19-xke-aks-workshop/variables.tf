variable "deployment_locations" {
  type = list(object({
    # offset   = number
    # count    = number
    users = set(string)
    location = string
    vm_sku   = string
  }))
}