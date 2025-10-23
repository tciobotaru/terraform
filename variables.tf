variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type = string
}

variable "network_name" {
  type = string
}

variable "subnet_name" {
  type = string
}

variable "subnet_cidr" {
  type = string
}

variable "allowed_ip_ranges" {
  type = list(string)
}

variable "zone" {
  type = string
}