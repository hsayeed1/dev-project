variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "Region for BigQuery resources"
  type        = string
  default     = "US"
}