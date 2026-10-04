# frozen_string_literal: true

module ::RelayRooms
  # Based on discourse/discourse-plugin-skeleton's lib/my_plugin_module/engine.rb,
  # with one deliberate difference: `engine_name` is a lowercase slug rather than
  # PLUGIN_NAME.
  #
  # WHY NOT `engine_name PLUGIN_NAME` HERE:
  #
  # In railties/lib/rails/engine.rb, `engine_name` is literally
  # `alias :engine_name :railtie_name`, and railtie_name is a Rails-internal
  # identifier, not a user-facing label. Two things follow from it:
  #
  #   * `mount` derives its default route name from it
  #     ("the :as option given to mount takes the engine_name as default"), and
  #   * railtie_name is used to identify the railtie inside Rails.
  #
  # This plugin's name is `Resource-Center-Plugin` — uppercase and dashed. Ruby
  # tolerates it via `define_method` (which is what modern Rails uses to build
  # URL helpers), but `def Resource-Center-Plugin` is a syntax error, so any
  # code path that string-evals the name would break. Setting a conventional
  # lowercase slug removes that entire class of risk, and nothing in this plugin
  # depends on engine_name matching the plugin name: the engine is mounted at an
  # explicit `at:`, its namespace comes from `isolate_namespace` (the MODULE, not
  # the engine name), and Discourse's plugin asset lookup uses the plugin
  # DIRECTORY via `DiscoursePluginRegistry.stylesheets_exists?(directory_name)`.
  #
  # Rails documents overriding it directly (engine.rb: `engine_name "my_engine"`),
  # so this is the supported mechanism, not a workaround.
  #
  # There is deliberately no `config.paths["app/controllers"] << …` here. With
  # `isolate_namespace`, a controller's namespace comes from its DIRECTORY under
  # app/controllers (app/controllers/relay_rooms/rooms_controller.rb defines
  # RelayRooms::RoomsController — same as the skeleton's
  # app/controllers/my_plugin_module/examples_controller.rb). Adding the
  # subdirectory as a second autoload root makes the same file reachable under
  # two roots, which is a Zeitwerk conflict rather than a fix.
  #
  # `config.autoload_paths << File.join(config.root, "lib")` is also omitted on
  # purpose. The skeleton can do that because every file under its lib/ defines
  # the constant its path implies. This plugin's lib/ does too now, but the files
  # are require_relative'd from plugin.rb anyway, so there is nothing to gain and
  # one more way to get a Zeitwerk::NameError on eager load.
  class Engine < ::Rails::Engine
    engine_name "relay_rooms"
    isolate_namespace RelayRooms
  end
end
