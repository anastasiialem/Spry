# The FastAPI container on Cloud Run: the same image as docker compose's
# runtime target, no Lambda adapter. Scales to zero.

resource "google_artifact_registry_repository" "images" {
  repository_id = var.project_name
  location      = var.region
  format        = "DOCKER"
  description   = "Spry container images"

  # 0.5 GB is free: keep the last three images, delete the rest.
  cleanup_policies {
    id     = "keep-recent"
    action = "KEEP"
    most_recent_versions {
      keep_count = 3
    }
  }
  cleanup_policies {
    id     = "delete-old"
    action = "DELETE"
    condition {
      older_than = "86400s"
    }
  }

  depends_on = [google_project_service.this]
}

# Created by gcp/bootstrap (creating service accounts needs IAM admin, which the
# Terraform account deliberately does not have).
data "google_service_account" "api" {
  account_id = "${var.project_name}-api"
}

# The API may read its own secret, and no other.
resource "google_secret_manager_secret_iam_member" "api_database_url" {
  secret_id = google_secret_manager_secret.database_url.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${data.google_service_account.api.email}"
}

locals {
  site_origins = [
    "https://${var.project_id}.web.app",
    "https://${var.project_id}.firebaseapp.com",
  ]
}

resource "google_cloud_run_v2_service" "api" {
  name     = "${var.project_name}-api"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  deletion_protection = false

  template {
    service_account = data.google_service_account.api.email

    scaling {
      min_instance_count = 0
      max_instance_count = var.api_max_instances
    }

    # The Cloud SQL connector: a Unix socket at /cloudsql/<connection name>.
    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = [google_sql_database_instance.main.connection_name]
      }
    }

    containers {
      image = var.api_image

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        # Request-based billing: CPU only while a request is in flight.
        cpu_idle          = true
        startup_cpu_boost = true
      }

      env {
        name  = "APP_ENV"
        value = "production"
      }
      env {
        name  = "CORS_ORIGINS"
        value = join(",", local.site_origins)
      }
      env {
        name  = "COGNITO_REGION"
        value = var.cognito_region
      }
      env {
        name  = "COGNITO_USER_POOL_ID"
        value = var.cognito_user_pool_id
      }
      env {
        name  = "COGNITO_CLIENT_ID"
        value = var.cognito_client_id
      }
      env {
        name = "DATABASE_URL"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.database_url.secret_id
            version = "latest"
          }
        }
      }

      volume_mounts {
        name       = "cloudsql"
        mount_path = "/cloudsql"
      }

      # Migrations run at start (scripts/entrypoint.sh) before uvicorn listens.
      startup_probe {
        http_get {
          path = "/health"
        }
        initial_delay_seconds = 2
        period_seconds        = 3
        failure_threshold     = 20
      }
    }
  }

  lifecycle {
    # make gcp-deploy-backend rolls the image; Terraform owns everything else.
    ignore_changes = [
      template[0].containers[0].image,
      client,
      client_version,
    ]
  }

  # The secret must have a version before a revision can reference "latest".
  depends_on = [
    google_secret_manager_secret_iam_member.api_database_url,
    google_secret_manager_secret_version.database_url,
  ]
}

# Public: the API checks the Cognito access token itself on every /api route,
# and Firebase Hosting's /api/** rewrite calls it without Google credentials.
resource "google_cloud_run_v2_service_iam_member" "public" {
  name     = google_cloud_run_v2_service.api.name
  location = google_cloud_run_v2_service.api.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}
