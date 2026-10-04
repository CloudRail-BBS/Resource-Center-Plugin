# frozen_string_literal: true

module ::RelayRooms
  # Builds the cached room payload and hands it to the serializer.
  module RoomList
    CACHE_KEY = "relay_rooms:rooms:v1"

    module_function

    # Returns the normalised payload Hash. Raises RelayRooms::ApiClient::Error.
    def fetch
      raw = RelayRooms::ApiClient.fetch
      rooms = build_rooms(raw["rooms"], raw["update_timestamp"])

      {
        "node_name" => raw["node_name"],
        "node_role" => raw["node_role"],
        "node_code" => raw["node_code"],
        "room_count" => RelayRooms.effective_room_count(raw["rooms"]),
        "reported_room_count" => raw["room_count"],
        "update_time" => raw["update_time"],
        "update_timestamp" => raw["update_timestamp"],
        "fetched_at" => raw["fetched_at"],
        "rooms" => rooms,
      }
    end

    def cached
      ttl = SiteSetting.relay_rooms_cache_seconds.to_i
      return fetch if ttl <= 0

      Discourse.cache.fetch(CACHE_KEY, expires_in: ttl.seconds) { fetch }
    end

    def build_rooms(rooms, node_timestamp)
      now = Time.zone.now.to_i
      filtered = Array(rooms).select { |room| visible?(room) }

      filtered
        .map { |room| build_room(room, node_timestamp, now) }
        .sort_by { |room| [status_rank(room[:status]), -room[:created_at].to_i] }
    end

    def visible?(room)
      return false unless room.is_a?(Hash)
      return false if RelayRooms.normalize_status(room["status"]) == "closed"

      normalized = RelayRooms.normalize_status(room["status"])
      return false if normalized == "ingame" && !SiteSetting.relay_rooms_show_ingame

      true
    end

    def status_rank(status)
      status == "battleroom" ? 0 : 1
    end

    def build_room(room, node_timestamp, now)
      map = RelayRooms.parse_map_name(room["mapName"])
      player_size = room["playerSize"].to_i
      active = room["activeConnectionSize"].to_i
      created_at = room["roomCreateTime"].to_i
      last_activity = room["lastActivityTime"].to_i
      # Upstream reports activity in seconds; the node timestamp is in ms.
      # Be tolerant of either unit rather than silently printing nonsense.
      last_activity_at = last_activity > 1_000_000_000_000 ? last_activity / 1000 : last_activity

      {
        room_id: room["roomId"].to_s,
        display_id: room["displayId"].to_s.presence,
        lookup_id: room["lookupId"].to_s.presence,
        status: RelayRooms.normalize_status(room["status"]),
        player_size: player_size,
        active_connection_size: active,
        host_name: room["hostName"].to_s.presence,
        map_name: map["name"],
        map_kind: map["kind"],
        is_mod: room["isMod"] == true,
        is_public: room["publicRoom"] == true,
        is_custom: room["customRoom"] == true,
        is_full: player_size.positive? && active >= player_size,
        is_empty: active.zero?,
        join_url: RelayRooms.join_url(room["joinLink"]),
        join_label: room["joinLink"].to_s.presence,
        created_at: created_at.positive? ? created_at : nil,
        last_activity_at: last_activity_at.positive? ? last_activity_at : nil,
        last_activity_ago: last_activity_at.positive? ? [now - last_activity_at, 0].max : nil,
        uptime_seconds: created_at.positive? ? (now - created_at) : nil,
        activity_ratio:
          if player_size.positive?
            (active.to_f / player_size).clamp(0.0, 1.0)
          else
            0.0
          end,
      }
    end
  end
end
