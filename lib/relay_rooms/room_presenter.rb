# frozen_string_literal: true

module ::RelayRooms
  # Normalises the relay API's raw values into display-ready ones.
  #
  # The module is named `RoomPresenter` because the file is `room_presenter.rb` —
  # Zeitwerk derives the expected constant from the path, and lib/ must stay
  # self-consistent in case it is ever added to the autoload paths.
  module RoomPresenter
    module_function

    # Relay map identifiers arrive in a few shapes, all of which encode the raw
    # asset name after the last separator:
    #
    #   "NEW_PATH|maps2/14P现代中东战争by和平铁锈.tmx"
    #   "MOD|0B3D28...//maps/官方陆战图.tmx"
    #   "[z;p10]Crossing Large (10p).tmx"
    #   "maps/官方陆战图.tmx"
    #
    # Returns a display label plus whether the map is a bundled/official one.
    def parse_map_name(raw)
      string = raw.to_s.strip
      return { "name" => nil, "kind" => "unknown" } if string.blank?

      kind = "unknown"
      body = string

      if (index = body.index("|"))
        prefix = body[0...index]
        body = body[(index + 1)..]
        kind = prefix.casecmp("MOD").zero? ? "mod" : "custom"
      end

      # MOD identifiers embed a content hash separated from the path by "//".
      if (index = body.index("//"))
        body = body[(index + 2)..]
      end

      # Strip the directory portion and the .tmx/.tmz extension.
      body = body.split("/").last.to_s
      body = body.sub(/\.(tmx|tmz|map)\z/i, "")
      body = body.strip

      { "name" => body.presence, "kind" => kind }
    end

    # "battleroom" -> "battleroom", "ingame" -> "ingame"; anything unrecognised
    # collapses to "unknown" so the UI always has a translation to resolve.
    def normalize_status(raw)
      case raw.to_s.strip.downcase
      when "battleroom", "battle_room", "battle", "lobby"
        "battleroom"
      when "ingame", "in_game", "playing", "started"
        "ingame"
      when "closed", "close", "ended", "finished"
        "closed"
      else
        "unknown"
      end
    end

    # Turns the upstream joinLink into something clickable. Values are
    # "www.cnkd.fun/RKC682" or sometimes a full URL already.
    def join_url(raw)
      string = raw.to_s.strip
      return nil if string.blank?
      return string if string.match?(%r{\Ahttps?://}i)

      string = string.delete_prefix("//")

      if SiteSetting.relay_rooms_join_link_scheme == "cnkd"
        "cnkd://#{string}"
      else
        "http://#{string}"
      end
    end

    def effective_room_count(rooms)
      return 0 if rooms.blank?

      rooms.count { |room| normalize_status(room["status"]) != "closed" }
    end
  end
end
