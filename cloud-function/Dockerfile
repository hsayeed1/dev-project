# Use a lightweight Python image
FROM python:3.10-slim

# Install required system packages (including unixODBC and build tools for pyodbc)
RUN apt-get update && \
    apt-get install -y unixodbc gcc g++ && \
    rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python deps
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy your source code
COPY . .

# Set port and expose it
ENV PORT=8080
EXPOSE 8080

# Start the functions framework
CMD ["functions-framework", "--target", "load_csv_to_bigquery"]