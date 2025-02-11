provider "google" {
  project = "your-project-id"
  region  = "us-central1"
}

resource "google_compute_network" "vpc_network" {
  name                    = "custom-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name          = "custom-subnet"
  region        = "us-central1"
  network       = google_compute_network.vpc_network.id
  ip_cidr_range = "10.0.0.0/24"
}

resource "google_compute_firewall" "allow-http-https" {
  name    = "allow-http-https"
  network = google_compute_network.vpc_network.id

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_instance_template" "default" {
  name         = "instance-template"
  machine_type = "e2-medium"

  disk {
    boot         = true
    auto_delete  = true
    source_image = "debian-cloud/debian-11"
  }

  network_interface {
    network    = google_compute_network.vpc_network.id
    subnetwork = google_compute_subnetwork.subnet.id
    access_config {}
  }

  metadata_startup_script = <<EOT
    #!/bin/bash
    <Docker compose>
  EOT
}

resource "google_compute_instance_group_manager" "default" {
  name               = "instance-group"
  base_instance_name = "vm"
  zone              = "us-central1-a"
  target_size       = 1

  version {
    instance_template = google_compute_instance_template.default.id
  }
}

resource "google_compute_health_check" "default" {
  name                = "http-health-check"
  timeout_sec         = 5
  check_interval_sec  = 10

  http_health_check {
    port = "80"
  }
}

resource "google_compute_backend_service" "default" {
  name                  = "backend-service"
  health_checks         = [google_compute_health_check.default.self_link]
  load_balancing_scheme = "EXTERNAL"

  backend {
    group = google_compute_instance_group_manager.default.instance_group
  }
}

resource "google_compute_url_map" "default" {
  name            = "url-map"
  default_service = google_compute_backend_service.default.self_link
}

resource "google_compute_target_https_proxy" "default" {
  name    = "https-proxy"
  url_map = google_compute_url_map.default.self_link
  ssl_certificates = [google_compute_ssl_certificate.default.self_link]
}

resource "google_compute_ssl_certificate" "default" {
  name        = "ssl-cert"
  private_key = file("./private-key.pem")
  certificate = file("./certificate.pem")
}

resource "google_compute_global_forwarding_rule" "https" {
  name                  = "https-forwarding-rule"
  target                = google_compute_target_https_proxy.default.self_link
  port_range            = "443"
  load_balancing_scheme = "EXTERNAL"
}

resource "google_dns_managed_zone" "default" {
  name        = "example-zone"
  dns_name    = "example.com."
  description = "Managed DNS zone for example.com"
}

resource "google_dns_record_set" "default" {
  name    = "www.example.com."
  type    = "A"
  ttl     = 300
  managed_zone = google_dns_managed_zone.default.name

  rrdatas = [
    google_compute_global_forwarding_rule.https.ip_address
  ]
}
