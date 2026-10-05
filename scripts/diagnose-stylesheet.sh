#!/usr/bin/env bash
# Why is this plugin's stylesheet 404ing?
#
# Discourse serves /stylesheets/<target>_<digest>.css out of the `stylesheet_cache`
# table. The <link> is emitted from the plugin registry, so a 404 means the row
# was never written -- the compile either raised or never ran. Either way the
# build log says which, and this prints the lines that matter.
#
# Usage:  bash scripts/diagnose-stylesheet.sh [forum-url] [/var/discourse]
#
# Run it from anywhere; it only reads.

set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN_NAME="$(basename "$PLUGIN_DIR")"
FORUM="${1:-}"
DOCKER_ROOT="${2:-/var/discourse}"

echo "plugin directory name: $PLUGIN_NAME"
echo "target name:           $PLUGIN_NAME   (and ${PLUGIN_NAME}_admin)"
echo

# --------------------------------------------------------------------------
# 1. Is the stylesheet actually 404ing, and are its neighbours fine?
# --------------------------------------------------------------------------
if [ -n "$FORUM" ]; then
  echo "=== stylesheet HTTP status ==="
  page="$(curl -sS --max-time 30 -H "Accept: text/html" "$FORUM/" 2>/dev/null)"

  mine="$(printf '%s' "$page" | grep -oE "/stylesheets/${PLUGIN_NAME}_[a-f0-9]+\.css" | head -1)"

  if [ -z "$mine" ]; then
    echo "  no <link> for $PLUGIN_NAME on the homepage."
    echo "  The page that uses it is /relay-rooms -- fetch that instead:"
    page="$(curl -sS --max-time 30 -H "Accept: text/html" "$FORUM/relay-rooms" 2>/dev/null)"
    mine="$(printf '%s' "$page" | grep -oE "/stylesheets/${PLUGIN_NAME}_[a-f0-9]+\.css" | head -1)"
  fi

  if [ -n "$mine" ]; then
    printf '  %-4s %s\n' "$(curl -sS --max-time 20 -o /dev/null -w '%{http_code}' "$FORUM$mine" 2>/dev/null)" "$mine"
  else
    echo "  could not find a stylesheet link for this plugin at all."
    echo "  That means register_asset never ran -- check plugin.rb."
  fi

  # A neighbour for contrast: if another plugin's stylesheet is 200, the pipeline
  # itself is fine and the problem is specific to this stylesheet.
  other="$(printf '%s' "$page" | grep -oE '/stylesheets/[a-z0-9_-]+_[a-f0-9]+\.css' | grep -v "$PLUGIN_NAME" | head -1)"
  if [ -n "$other" ]; then
    printf '  %-4s %s   (another plugin, for contrast)\n' \
      "$(curl -sS --max-time 20 -o /dev/null -w '%{http_code}' "$FORUM$other" 2>/dev/null)" "$other"
  fi
  echo
fi

# --------------------------------------------------------------------------
# 2. The build log. Discourse prints one line per target, then the error.
# --------------------------------------------------------------------------
echo "=== build log: was the target precompiled? ==="
found=0
for log in "$DOCKER_ROOT"/log/*.log "$DOCKER_ROOT"/shared/log/*.log /var/log/docker/*.log; do
  [ -f "$log" ] || continue
  hits="$(grep -a "precompile target: ${PLUGIN_NAME}" "$log" 2>/dev/null)"
  if [ -n "$hits" ]; then
    echo "  in $log:"
    printf '%s\n' "$hits" | sed 's/^/    /'
    found=1
  fi
done

if [ "$found" -eq 0 ]; then
  echo "  not found in any local log."
  echo "  The rebuild output goes to your terminal, not to a file. Re-run with the"
  echo "  output captured:"
  echo "      cd $DOCKER_ROOT && ./launcher rebuild app 2>&1 | tee /tmp/rebuild.log"
  echo "  then:"
  echo "      grep -nE 'precompile target|SCSS compilation error|ScssError|stylesheet' /tmp/rebuild.log"
fi
echo

# --------------------------------------------------------------------------
# 3. The SCSS error itself, if the build recorded one.
# --------------------------------------------------------------------------
echo "=== SCSS / stylesheet errors in logs ==="
for log in "$DOCKER_ROOT"/log/*.log "$DOCKER_ROOT"/shared/log/*.log; do
  [ -f "$log" ] || continue
  hits="$(grep -anE "SCSS compilation error|Discourse::ScssError|Error compiling stylesheet" "$log" 2>/dev/null | tail -20)"
  [ -n "$hits" ] && printf '%s\n' "$hits" | sed "s|^|  $(basename "$log"):|"
done
echo

# --------------------------------------------------------------------------
# 4. Sanity checks that need no log at all.
# --------------------------------------------------------------------------
echo "=== local sanity ==="
printf '  registered in plugin.rb: '
grep -c 'register_asset "stylesheets/' "$PLUGIN_DIR/plugin.rb" 2>/dev/null || echo 0

printf '  files on disk:           '
for f in "$PLUGIN_DIR"/assets/stylesheets/*.scss; do
  [ -f "$f" ] && printf '%s ' "$(basename "$f")"
done
echo

printf '  bare-# lines in plugin.rb: '
grep -c '^#[[:space:]]*$' "$PLUGIN_DIR/plugin.rb" 2>/dev/null || echo 0
echo "  (a bare '#' aborts Plugin::Metadata.parse -- see README)"

echo
echo "=== does each stylesheet compile? ==="
echo "  run this locally, where the real check lives:"
echo "      python scripts/validate.py     # compiles every registered .scss"
echo "  It mirrors Discourse's entrypoint (prepended_scss + @import \"<abs path>\")"
echo "  and uses the same dart-sass, so a failure here is a failure there."
