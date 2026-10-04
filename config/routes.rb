# frozen_string_literal: true

# Rails loads this file through the engine routes reloader while the
# application's route set is still open, which is why `draw` is correct here.
# Moving the mount into `after_initialize` with `append` fails silently: the
# route set is already finalised and `/relay-rooms` 404s on every direct visit
# while in-app transitions keep working.
RelayRooms::Engine.routes.draw do
  get "/" => "pages#index"
  get "/rooms.json" => "rooms#index"
  get "/meta.json" => "rooms#meta"
end

Discourse::Application.routes.draw { mount ::RelayRooms::Engine, at: "/relay-rooms" }
