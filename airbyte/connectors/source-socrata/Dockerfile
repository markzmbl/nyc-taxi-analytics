# Dockerfile for the Socrata Airbyte source connector.
#
# Uses a standard Python 3.12 slim image. The Airbyte CDK is installed as a
# Python package — no special base image is required for Low-Code CDK connectors.
#
# Build:
#   docker build -t source-socrata:dev airbyte/connectors/source-socrata/
#
# Test:
#   docker run --rm source-socrata:dev spec
#   docker run --rm -v $(pwd)/config.json:/secrets/config.json source-socrata:dev check --config /secrets/config.json
#
# Deploy to Airbyte:
#   Load the image into your Airbyte instance (kind load docker-image for Kind):
#     kind load docker-image source-socrata:dev --name nyc-taxi-dev
#   Then register as a custom connector definition via the Airbyte API.

FROM python:3.12-slim

# Install the connector package
WORKDIR /airbyte
COPY setup.py requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY source_socrata/ ./source_socrata/
COPY main.py ./

RUN pip install --no-cache-dir -e .

# Airbyte connector entry point
ENV AIRBYTE_ENTRYPOINT="python /airbyte/main.py"
ENTRYPOINT ["python", "/airbyte/main.py"]
