import functions_framework
import os
from google.cloud import storage, bigquery
import pandas as pd
import logging
from io import StringIO

logging.basicConfig(level=logging.INFO)

@functions_framework.cloud_event
def load_csv_to_bigquery(cloud_event):
    try:
        # GCS bucket and file details
        bucket_name = 'employees-data-bucket-dev-project-humayra'
        csv_filename = 'employees.csv'

        # BigQuery dataset and table from env vars
        dataset_id = os.environ.get('BQ_DATASET')
        table_id = os.environ.get('BQ_TABLE')

        # Initialize clients
        storage_client = storage.Client()
        bq_client = bigquery.Client()

        # Download CSV file content from GCS
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(csv_filename)
        csv_data = blob.download_as_text()

        logging.info("CSV file downloaded from GCS")

        # Read CSV into pandas DataFrame
        df = pd.read_csv(StringIO(csv_data))

        logging.info(f"CSV loaded into DataFrame with {len(df)} rows")

        # Define BigQuery table reference
        table_ref = bq_client.dataset(dataset_id).table(table_id)

        # Define job config with schema and write disposition
        job_config = bigquery.LoadJobConfig(
            write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
            schema=[
                bigquery.SchemaField("customer_id", "STRING"),
                bigquery.SchemaField("first_name", "STRING"),
                bigquery.SchemaField("last_name", "STRING"),
                bigquery.SchemaField("email", "STRING"),
                bigquery.SchemaField("created_at", "DATE"),  # since your CSV has no time
            ],
            source_format=bigquery.SourceFormat.CSV,
            skip_leading_rows=1,
            autodetect=False,
        )

        # Load data from DataFrame directly using load_table_from_dataframe
        load_job = bq_client.load_table_from_dataframe(df, table_ref, job_config=job_config)
        load_job.result()  # Wait for the job to complete

        logging.info("Data loaded to BigQuery successfully")

    except Exception as e:
        logging.error(f"Error loading CSV to BigQuery: {e}")
