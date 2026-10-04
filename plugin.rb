# name: discourse-relay-rooms
# about: Display live relay game rooms (联机房) from a CNKD relay API on a Discourse page.
# version: 1.1.0
# authors: CloudRail BBS
# url: https://github.com/CloudRail-BBS/Resource-Center-Plugin
# required_version: 3.2.0
# transpile_js: true

# frozen_string_literal: true

# PLUGIN_NAME is NOT provided by core.
#
# `Plugin::Instance#activate!` runs `instance_eval File.read(path), path`, and
# nothing in core defines a PLUGIN_NAME constant (grep lib/plugin/instance.rb:
# zero hits). The official plugin skeleton defines it explicitly, and both its
# engine and its controller then reference it.
#
# Leave it undefined and `requires_plugin PLUGIN_NAME` raises NameError. Because
# plugin.rb is evaluated from `config/application.rb`'s body — BEFORE
# `Rails.application.initialize!` — that NameError is caught by
# `Plugin.initialization_guard`, which prints
# "You are unable to start Discourse due to errors in the plugin at <dir>" and
# calls `exit 1`. `exit 1` is also what makes the following `rake db:migrate`
# step fail with Pups::ExecError: the two symptoms are one event.
#
# It must be defined BEFORE the engine is required — engine.rb resolves
# `engine_name PLUGIN_NAME` while its class body is evaluated.
module ::RelayRooms
  PLUGIN_NAME = "discourse-relay-rooms"
end

# lib/ is not autoloaded — these must be required explicitly.
#
# Note what is deliberately NOT in this list: the serializer. Anything that
# subclasses a Zeitwerk-loaded app class (ApplicationSerializer,
# ApplicationController, …) must not be required here, because plugin activation
# happens before the autoloader exists. Such files live in app/ and are loaded
# after boot.
require_relative "lib/relay_rooms/version"
require_relative "lib/relay_rooms/api_client"
require_relative "lib/relay_rooms/room_presenter"
require_relative "lib/relay_rooms/room_list"
require_relative "lib/relay_rooms/engine"

enabled_site_setting :relay_rooms_enabled

# The plugin serves its own top-level page, so the stylesheet has to be
# registered explicitly — nothing under assets/stylesheets is auto-included.
register_asset "stylesheets/relay-rooms.scss"
register_asset "stylesheets/relay-rooms-admin.scss", :admin

after_initialize do
  # Admin plugin page. `use_new_show_route: true` sets `full_location` to
  # `adminPlugins.show`, a CORE route, so the link on /admin/plugins always
  # resolves. With `false` it becomes `adminPlugins.<slug>`, which only exists
  # if the plugin mounts it — and the legacy mount point is dead.
  #
  # The location must be the plugin's NAME (its `# name:`, which equals the
  # installed directory name) — not an arbitrary slug. Core loads the page via
  # `Discourse.plugins_by_name[params[:plugin_id]]`, so anything else 404s on
  # /admin/plugins/<location>.json.
  #
  # Referenced through the absolute constant rather than a bare PLUGIN_NAME:
  # plugin.rb is evaluated as a string, so its top-level cref is Object, where a
  # bare PLUGIN_NAME would resolve to ::PLUGIN_NAME and miss RelayRooms::.
  add_admin_route(
    "relay_rooms.admin.title",
    ::RelayRooms::PLUGIN_NAME,
    use_new_show_route: true,
  )
end
