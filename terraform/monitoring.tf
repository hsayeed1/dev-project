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

  value_extractor = "EXTRACT(jsonPayload.jobChange.reason)"
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

  notification_channels = [google_monitoring_notification_channel.email_channel.name]

  conditions {
    display_name = "BigQuery Failed Jobs > 0"

    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/bigquery_job_failure_count\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "60s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_DELTA"
      }
    }
  }

  documentation {
    content = "BigQuery job failures detected in the last minute."
  }

  alert_strategy {
    notification_rate_limit {
      period = "3600s" # 1 notification per hour
    }
  }

  enabled = true
}