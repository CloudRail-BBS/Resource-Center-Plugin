#!/usr/bin/env bash
# Recompiles this plugin's stylesheets through Discourse's real pipeline, and
# reports what the cache ends up holding.
#
# It must run where Redis and Postgres are up -- i.e. inside the RUNNING
# container, and as the `discourse` user.
#
# Two invocation traps, both of which look like plugin errors:
#
#   ./launcher run app "..."   starts a fresh one-off container with NO services,
#                              so Redis is down and Rails cannot boot:
#                                Couldn't connect to Redis ... 127.0.0.1:6379
#
#   ./launcher enter app       gives you ROOT, and Postgres uses peer auth, so:
#                                FATAL: Peer authentication failed for user "discourse"
#                                Database not found: discourse
#                              (the "database not found" line is a consequence)
#                              Wrap in `su discourse -c '...'`, which is exactly
#                              what Discourse's own db_migrate step does.
#
# From the host, this script handles both:
#
#     bash plugins/<plugin-dir>/scripts/recompile-stylesheets.sh
#     DISCOURSE_CONTAINER=<name> bash ...        # if it is not called 'app'
#
# Or by hand, from your docker_manager directory (path varies:
# /var/discourse, /data/discourse, ...):
#
#     ./launcher enter app
#     su discourse -c "cd /var/www/discourse && bundle exec rails runner plugins/<plugin-dir>/scripts/recompile-stylesheets.rb"
#
# Note the two paths differ on purpose: the HOST directory varies, but inside the
# container it is always /var/www/discourse.
#
# Why a script instead of an inline command: the Ruby has to run inside the
# container against the app, and `rails runner '...'` inline means nested quoting
# that is easy to get wrong — pasting Ruby straight into bash fails with
# "syntax error near unexpected token `target:'". A file removes the quoting.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PLUGIN_NAME="$(basename "$PLUGIN_DIR")"

INNER_ROOT="/var/www/discourse"
RUNNER_REL="plugins/$PLUGIN_NAME/scripts/recompile-stylesheets.rb"

# --------------------------------------------------------------------------
# Rails must run as the `discourse` user, not as root.
#
# Postgres in the container uses PEER authentication on the unix socket, so the
# OS user has to match the database user. `./launcher enter app` gives you root,
# and root gets:
#
#     FATAL: Peer authentication failed for user "discourse" (PG::ConnectionBad)
#     Database not found: discourse (ActiveRecord::NoDatabaseError)
#
# The "database not found" line is a consequence, not the cause -- the connection
# never succeeded. This is why Discourse's own boot runs `su discourse -c '...'`
# (see the db_migrate step in the bootstrap output).
# --------------------------------------------------------------------------
run_rails() {
  if [ "$(id -u)" = "0" ] && id discourse >/dev/null 2>&1; then
    su discourse -c "cd $INNER_ROOT && bundle exec rails runner $RUNNER_REL"
  else
    cd "$INNER_ROOT" || exit 1
    bundle exec rails runner "$RUNNER_REL"
  fi
}

# --------------------------------------------------------------------------
# Inside the container: run it.
# --------------------------------------------------------------------------
if [ -f "$INNER_ROOT/config/environment.rb" ]; then
  if [ ! -f "$INNER_ROOT/$RUNNER_REL" ]; then
    echo "Runner not found at $INNER_ROOT/$RUNNER_REL" >&2
    echo "Is the plugin directory really named '$PLUGIN_NAME'?" >&2
    exit 1
  fi

  echo "plugin : $PLUGIN_NAME"
  echo "runner : $RUNNER_REL"
  echo
  run_rails
  exit $?
fi

# --------------------------------------------------------------------------
# On the host: run it in the ALREADY-RUNNING container.
#
# NOT `./launcher run app` -- that starts a fresh one-off container from the
# bootstrapped image with no services running, so Redis and Postgres are down and
# Rails cannot boot at all:
#
#     Couldn't connect to Redis
#     Connection refused - connect(2) for 127.0.0.1:6379
#       from app/models/global_setting.rb:41:in 'GlobalSetting.safe_secret_key_base'
#
# `docker exec` against the running container is what actually works.
# --------------------------------------------------------------------------
CONTAINER="${DISCOURSE_CONTAINER:-app}"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker not found on this host. Run it inside the container instead:" >&2
  echo "    cd <your-discourse-dir> && ./launcher enter app" >&2
  echo "    su discourse -c \"cd $INNER_ROOT && bundle exec rails runner $RUNNER_REL\"" >&2
  echo >&2
  echo "The 'su discourse' is required: enter gives you root, and Postgres uses" >&2
  echo "peer auth, so root gets 'Peer authentication failed for user \"discourse\"'." >&2
  exit 1
fi

if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$CONTAINER"; then
  echo "No running container named '$CONTAINER'." >&2
  echo "Running containers:" >&2
  docker ps --format '  {{.Names}}' 2>/dev/null >&2 || true
  echo >&2
  echo "Set the right one with:  DISCOURSE_CONTAINER=<name> bash $0" >&2
  echo "Or run it inside the container:" >&2
  echo "    cd <your-discourse-dir> && ./launcher enter app" >&2
  echo "    su discourse -c \"cd $INNER_ROOT && bundle exec rails runner $RUNNER_REL\"" >&2
  exit 1
fi

echo "host detected; running inside the live container '$CONTAINER'"
echo

# -i, not -it: this must work when output is piped, and there is no TTY in a
# captured session. `su discourse` because of peer authentication, as above.
exec docker exec -i "$CONTAINER" bash -c "cd $INNER_ROOT && su discourse -c 'bundle exec rails runner $RUNNER_REL'"
