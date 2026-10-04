#!/usr/bin/env bash
# Proves the static checks can FAIL.
#
# A check that can only pass is worthless and worse than none, because it
# manufactures confidence. This script corrupts a copy of the plugin in each way
# the checks are supposed to catch, and asserts that validate.py reports a
# failure for every one of them.
#
# Usage: bash scripts/selftest.sh
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
PY="${PYTHON:-python}"
NODE_BIN="${NODE:-node}"

pass=0
fail=0

# Copy the plugin WITHOUT node_modules: a recursive copy of it is slow enough on
# Windows to look like a hang, and no check needs it.
copy_plugin() {
  local destination="$1"
  mkdir -p "$destination"
  ( cd "$PLUGIN_DIR" && tar --exclude=./node_modules --exclude=./.git -cf - . ) \
    | ( cd "$destination" && tar -xf - )
}

cleanup() { rm -rf "$WORK" 2>/dev/null; }
trap cleanup EXIT

run_case() {
  local label="$1"; shift
  local mutate="$1"; shift

  local target="$WORK/$label/Resource-Center-Plugin"
  rm -rf "$WORK/$label"
  copy_plugin "$target"

  ( cd "$target" && eval "$mutate" )

  if ( cd "$target" && PATH="$(dirname "$NODE_BIN"):$PATH" "$PY" scripts/validate.py ) >"$WORK/$label.log" 2>&1; then
    echo "SELFTEST FAIL  $label — validate.py reported OK on deliberately broken code"
    sed 's/^/               /' "$WORK/$label.log"
    fail=$((fail + 1))
  else
    echo "SELFTEST OK    $label — caught"
    pass=$((pass + 1))
  fi
}

# 1. Plugin directory name != `# name:` (the install-time mismatch warning)
rm -rf "$WORK/wrong-directory-name"
copy_plugin "$WORK/wrong-directory-name/Wrong-Name"
if ( cd "$WORK/wrong-directory-name/Wrong-Name" && "$PY" scripts/validate.py ) >"$WORK/dirname.log" 2>&1; then
  echo "SELFTEST FAIL  wrong-directory-name — not caught"
  fail=$((fail + 1))
else
  echo "SELFTEST OK    wrong-directory-name — caught"
  pass=$((pass + 1))
fi

# 2. require_relative of a file under app/ (Zeitwerk::NameError at boot)
run_case "zeitwerk-require" \
  'printf "\nrequire_relative \"app/controllers/relay_rooms/rooms_controller\"\n" >> plugin.rb'

# 3. Engine mounted with append from after_initialize (silent 404)
run_case "append-mount" \
  "printf '\nafter_initialize do\n  Discourse::Application.routes.append { mount ::RelayRooms::Engine, at: \"/relay-rooms\" }\nend\n' >> plugin.rb"

# 4. Top-level route map switched to the object form (silently dropped)
run_case "object-route-map" \
  'printf "export default { resource: \"relay-rooms\", map() { this.route(\"index\"); } };\n" > assets/javascripts/discourse/relay-rooms-route-map.js'

# 5. Parent template that forgets {{outlet}} (blank page)
run_case "missing-outlet" \
  'printf "export default <template><div class=\"relay-rooms-route\"></div></template>;\n" > assets/javascripts/discourse/templates/relay-rooms.gjs'

# 6. Nav item name colliding with the page root class (stretched nav bar)
run_case "nav-class-collision" \
  "sed -i 's/const LINK_NAME = \"relay-rooms-nav-link\";/const LINK_NAME = \"relay-rooms\";/' assets/javascripts/discourse/initializers/relay-rooms-navigation.js"

# 7. Bare root SCSS rule carrying layout (the same collision, via CSS)
run_case "bare-root-scss" \
  'sed -i "s/^div\.relay-rooms {/.relay-rooms {/" assets/stylesheets/relay-rooms.scss'

# 8. Unbalanced braces (rules leak to top level site-wide)
run_case "unbalanced-scss" \
  'printf "\n.oops { color: red;\n" >> assets/stylesheets/relay-rooms.scss'

# 9. A stale core import that no longer exists
run_case "stale-import" \
  'sed -i "1i import DButton from \"discourse/components/d-button\";" admin/assets/javascripts/discourse/components/relay-rooms-status.gjs'

# 10. A serializer attribute with no reader (every endpoint 500s)
run_case "serializer-no-reader" \
  "sed -i 's/^               :activity_ratio/:activity_ratio_broken/' app/serializers/relay_rooms/room_serializer.rb"

# 11. Missing i18n key used from a template.
#     Anchored loosely on purpose: a `sed` that fails to match leaves the file
#     untouched and the case then "passes" for the wrong reason.
run_case "missing-i18n-key" \
  "sed -i -E 's/^([[:space:]]*)heading: .*/\1heading_renamed: \"x\"/' config/locales/client.zh_CN.yml"

# 12. register_asset on a JS file (Discourse raises)
run_case "register-js-asset" \
  'sed -i "s|^register_asset \"stylesheets/relay-rooms.scss\"|register_asset \"stylesheets/relay-rooms.scss\"\nregister_asset \"javascripts/discourse/components/relay-rooms-page.gjs\"|" plugin.rb'

# 13. A site setting with no label
run_case "missing-setting-label" \
  'printf "  site_settings:\n    relay_rooms_enabled: \"x\"\n" > config/locales/server_settings.en.yml'

# 14. request.format gate on the page action (404 on a matching URL)
run_case "format-gate" \
  'sed -i "s|raise Discourse::NotFound unless SiteSetting.relay_rooms_enabled|raise Discourse::NotFound unless request.format.html?\n      raise Discourse::NotFound unless SiteSetting.relay_rooms_enabled|" app/controllers/relay_rooms/pages_controller.rb'

# 15. A .gjs parse error (replaces the ENTIRE plugin bundle with a throw)
run_case "gjs-parse-error" \
  'printf "\n<script>\nexport const x = 1;\n</script>\n<template><div></div></template>\n" >> assets/javascripts/discourse/components/relay-rooms-icon.gjs'

# 16. PLUGIN_NAME used but never defined. This is the defect that aborted boot on
#     the real install: the NameError is caught by Plugin.initialization_guard,
#     which prints "You are unable to start Discourse ..." and calls exit 1, so
#     it also fails the later rake db:migrate step.
run_case "plugin-name-undefined" \
  'sed -i "/PLUGIN_NAME = \"Resource-Center-Plugin\"/d" plugin.rb'

# 17. PLUGIN_NAME defined AFTER the requires, while a required file reads it at
#     class-body evaluation time. The reading form is `engine_name PLUGIN_NAME`,
#     so this mutation switches engine.rb back to that and moves the definition
#     to the bottom of plugin.rb.
run_case "plugin-name-defined-late" \
  'sed -i "s|^    engine_name \"relay_rooms\"$|    engine_name PLUGIN_NAME|" lib/relay_rooms/engine.rb; sed -i "/PLUGIN_NAME = \"Resource-Center-Plugin\"/d" plugin.rb; printf "\nmodule ::RelayRooms\n  PLUGIN_NAME = \"Resource-Center-Plugin\"\nend\n" >> plugin.rb'

# 18. Engine missing `engine_name` entirely
run_case "engine-missing-engine-name" \
  'sed -i "s/^    engine_name \"relay_rooms\"$//" lib/relay_rooms/engine.rb'

# 18b. engine_name handed a name that is not a lowercase slug. engine_name
#      aliases railtie_name, a Rails-internal identifier used to derive route
#      names, so a plugin name with uppercase/dashes must not go there.
run_case "engine-name-not-a-slug" \
  'sed -i "s|^    engine_name \"relay_rooms\"$|    engine_name PLUGIN_NAME|" lib/relay_rooms/engine.rb'

# 20. A bare "#" line in plugin.rb. Plugin::Metadata#parse_line splits it to an
#     empty list, leaving attribute nil, and calls .strip on it. That runs in
#     Plugin::Instance.find_all, before any plugin activates, so the whole boot
#     aborts with a backtrace naming no plugin.
run_case "bare-hash-line-in-plugin-rb" \
  'sed -i "s|^# transpile_js: true$|# transpile_js: true\n#|" plugin.rb'

# 21. Same crash via a different line shape: "#:" also splits to nothing, so a
#     check that only greps for a bare "#" would let this through.
run_case "colon-only-comment-line" \
  'sed -i "s|^# transpile_js: true$|# transpile_js: true\n#:|" plugin.rb'

# 19. Serializer moved back into lib/, where it cannot resolve its
#     Zeitwerk-loaded base class during plugin activation.
run_case "serializer-in-lib" \
  'mv app/serializers/relay_rooms/room_serializer.rb lib/relay_rooms/room_serializer.rb'

# 20. lib/ added to autoload_paths while a file's constant does not match its
#     path — Zeitwerk::NameError on eager load.
run_case "lib-autoloaded-constant-mismatch" \
  'sed -i "s|^    isolate_namespace RelayRooms$|    isolate_namespace RelayRooms\n    config.autoload_paths << File.join(config.root, \"lib\")|" lib/relay_rooms/engine.rb; printf "# frozen_string_literal: true\n\nmodule ::RelayRooms\n  module WrongConstantName\n  end\nend\n" > lib/relay_rooms/helper_thing.rb'

echo
echo "selftest: $pass caught, $fail missed"

if [ "$fail" -ne 0 ]; then
  exit 1
fi

echo "All deliberately-broken variants were caught."
