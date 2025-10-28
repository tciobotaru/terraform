########################################################
# Provider Configuration
########################################################
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

########################################################
# Network Module (v12)
########################################################
module "network" {
  source  = "terraform-google-modules/network/google"
  version = "~> 12.0"

  project_id   = var.project_id
  network_name = var.network_name
  routing_mode = "REGIONAL"

  subnets = [
    {
      subnet_name   = var.subnet_name
      subnet_ip     = var.subnet_cidr
      subnet_region = var.region
    }
  ]

  firewall_rules = [
    {
      name        = "allow-http"
      description = "Allow HTTP from restricted IP range"
      direction   = "INGRESS"
      ranges      = var.allowed_ip_ranges
      allow = [{
        protocol = "tcp"
        ports    = ["80"]
      }]
      target_tags = ["web-server"]
    }
  ]
}

########################################################
# Local Values to Handle Subnet Self-Link
########################################################
locals {
  subnet_key = "${var.region}/${var.subnet_name}"

  subnet_self_link = try(
    module.network.subnets_self_links[local.subnet_key],
    module.network.subnets_self_links[0]
  )
}

########################################################
# Temporary VM (used to create custom image)
########################################################
resource "google_compute_instance" "temp_vm" {
  name         = "temp-vm-apache"
  machine_type = "e2-medium"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-12"
      size  = 10
    }
    auto_delete = true
  }

  network_interface {
    network    = module.network.network_self_link
    subnetwork = local.subnet_self_link
    access_config {}
  }

  metadata_startup_script = file("${path.module}/startup-script.sh")
  tags                    = ["web-server"]

  lifecycle {
    prevent_destroy = false
  }
}

########################################################
# Stop Temp VM Before Creating Image
########################################################
resource "null_resource" "stop_temp_vm" {
  depends_on = [google_compute_instance.temp_vm]

  provisioner "local-exec" {
    
    command = <<EOT
    echo "Sleeping 60s to allow startup script to finish..."
    sleep 60
    gcloud compute instances stop ${google_compute_instance.temp_vm.name} --zone ${var.zone} --project ${var.project_id}
  EOT
  }
}

########################################################
# Custom Image from Temp VM
########################################################
resource "google_compute_image" "webserver_image" {
  name           = "webserver-custom-image"
  source_disk    = google_compute_instance.temp_vm.boot_disk[0].source
  depends_on     = [null_resource.stop_temp_vm]
}

########################################################
# Instance Template for Managed Instance Group
########################################################
resource "google_compute_instance_template" "webserver_template" {
  name         = "webserver-template"
  machine_type = "e2-medium"

  disk {
    source_image = google_compute_image.webserver_image.self_link
    auto_delete  = true
    boot         = true
  }

  network_interface {
    network    = module.network.network_self_link
    subnetwork = local.subnet_self_link
    access_config {}
  }
  metadata_startup_script = <<-EOT
  #!/bin/bash
  echo "<h1>Welcome from $(hostname)</h1>" > /var/www/html/index.html
  systemctl restart apache2
  EOT

  tags = ["web-server"]
}

########################################################
# Managed Instance Group
########################################################
resource "google_compute_region_instance_group_manager" "webserver_mig" {
  name               = "webserver-mig"
  region             = var.region
  base_instance_name = "webserver"

  version {
    instance_template = google_compute_instance_template.webserver_template.self_link
  }

  target_size = 3
}

########################################################
# HTTP Health Check
########################################################
resource "google_compute_health_check" "http_health" {
  name                = "webserver-health-check"
  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 2

  http_health_check {
    request_path = "/"
    port         = 80
  }
}

########################################################
# Backend Service for Load Balancer
########################################################
resource "google_compute_backend_service" "web_backend" {
  name          = "web-backend-service"
  port_name     = "http"
  protocol      = "HTTP"
  health_checks = [google_compute_health_check.http_health.id]
  timeout_sec   = 10

  backend {
    group = google_compute_region_instance_group_manager.webserver_mig.instance_group
  }
}

########################################################
# URL Map for HTTP Load Balancer
########################################################
resource "google_compute_url_map" "web_url_map" {
  name            = "web-url-map"
  default_service = google_compute_backend_service.web_backend.id
}

########################################################
# HTTP Target Proxy
########################################################
resource "google_compute_target_http_proxy" "web_proxy" {
  name    = "web-proxy"
  url_map = google_compute_url_map.web_url_map.id
}

########################################################
# Global Forwarding Rule
########################################################
resource "google_compute_global_forwarding_rule" "web_forwarding" {
  name        = "web-forwarding-rule"
  target      = google_compute_target_http_proxy.web_proxy.id
  port_range  = "80"
  ip_protocol = "TCP"
}

########################################################
# Firewall Rule to Allow LB Traffic
########################################################
resource "google_compute_firewall" "allow_lb_http" {
  name    = "allow-lb-http"
  network = module.network.network_self_link

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = var.allowed_ip_ranges
  target_tags   = ["web-server"]
}


