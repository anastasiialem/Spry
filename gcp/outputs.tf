output "api_url" {
  value = google_cloud_run_v2_service.api.uri
}

output "api_service" {
  value = google_cloud_run_v2_service.api.name
}

output "image_repository" {
  description = "docker push target: <this>/backend:<tag>"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.images.repository_id}"
}

output "db_connection_name" {
  value = google_sql_database_instance.main.connection_name
}

output "db_activation_policy" {
  value = var.db_activation_policy
}

output "site_url" {
  value = "https://${var.project_id}.web.app"
}
