-- Postgres initialization script: creates the rimi_app role.
-- TENANCY-03: credentials for rimi_app come from env (POSTGRES_APP_PASSWORD).
-- This file is mounted into the postgres container as an init script.
-- rimi_migrator already exists as POSTGRES_USER.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rimi_app') THEN
    -- TENANCY-02: NOSUPERUSER, NOBYPASSRLS, non-owner.
    EXECUTE format('CREATE ROLE rimi_app WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS PASSWORD %L',
                   current_setting('custom.rimi_app_password', true));
  END IF;
END
$$;

GRANT CONNECT ON DATABASE rimi TO rimi_app;
