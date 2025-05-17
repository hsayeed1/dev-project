resource "google_logging_metric" "bigquery_job_failure_count" {
  name        = "bigquery_job_failure_count"
  description = "Count of failed BigQuery jobs"
  filter      = <<EOT
resource.type="bigquery_project"
protoPayload.methodName="jobservice.jobcompleted"
protoPayload.status.code != 0
EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

resource "google_monitoring_notification_channel" "email_channel" {
  display_name = "Email Notification"
  type         = "email"

  labels = {
    email_address = "humayra.sayeed@alumni.stonybrook.edu"
  }
}

resource "google_monitoring_alert_policy" "bq_job_failure_alert" {
  display_name = "BigQuery Job Failure Alert"
  combiner     = "OR"

  conditions {
    display_name = "BigQuery Job Failures > 0"

    condition_threshold {
      filter          = "resource.type=\"bigquery_project\" AND metric.type=\"logging.googleapis.com/user/bigquery_job_failure_count\""
      duration        = "60s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_NONE"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email_channel.id]

  documentation {
    content   = "A BigQuery job failure has been detected."
    mime_type = "text/markdown"
  }

  user_labels = {
    environment = "dev"
  }
}
