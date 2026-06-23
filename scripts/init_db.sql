-- Create databases (dagster is the default POSTGRES_DB, already exists)
SELECT 'CREATE DATABASE warehouse'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'warehouse')\gexec
SELECT 'CREATE DATABASE metabase'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'metabase')\gexec

\c warehouse
CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS marts;

CREATE TABLE IF NOT EXISTS raw._watermarks (
    source_name TEXT PRIMARY KEY,
    last_value  TEXT,
    updated_at  TIMESTAMPTZ DEFAULT NOW()
);
