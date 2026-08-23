#!/usr/bin/env bash
# EcoLoop dev-database backup.
#   ./scripts/backup_db.sh            -> backups/ecoloop_YYYYmmdd_HHMMSS.dump
# Restore with:
#   pg_restore -U recycle -d recycle_vision --clean <file>
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKUP_DIR="$ROOT/backups"
STAMP="$(date +%Y%m%d_%H%M%S)"
FILE="$BACKUP_DIR/ecoloop_$STAMP.dump"

mkdir -p "$BACKUP_DIR"
PGPASSWORD="${POSTGRES_PASSWORD:-recycle}" pg_dump \
  -h "${POSTGRES_HOST:-localhost}" -p "${POSTGRES_PORT:-5432}" \
  -U "${POSTGRES_USER:-recycle}" -d "${POSTGRES_DB:-recycle_vision}" \
  -Fc -f "$FILE"

echo "Backup written: $FILE"
# Keep the 14 most recent dumps; delete older ones.
ls -1t "$BACKUP_DIR"/ecoloop_*.dump 2>/dev/null | tail -n +15 | xargs rm -f 2>/dev/null || true
