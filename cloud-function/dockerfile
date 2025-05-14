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

# Set env port and run the function
ENV PORT=8080
CMD ["functions-framework", "--target", "load_to_bigquery"]
