output "load_balancer_ip" {
  description = "External IP address of the HTTP load balancer"
  value       = google_compute_global_forwarding_rule.web_forwarding.ip_address
}

output "instance_group_size" {
  description = "Number of instances in the managed instance group"
  value       = google_compute_region_instance_group_manager.webserver_mig.target_size
}

output "custom_image_name" {
  description = "Name of the custom image used for all VMs"
  value       = google_compute_image.webserver_image.name
}

output "subnet_self_link" {
  description = "Self-link of the subnet created by the network module"
  value = try(
    module.network.subnets_self_links["${var.region}/${var.subnet_name}"],
    module.network.subnets_self_links[0]
  )
}
