terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.8.0"
    }
  }

  backend "gcs" {
    bucket = "toma-bucket"
  }
}
