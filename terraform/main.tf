terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0.0"
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

/*# Cloud Function using the container image from GCR
resource "google_cloudfunctions2_function" "data_ingestion_function" {
  name     = "load-to-bigquery"
  location = var.region
  project  = var.project_id

  build_config {
    runtime     = "custom"
    entry_point = "load_to_bigquery"
    source {
      container_image = "gcr.io/dev-project-humayra/load-to-bigquery"
    }
  }

  service_config {
    max_instance_count = 1
    available_memory   = "256M"
    timeout_seconds    = 60
    environment_variables = {
      BQ_DATASET = google_bigquery_dataset.employees_data_dataset.dataset_id
      BQ_TABLE   = google_bigquery_table.employees_table.table_id
    }
    ingress_settings      = "ALLOW_ALL"
    service_account_email = google_service_account.data_pipeline_sa.email
  }

  event_trigger {
    event_type  = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic = google_pubsub_topic.trigger_topic.id
    retry_policy = "RETRY_POLICY_DO_NOT_RETRY"
  }
}*/

resource "google_cloudfunctions2_function" "data_ingestion_function" {
  name     = "load-to-bigquery"
  location = var.region
  project  = var.project_id

  build_config {
    runtime = "custom"          # usually 'custom' when using container image
    entry_point = "load_to_bigquery"  # your function entry point
    image = "gcr.io/dev-project-humayra/load-to-bigquery"  # <-- here is the image
  }

  service_config {
    max_instance_count  = 1
    available_memory    = "256M"
    timeout_seconds     = 60
    ingress_settings    = "ALLOW_ALL"
    service_account_email = google_service_account.data_pipeline_sa.email

    environment_variables = {
      BQ_DATASET = google_bigquery_dataset.employees_data_dataset.dataset_id
      BQ_TABLE   = google_bigquery_table.employees_table.table_id
    }
  }

  event_trigger {
    event_type   = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic = google_pubsub_topic.trigger_topic.id
    retry_policy = "RETRY_POLICY_DO_NOT_RETRY"
  }
}

# Cloud Scheduler Job to trigger Cloud Function
resource "google_cloud_scheduler_job" "daily_trigger" {
  name        = "daily-function-trigger"
  description = "Triggers the function daily via Pub/Sub"
  schedule    = "0 22 * * *"       # 22:00 = 10 PM
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

data "google_project" "project" {
  project_id = var.project_id
}
