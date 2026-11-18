# Every API this configuration uses, so a fresh project is reproducible.
# disable_on_destroy = false: turning an API off on destroy can break things
# outside this configuration (the bootstrap, the console) and gains nothing.

resource "google_project_service" "this" {
  for_each = toset([
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "artifactregistry.googleapis.com",
    "secretmanager.googleapis.com",
    "logging.googleapis.com",
    "firebase.googleapis.com",
    "firebasehosting.googleapis.com",
  ])

  service            = each.key
  disable_on_destroy = false
}
