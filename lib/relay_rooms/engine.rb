# frozen_string_literal: true

module ::RelayRooms
  class Engine < ::Rails::Engine
    isolate_namespace RelayRooms

    config.paths["app/controllers"] << "app/controllers/relay_rooms"
  end
end
