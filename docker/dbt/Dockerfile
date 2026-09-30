# dbt Core + the ClickHouse adapter, Python 3.13 to match pyproject.toml's pin.
FROM python:3.13-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir dbt-core~=1.11.0 dbt-clickhouse~=1.10.0

# Repo root, not the project subfolder -- avoids Docker auto-creating airstats/ on the host
# just from starting a container. Pass --project-dir airstats --profiles-dir airstats per call.
WORKDIR /usr/app

ENTRYPOINT ["dbt"]
