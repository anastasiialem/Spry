# Cloud SQL for PostgreSQL 17, the smallest shared-core tier. Unlike Aurora
# Serverless it never pauses: it bills by the hour until db_activation_policy
# is NEVER (stopped) or terraform destroy (deleted).

resource "google_sql_database_instance" "main" {
  name             = "${var.project_name}-db"
  database_version = "POSTGRES_17"
  region           = var.region

  # A lab database: terraform destroy must be able to delete it.
  deletion_protection = false

  settings {
    # Shared-core tiers exist only in Enterprise edition (PG 16+ defaults to Plus).
    edition           = "ENTERPRISE"
    tier              = var.db_tier
    activation_policy = var.db_activation_policy
    availability_type = "ZONAL"

    disk_type       = "PD_SSD"
    disk_size       = 10
    disk_autoresize = false

    deletion_protection_enabled = false

    # Public IP but no authorized networks: nothing can connect directly. Cloud
    # Run reaches it through the Cloud SQL connector (IAM-authorised, TLS), so
    # no VPC, connector or private IP range is needed.
    ip_configuration {
      ipv4_enabled = true
      ssl_mode     = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled = false
    }

    user_labels = {
      project    = var.project_name
      managed-by = "terraform"
    }
  }

  depends_on = [google_project_service.this]
}

resource "google_sql_database" "app" {
  name     = var.project_name
  instance = google_sql_database_instance.main.name
}

resource "random_password" "db" {
  length  = 32
  special = false
}

resource "google_sql_user" "app" {
  name     = var.project_name
  instance = google_sql_database_instance.main.name
  password = random_password.db.result
}

# The whole connection string is the secret, so the app reads DATABASE_URL as
# before and needs no code for Secret Manager. The host is the Unix socket the
# Cloud SQL connector mounts at /cloudsql/<connection name> in Cloud Run.
# Like every generated password, it is also in the Terraform state (HCP,
# encrypted at rest); it is never in Git.
resource "google_secret_manager_secret" "database_url" {
  secret_id = "${var.project_name}-database-url"

  replication {
    auto {}
  }

  depends_on = [google_project_service.this]
}

resource "google_secret_manager_secret_version" "database_url" {
  secret = google_secret_manager_secret.database_url.id
  secret_data = format(
    "postgresql+asyncpg://%s:%s@/%s?host=/cloudsql/%s",
    google_sql_user.app.name,
    random_password.db.result,
    google_sql_database.app.name,
    google_sql_database_instance.main.connection_name,
  )
}
