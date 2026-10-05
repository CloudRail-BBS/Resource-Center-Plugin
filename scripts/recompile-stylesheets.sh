#!/usr/bin/env bash
# Recompiles this plugin's stylesheets through Discourse's real pipeline, and
# reports what the cache ends up holding.
#
# ONE COMMAND, from the host — substitute your own docker_manager directory:
#
#     cd /var/discourse && ./launcher run app "cd /var/www/discourse && bash plugins/<plugin-dir>/scripts/recompile-stylesheets.sh"
#
# The host directory varies by install (`/var/discourse`, `/data/discourse`, …).
# The path INSIDE the container does not: it is always /var/www/discourse. Only
# the leading `cd` changes.
#
# Or if you prefer to be inside the container already:
#
#     cd <your-discourse-dir> && ./launcher enter app
#     cd /var/www/discourse && bash plugins/<plugin-dir>/scripts/recompile-stylesheets.sh
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
# On the host: re-enter the container. The plugin directory is bind-mounted, so
# this same file is already visible inside at $INNER_ROOT/$RUNNER_REL.
# --------------------------------------------------------------------------
LAUNCHER=""
# The host directory differs per install — /var/discourse is only the common
# default. Look in the usual places, then next to this plugin.
for candidate in \
  "./launcher" \
  "/var/discourse/launcher" \
  "/data/discourse/launcher" \
  "$(dirname "$(dirname "$(dirname "$PLUGIN_DIR")")")/launcher"
do
  if [ -x "$candidate" ]; then
    LAUNCHER="$candidate"
    break
  fi
done

if [ -z "$LAUNCHER" ]; then
  echo "Not inside the container, and no ./launcher found." >&2
  echo "Run this from your docker_manager directory, e.g.:" >&2
  echo "    cd /data/discourse && ./launcher run app \"cd $INNER_ROOT && bash $RUNNER_REL\"" >&2
  echo "or copy that command from the header of this file." >&2
  exit 1
fi

echo "host detected; re-entering the container via $LAUNCHER"
echo

# The inner command contains no quotes or spaces, so one level of quoting is all
# that is needed.
exec "$LAUNCHER" run app "cd $INNER_ROOT && bash $RUNNER_REL"
