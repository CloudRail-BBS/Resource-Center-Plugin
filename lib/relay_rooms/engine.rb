# frozen_string_literal: true

module ::RelayRooms
  # Mirrors discourse/discourse-plugin-skeleton's lib/my_plugin_module/engine.rb.
  #
  # `engine_name PLUGIN_NAME` is required, not cosmetic: it sets the engine's
  # name, which Rails uses for the engine's routes, helpers and asset lookup.
  # PLUGIN_NAME is defined in plugin.rb *above* the require_relative that loads
  # this file — this class body resolves it immediately, so the order matters.
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
  # the constant its path implies; this plugin's lib/ holds files whose names
  # would not match (and which are require_relative'd instead). Adding lib/ to
  # the autoload paths would turn those into Zeitwerk::NameError on eager load.
  class Engine < ::Rails::Engine
    engine_name PLUGIN_NAME
    isolate_namespace RelayRooms
  end
end
