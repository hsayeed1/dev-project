terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.11.0"
    }
  }

  required_version = ">= 1.3.0"
}

provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_bigquery_dataset" "employees_data_dataset" {
  dataset_id = "employees_data"
  location   = var.region
}

resource "google_bigquery_table" "employees_table" {
  dataset_id          = google_bigquery_dataset.employees_data_dataset.dataset_id
  table_id            = "employees_info"
  deletion_protection = false

  schema = file("${path.module}/schemas/employees_schema.json")
}

# Create a Service Account for the data pipeline
resource "google_service_account" "data_pipeline_sa" {
  account_id   = "data-pipeline-sa"
  display_name = "Data Pipeline Service Account"
  project      = var.project_id
}

# Assign BigQuery Admin role to the service account
resource "google_project_iam_member" "bigquery_admin" {
  project = var.project_id
  role    = "roles/bigquery.admin"
  member  = "serviceAccount:${google_service_account.data_pipeline_sa.email}"
}

# Assign Storage Admin role to the service account (for GCS access)
resource "google_project_iam_member" "storage_admin" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.data_pipeline_sa.email}"
}

# Generate the service account key
resource "google_service_account_key" "data_pipeline_sa_key" {
  service_account_id = google_service_account.data_pipeline_sa.name
  private_key_type   = "TYPE_GOOGLE_CREDENTIALS_FILE"
}

# Output the service account key for manual download
output "service_account_key" {
  value     = google_service_account_key.data_pipeline_sa_key.private_key
  sensitive = true
}

# Pub/Sub Topic
resource "google_pubsub_topic" "trigger_topic" {
  name = "cf-trigger-topic"
}

# Cloud Run Service to run the containerized data ingestion function
resource "google_cloud_run_service" "data_ingestion_service" {
  name     = "load-to-bigquery"
  location = var.region
  project  = var.project_id

  template {
    spec {
      containers {
        image = "gcr.io/dev-project-humayra/load-to-bigquery"
        resources {
          limits = {
            memory = "256Mi"
          }
        }
        env {
          name  = "BQ_DATASET"
          value = google_bigquery_dataset.employees_data_dataset.dataset_id
        }
        env {
          name  = "BQ_TABLE"
          value = google_bigquery_table.employees_table.table_id
        }
      }
      service_account_name = google_service_account.data_pipeline_sa.email
    }
    metadata {
      annotations = {
        "autoscaling.knative.dev/maxScale" = "1"
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }
}

# Allow unauthenticated invocations (optional)
resource "google_cloud_run_service_iam_member" "public_invoker" {
  location = google_cloud_run_service.data_ingestion_service.location
  project  = google_cloud_run_service.data_ingestion_service.project
  service  = google_cloud_run_service.data_ingestion_service.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Cloud Scheduler Job to trigger Pub/Sub topic daily
resource "google_cloud_scheduler_job" "daily_trigger" {
  name        = "daily-function-trigger"
  description = "Triggers the function daily via Pub/Sub"
  schedule    = "0 17 * * *"       # 10:00 AM daily
  time_zone   = "America/New_York" # NYC time zone

  pubsub_target {
    topic_name = google_pubsub_topic.trigger_topic.id
    data       = base64encode("Trigger function")
  }
}

# IAM Permissions for Scheduler to publish to Pub/Sub
resource "google_project_iam_member" "scheduler_pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-cloudscheduler.iam.gserviceaccount.com"
}

resource "google_pubsub_subscription" "cloud_run_sub" {
  name  = "cloud-run-sub"
  topic = google_pubsub_topic.trigger_topic.name

  push_config {
    push_endpoint = "https://load-to-bigquery-881002525671.${var.region}.run.app"
  }

  ack_deadline_seconds = 20

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
}

data "google_project" "project" {
  project_id = var.project_id
}
