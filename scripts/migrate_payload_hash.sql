-- ============================================================
-- Migration: payload_hash dedup for raw JSONB tables
-- Order per table: add column -> dedup -> add unique constraint
-- Idempotent: safe to run multiple times.
-- ============================================================

-- ── raw.air_quality ──────────────────────────────────────
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='raw' AND table_name='air_quality' AND column_name='payload_hash') THEN
        ALTER TABLE raw.air_quality ADD COLUMN payload_hash TEXT GENERATED ALWAYS AS (md5(payload::text)) STORED;
    END IF;
END $$;

DELETE FROM raw.air_quality a USING raw.air_quality b WHERE a.ctid < b.ctid AND a.payload = b.payload;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='raw.air_quality'::regclass AND conname='raw_air_quality_payload_hash_key' AND contype='u') THEN
        ALTER TABLE raw.air_quality ADD CONSTRAINT raw_air_quality_payload_hash_key UNIQUE (payload_hash);
    END IF;
END $$;

-- ── raw.weather ──────────────────────────────────────────
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='raw' AND table_name='weather' AND column_name='payload_hash') THEN
        ALTER TABLE raw.weather ADD COLUMN payload_hash TEXT GENERATED ALWAYS AS (md5(payload::text)) STORED;
    END IF;
END $$;

DELETE FROM raw.weather a USING raw.weather b WHERE a.ctid < b.ctid AND a.payload = b.payload;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='raw.weather'::regclass AND conname='raw_weather_payload_hash_key' AND contype='u') THEN
        ALTER TABLE raw.weather ADD CONSTRAINT raw_weather_payload_hash_key UNIQUE (payload_hash);
    END IF;
END $$;

-- ── raw.nypd_complaints ──────────────────────────────────
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='raw' AND table_name='nypd_complaints' AND column_name='payload_hash') THEN
        ALTER TABLE raw.nypd_complaints ADD COLUMN payload_hash TEXT GENERATED ALWAYS AS (md5(payload::text)) STORED;
    END IF;
END $$;

DELETE FROM raw.nypd_complaints a USING raw.nypd_complaints b WHERE a.ctid < b.ctid AND a.payload = b.payload;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='raw.nypd_complaints'::regclass AND conname='raw_nypd_complaints_payload_hash_key' AND contype='u') THEN
        ALTER TABLE raw.nypd_complaints ADD CONSTRAINT raw_nypd_complaints_payload_hash_key UNIQUE (payload_hash);
    END IF;
END $$;

-- ── raw.complaints_311 ───────────────────────────────────
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='raw' AND table_name='complaints_311' AND column_name='payload_hash') THEN
        ALTER TABLE raw.complaints_311 ADD COLUMN payload_hash TEXT GENERATED ALWAYS AS (md5(payload::text)) STORED;
    END IF;
END $$;

DELETE FROM raw.complaints_311 a USING raw.complaints_311 b WHERE a.ctid < b.ctid AND a.payload = b.payload;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='raw.complaints_311'::regclass AND conname='raw_complaints_311_payload_hash_key' AND contype='u') THEN
        ALTER TABLE raw.complaints_311 ADD CONSTRAINT raw_complaints_311_payload_hash_key UNIQUE (payload_hash);
    END IF;
END $$;

-- ── raw.event_permits ────────────────────────────────────
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='raw' AND table_name='event_permits' AND column_name='payload_hash') THEN
        ALTER TABLE raw.event_permits ADD COLUMN payload_hash TEXT GENERATED ALWAYS AS (md5(payload::text)) STORED;
    END IF;
END $$;

DELETE FROM raw.event_permits a USING raw.event_permits b WHERE a.ctid < b.ctid AND a.payload = b.payload;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='raw.event_permits'::regclass AND conname='raw_event_permits_payload_hash_key' AND contype='u') THEN
        ALTER TABLE raw.event_permits ADD CONSTRAINT raw_event_permits_payload_hash_key UNIQUE (payload_hash);
    END IF;
END $$;

-- ── raw.restaurant_inspections ───────────────────────────
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='raw' AND table_name='restaurant_inspections' AND column_name='payload_hash') THEN
        ALTER TABLE raw.restaurant_inspections ADD COLUMN payload_hash TEXT GENERATED ALWAYS AS (md5(payload::text)) STORED;
    END IF;
END $$;

DELETE FROM raw.restaurant_inspections a USING raw.restaurant_inspections b WHERE a.ctid < b.ctid AND a.payload = b.payload;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='raw.restaurant_inspections'::regclass AND conname='raw_restaurant_inspections_payload_hash_key' AND contype='u') THEN
        ALTER TABLE raw.restaurant_inspections ADD CONSTRAINT raw_restaurant_inspections_payload_hash_key UNIQUE (payload_hash);
    END IF;
END $$;

-- ── raw.holidays ─────────────────────────────────────────
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='raw' AND table_name='holidays' AND column_name='payload_hash') THEN
        ALTER TABLE raw.holidays ADD COLUMN payload_hash TEXT GENERATED ALWAYS AS (md5(payload::text)) STORED;
    END IF;
END $$;

DELETE FROM raw.holidays a USING raw.holidays b WHERE a.ctid < b.ctid AND a.payload = b.payload;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='raw.holidays'::regclass AND conname='raw_holidays_payload_hash_key' AND contype='u') THEN
        ALTER TABLE raw.holidays ADD CONSTRAINT raw_holidays_payload_hash_key UNIQUE (payload_hash);
    END IF;
END $$;
