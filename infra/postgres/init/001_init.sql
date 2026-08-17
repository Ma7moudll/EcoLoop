-- Postgres bootstrap for the EcoLoop dev stack.
-- The backend runs Alembic migrations on boot; this only guarantees the
-- role + database exist before the app connects.
CREATE ROLE recycle WITH LOGIN PASSWORD 'recycle';
CREATE DATABASE recycle_vision OWNER recycle;
GRANT ALL PRIVILEGES ON DATABASE recycle_vision TO recycle;
