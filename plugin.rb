# name: discourse-relay-rooms
# about: Display live relay game rooms (联机房) from a CNKD relay API on a Discourse page.
# version: 1.0.0
# authors: CloudRail BBS
# url: https://github.com/CloudRail-BBS/Resource-Center-Plugin
# required_version: 3.2.0
# transpile_js: true

# frozen_string_literal: true

require_relative "lib/relay_rooms/api_client"
require_relative "lib/relay_rooms/room_presenter"
require_relative "lib/relay_rooms/room_list"
require_relative "lib/relay_rooms/room_serializer"
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
  add_admin_route("relay_rooms.admin.title", "discourse-relay-rooms", use_new_show_route: true)
end
