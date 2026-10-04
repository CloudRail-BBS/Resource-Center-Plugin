#!/usr/bin/env bash
# Locates the plugin whose migration is breaking `rake db:migrate`.
#
# `Pups::ExecError ... db:migrate failed` is only the *wrapper* error. The
# offending migration, its file path and the real exception are always printed
# higher up the build log, and pups only echoes the tail.
#
# Reads the numbered log files rather than stdout: there is no terminal and no
# scrollback when the build runs non-interactively, so `/var/discourse` is the
# only place the answer exists.
#
# Usage:  bash diagnose-migrate.sh [/var/discourse]

set -uo pipefail

DOCKER_ROOT="${1:-/var/discourse}"
GLOBALS="$(find "$DOCKER_ROOT/shared/log" -name 'rails_production.log*' 2>/dev/null | sort | tail -1)"

if [ -z "$GLOBALS" ]; then
  echo "ERROR: no rails_production.log under $DOCKER_ROOT/shared/log"
  exit 1
fi

echo "Log: $GLOBALS"
echo

# --------------------------------------------------------------------------
# 1. Was the failure actually caused by a plugin migration?
# --------------------------------------------------------------------------
echo "=== migrations attributed to PLUGINS (not core) ==="
grep -aE 'StandardError: An error has occurred, this and all later migrations canceled' -B 200 "$GLOBALS" 2>/dev/null \
  | grep -aoE "plugins/[a-zA-Z0-9_.-]+/db/migrate/[0-9_]+[a-z0-9_]+\.rb" \
  | sort -u

echo
echo "=== migrations attributed to CORE ==="
grep -aoE "db/migrate/[0-9_]+[a-z0-9_]+\.rb" "$GLOBALS" 2>/dev/null \
  | grep -v '^plugins/' | sort -u | tail -5

echo
# --------------------------------------------------------------------------
# 2. The actual exception class and message.
#    After a bad plugin migration, Rails raises a StandardError listing the
#    remaining migrations in the `db/migrate` description, NOT the plugin path.
# --------------------------------------------------------------------------
echo "=== exception class + message ==="
grep -aE '^[A-Z][A-Za-z:]*Error|^StandardError|^ActiveRecord::' "$GLOBALS" 2>/dev/null | sort -u | tail -15

echo
echo "=== the migration that actually raised ==="
# Rails prints "== <MigrationName>: migrating ======" for each one it starts.
# The last one it *started* but never reported "migrated" is the culprit.
awk '
  /== [A-Za-z0-9_:]+: migrating/ { name=$2; sub(/:$/,"",name); started=NR; line=$0 }
  /== [A-Za-z0-9_:]+: migrated/  { name="" }
  END { if (name != "") printf "started and never finished: %s (line %d)\n  %s\n", name, started, line }
' "$GLOBALS"

echo
echo "=== plugin names near the failure ==="
grep -aoE '(plugin directory is named|Plugin name is|plugins/[a-zA-Z0-9_.-]+)' "$GLOBALS" 2>/dev/null | sort -u | head -40

echo
# --------------------------------------------------------------------------
# 3. Order-independent cause: two plugins claiming the same migration version.
#    Both get copied into one db/migrate namespace, one gets skipped, and the
#    schema drifts. Reported as a duplicate version, not a plugin name.
# --------------------------------------------------------------------------
echo "=== duplicate migration versions across plugins (the classic cause) ==="
cat "$DOCKER_ROOT/plugins"/*/db/migrate/*.rb 2>/dev/null \
  | grep -aoE 'migration\[[0-9.]+\]' | sort | uniq -c | sort -rn | head

echo
echo "=== every plugin that ships migrations ==="
for d in "$DOCKER_ROOT/plugins"/*/; do
  n=$(ls "$d"db/migrate/*.rb 2>/dev/null | wc -l)
  [ "$n" -gt 0 ] && printf '%4d  %s\n' "$n" "$(basename "$d")"
done

echo
# --------------------------------------------------------------------------
# 4. The most common single-file breakage: a migration class whose ActiveRecord
#    version bracket is missing. Rails 8+ rejects it outright.
# --------------------------------------------------------------------------
echo "=== migrations missing the ActiveRecord version bracket ==="
grep -rlE 'class [A-Za-z0-9_]+ < ActiveRecord::Migration$' "$DOCKER_ROOT/plugins"/*/db/migrate/*.rb 2>/dev/null

echo
echo "=== full boot log location (for the complete stack trace) ==="
ls -1 "$DOCKER_ROOT/shared/log" 2>/dev/null
echo "  bundle log:  $(ls -t "$DOCKER_ROOT/shared/log"/rails_production.log* 2>/dev/null | tail -1)"
