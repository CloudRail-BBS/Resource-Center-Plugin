# name: resource-center-plugin
# about: Display live relay game rooms (联机房) from a CNKD relay API on a Discourse page.
# version: 1.3.0
# authors: CloudRail BBS
# url: https://github.com/CloudRail-BBS/Resource-Center-Plugin
# required_version: 3.2.0
# transpile_js: true

# frozen_string_literal: true

# THE NAME AND DIRECTORY MUST BE LOWERCASE.
# Not a style preference — core's stylesheet route constrains the name to
# lowercase, so an uppercase directory silently loses its CSS:
#     # config/routes.rb
#     get "stylesheets/:name" => "stylesheets#show",
#         constraints: { name: /[-a-z0-9_]+/, format: "css" }, format: true
# With a directory named `Resource-Center-Plugin`, the emitted <link> points at
# /stylesheets/Resource-Center-Plugin_<digest>.css, that constraint does not
# match, the route never matches, and the request 404s. The controller is never
# reached — so the stylesheet cache is populated correctly, the compile succeeds,
# and every plugin beside it serves fine. The page renders completely unstyled,
# with default <ul> bullets and browser-default buttons, and the browser console
# reports "MIME type ('text/html') is not a supported stylesheet MIME type".
# The repo is named `Resource-Center-Plugin`; the plugin and its directory are
# `resource-center-plugin`. Clone with an explicit target, or rename the repo.
# Do not add a line to this file whose stripped content is just "#". Such a line
# makes Plugin::Metadata#parse_line call .strip on nil and abort the whole boot,
# before any plugin activates. Only plugin.rb is parsed this way. See README,
# section "plugin.rb 不能出现裸 # 行", for the mechanism. Official plugins
# (discourse-solved, discourse-data-explorer, docker_manager) contain zero such
# lines, which is the convention to follow. Paragraph breaks in this file are
# therefore written as blank lines, never as "#" rules.

# PLUGIN_NAME must equal both the `# name:` above and the installed directory
# name; all three are `resource-center-plugin` here. That matters because core
# keys two lookups off two different values: `AdminPluginSerializer#id` returns
# `directory_name` (the DIRECTORY), which is what the admin plugin list,
# `api.setAdminPluginIcon` and `api.addAdminPluginConfigurationNav` match against,
# while `Discourse.plugins_by_name` is keyed by the plugin name and is what
# `add_admin_route`'s location resolves through.
# PLUGIN_NAME is not provided by core: `Plugin::Instance#activate!` runs
# `instance_eval File.read(path), path`, and nothing in lib/plugin/instance.rb
# defines it. Undefined, `requires_plugin PLUGIN_NAME` raises NameError, which
# `Plugin.initialization_guard` catches, printing "You are unable to start
# Discourse due to errors in the plugin at <dir>" and calling `exit 1` -- the same
# `exit 1` that then fails the following `rake db:migrate` step.
# It must be defined before the engine is required: engine.rb reads PLUGIN_NAME
# while its class body is evaluated.
module ::RelayRooms
  PLUGIN_NAME = "resource-center-plugin"
end

# lib/ is not autoloaded, so these must be required explicitly. The serializer is
# deliberately absent: anything subclassing a Zeitwerk-loaded app class
# (ApplicationSerializer, ApplicationController, ...) cannot be required here,
# because plugin activation happens before the autoloader exists. Those files live
# in app/ and load after boot.
require_relative "lib/relay_rooms/version"
require_relative "lib/relay_rooms/api_client"
require_relative "lib/relay_rooms/room_presenter"
require_relative "lib/relay_rooms/room_list"
require_relative "lib/relay_rooms/engine"

enabled_site_setting :relay_rooms_enabled

# The plugin serves its own top-level page, so the stylesheet has to be registered
# explicitly -- nothing under assets/stylesheets is auto-included.
register_asset "stylesheets/relay-rooms.scss"
register_asset "stylesheets/relay-rooms-admin.scss", :admin

after_initialize do
  # `use_new_show_route: true` sets `full_location` to `adminPlugins.show`, a CORE
  # route, so the link on /admin/plugins always resolves. The location must be the
  # plugin's name (which equals the directory name), because core loads the page
  # via `Discourse.plugins_by_name[params[:plugin_id]]`.
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
