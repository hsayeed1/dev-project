output "dataset_id" {
  value = google_bigquery_dataset.employees_data_dataset.dataset_id
}

output "table_id" {
  value = google_bigquery_table.employees_table.table_id
}