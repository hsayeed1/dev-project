import functions_framework
import json
import pandas as pd
import pyodbc
from google.cloud import bigquery
import logging
import os

# Set up logging
logging.basicConfig(level=logging.INFO)

# Cloud Function entry point
@functions_framework.cloud_event
def load_to_bigquery(cloud_event):
    logging.info("Function triggered by Cloud Scheduler via Pub/Sub")

    # Path to your .accdb file in Cloud Function environment or mounted storage
    access_db_path = 'C:/Users/humay/git/dev-project/employees.accdb'  # Update if needed
    table_name = 'employees'

    # Connect to Access DB (must be available in /tmp or pre-mounted path)
    try:
        conn_str = (
            r'DRIVER={Microsoft Access Driver (*.mdb, *.accdb)};'
            fr'DBQ={access_db_path};'
        )
        conn = pyodbc.connect(conn_str)
        df = pd.read_sql(f'SELECT * FROM {table_name}', conn)
        logging.info("Data extracted from Access DB")
    except Exception as e:
        logging.error(f"Failed to extract data from Access DB: {e}")
        return

    # Convert to JSON records
    records = df.to_dict(orient='records')

    # Load to BigQuery
    try:
        client = bigquery.Client()
        dataset_id = os.environ.get('BQ_DATASET')
        table_id = os.environ.get('BQ_TABLE')

        table_ref = f"{client.project}.{dataset_id}.{table_id}"

        job_config = bigquery.LoadJobConfig(
            schema=[
                bigquery.SchemaField("customer_id", "STRING"),
                bigquery.SchemaField("first_name", "STRING"),
                bigquery.SchemaField("last_name", "STRING"),
                bigquery.SchemaField("email", "STRING"),
                bigquery.SchemaField("created_at", "TIMESTAMP")
            ],
            write_disposition="WRITE_APPEND",
            source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
            autodetect=False,
        )

        # Write to a temporary JSON file
        tmp_json_path = "/tmp/employees.json"
        with open(tmp_json_path, "w") as f:
            for record in records:
                json.dump(record, f)
                f.write("\n")

        with open(tmp_json_path, "rb") as source_file:
            job = client.load_table_from_file(source_file, table_ref, job_config=job_config)
            job.result()  # Waits for the job to finish
            logging.info("Data loaded to BigQuery")

    except Exception as e:
        logging.error(f"Failed to load data to BigQuery: {e}")