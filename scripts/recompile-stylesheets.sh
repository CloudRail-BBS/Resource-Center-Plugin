#!/usr/bin/env bash
# Recompiles this plugin's stylesheets through Discourse's real pipeline, and
# reports what the cache ends up holding.
#
# It must run where Redis and Postgres are up -- i.e. inside the RUNNING
# container. `./launcher run app` is NOT that: it starts a fresh one-off
# container with no services, so Rails dies on
# "Couldn't connect to Redis ... 127.0.0.1:6379".
#
# From the host, this script finds the running container itself:
#
#     bash plugins/<plugin-dir>/scripts/recompile-stylesheets.sh
#     DISCOURSE_CONTAINER=<name> bash ...        # if it is not called 'app'
#
# Or do it by hand, from your docker_manager directory (path varies:
# /var/discourse, /data/discourse, ...):
#
#     ./launcher enter app
#     cd /var/www/discourse && bundle exec rails runner plugins/<plugin-dir>/scripts/recompile-stylesheets.rb
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
# Inside the container: run it.
# --------------------------------------------------------------------------
if [ -f "$INNER_ROOT/config/environment.rb" ]; then
  if [ ! -f "$INNER_ROOT/$RUNNER_REL" ]; then
    echo "Runner not found at $INNER_ROOT/$RUNNER_REL" >&2
    echo "Is the plugin directory really named '$PLUGIN_NAME'?" >&2
    exit 1
  fi

  cd "$INNER_ROOT" || exit 1
  echo "plugin : $PLUGIN_NAME"
  echo "runner : $RUNNER_REL"
  echo

  # `rails runner` rather than `rails c`: non-interactive, so the whole output
  # can be copied back in one piece.
  if command -v bundle >/dev/null 2>&1; then
    exec bundle exec rails runner "$RUNNER_REL"
  else
    exec rails runner "$RUNNER_REL"
  fi
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
  echo "    cd $INNER_ROOT && bundle exec rails runner $RUNNER_REL" >&2
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
  echo "    cd $INNER_ROOT && bundle exec rails runner $RUNNER_REL" >&2
  exit 1
fi

echo "host detected; running inside the live container '$CONTAINER'"
echo

# -i, not -it: this must work when output is piped, and there is no TTY in a
# captured session.
exec docker exec -i "$CONTAINER" bash -c "cd $INNER_ROOT && bundle exec rails runner $RUNNER_REL"
