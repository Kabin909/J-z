#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/.env"
MIGRATIONS_DIR="$ROOT/packages/db/migrations"

[[ -f "$ENV_FILE" ]] || { echo "ERROR: $ENV_FILE is missing" >&2; exit 1; }
[[ -d "$MIGRATIONS_DIR" ]] || { echo "ERROR: $MIGRATIONS_DIR is missing" >&2; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "ERROR: docker is required" >&2; exit 1; }

get_env(){
  local key="$1"
  awk -F= -v k="$key" '$1==k {sub(/^[^=]*=/,""); print; exit}' "$ENV_FILE"
}

DB_USER="$(get_env POSTGRES_USER)"
DB_NAME="$(get_env POSTGRES_DB)"
[[ -n "$DB_USER" && -n "$DB_NAME" ]] || { echo "ERROR: POSTGRES_USER/POSTGRES_DB missing" >&2; exit 1; }

cd "$ROOT"
psql_cmd=(docker compose --env-file "$ENV_FILE" exec -T postgres psql -X -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME")

"${psql_cmd[@]}" <<'SQL'
CREATE TABLE IF NOT EXISTS schema_migrations (
  version INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  checksum TEXT NOT NULL,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
SELECT pg_advisory_lock(hashtext('jz-panel-schema-migrations'));
SQL

cleanup(){
  "${psql_cmd[@]}" -c "SELECT pg_advisory_unlock(hashtext('jz-panel-schema-migrations'));" >/dev/null 2>&1 || true
}
trap cleanup EXIT

has_legacy_schema(){
  local count
  count="$(${psql_cmd[@]} -Atqc "SELECT count(*) FROM pg_class WHERE relkind='r' AND relname IN ('users','nodes','servers');")"
  [[ "$count" == "3" ]]
}

applied_checksum(){
  "${psql_cmd[@]}" -Atqc "SELECT checksum FROM schema_migrations WHERE version=$1;"
}

record_migration(){
  local version="$1" name="$2" checksum="$3"
  "${psql_cmd[@]}" -v version="$version" -v name="$name" -v checksum="$checksum" <<'SQL'
INSERT INTO schema_migrations(version,name,checksum)
VALUES(:'version',:'name',:'checksum');
SQL
}

mapfile -t migration_files < <(find "$MIGRATIONS_DIR" -maxdepth 1 -type f -name '*.sql' -printf '%f\n' | sort -V)
((${#migration_files[@]} > 0)) || { echo "No migrations found."; exit 1; }

for filename in "${migration_files[@]}"; do
  if [[ ! "$filename" =~ ^([0-9]+)_(.+)\.sql$ ]]; then
    echo "ERROR: invalid migration filename: $filename" >&2
    exit 1
  fi
  version="${BASH_REMATCH[1]}"
  name="${BASH_REMATCH[2]}"
  version_num=$((10#$version))
  file="$MIGRATIONS_DIR/$filename"
  checksum="$(sha256sum "$file" | awk '{print $1}')"

  current="$(applied_checksum "$version_num" || true)"
  if [[ -n "$current" ]]; then
    [[ "$current" == "$checksum" ]] || {
      echo "ERROR: checksum mismatch for migration $filename" >&2
      echo "       DB:   $current" >&2
      echo "       File: $checksum" >&2
      exit 1
    }
    echo "[skip] $filename already applied"
    continue
  fi

  # Databases created by J&Z <= 3.2.0 already ran 001_init.sql directly.
  # Adopt that schema as the 001 baseline instead of executing it again.
  if [[ "$version_num" -eq 1 ]] && has_legacy_schema; then
    echo "[baseline] $filename — existing J&Z schema detected; recording migration without re-running SQL"
    record_migration "$version_num" "$name" "$checksum"
    continue
  fi

  echo "[apply] $filename"
  {
    printf 'BEGIN;\n'
    cat "$file"
    printf '\nCOMMIT;\n'
  } | "${psql_cmd[@]}"
  record_migration "$version_num" "$name" "$checksum"
  echo "[done] $filename"
done

current_version="$("${psql_cmd[@]}" -Atqc 'SELECT COALESCE(MAX(version),0) FROM schema_migrations;')"
echo "Migration level: $current_version"
