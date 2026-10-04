# frozen_string_literal: true

module ::RelayRooms
  # JSON endpoint the frontend polls. Public read-only data, so no login is
  # required — but the payload is still gated on the plugin being enabled.
  class RoomsController < ::ApplicationController
    requires_plugin PLUGIN_NAME

    def index
      unless SiteSetting.relay_rooms_enabled
        return render json: { errors: [I18n.t("relay_rooms.errors.disabled")] }, status: 404
      end

      payload = RelayRooms::RoomList.cached
      render json: { rooms: serialize_rooms(payload), meta: meta_hash(payload) }
    rescue RelayRooms::ApiClient::Error => e
      render_json_error(e.message, status: 502)
    end

    def meta
      unless SiteSetting.relay_rooms_enabled
        return render json: { errors: [I18n.t("relay_rooms.errors.disabled")] }, status: 404
      end

      render json: { meta: meta_hash(RelayRooms::RoomList.cached) }
    rescue RelayRooms::ApiClient::Error => e
      render_json_error(e.message, status: 502)
    end

    private

    # `RoomSerializer` is an ActiveModel serializer, not an ActiveRecord one,
    # so build the instances directly rather than going through
    # `serialize_data` (which assumes a model with `to_ary` semantics).
    def serialize_rooms(payload)
      Array(payload["rooms"]).map do |room|
        RelayRooms::RoomSerializer.new(room, scope: guardian, root: false).as_json
      end
    end

    def meta_hash(payload)
      {
        node_name: payload["node_name"],
        node_role: payload["node_role"],
        node_code: payload["node_code"],
        room_count: payload["room_count"],
        reported_room_count: payload["reported_room_count"],
        update_time: payload["update_time"],
        update_timestamp: payload["update_timestamp"],
        fetched_at: payload["fetched_at"],
        refresh_seconds: SiteSetting.relay_rooms_refresh_seconds.to_i,
        request_timeout_ms: SiteSetting.relay_rooms_request_timeout_ms.to_i,
        show_ingame: SiteSetting.relay_rooms_show_ingame,
        join_link_scheme: SiteSetting.relay_rooms_join_link_scheme,
        plugin_version: RelayRooms::VERSION,
      }
    end
  end
end
