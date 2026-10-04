# frozen_string_literal: true

module ::RelayRooms
  # Talks to a CNKD relay node's public room-listing endpoint and normalises
  # the payload into something the presenter can consume.
  #
  # The upstream response looks like:
  #
  #   {
  #     "ok": true,
  #     "data": {
  #       "nodeName": "CNKD 上海服务器",
  #       "role": "core",
  #       "roomCount": 11,
  #       "updateTime": "2026-10-04 13:29:13",
  #       "updateTimestamp": 1791091753074,
  #       "rooms": [ { "roomId": "682", "playerSize": 4, ... } ]
  #     }
  #   }
  class ApiClient
    class Error < StandardError
    end

    class DisabledError < Error
    end

    class HttpError < Error
    end

    class ParseError < Error
    end

    MAX_BODY_BYTES = 2 * 1024 * 1024

    def self.fetch
      new.fetch
    end

    # Returns a Hash describing the node plus its rooms, or raises ApiClient::Error.
    def fetch
      raise DisabledError, "relay rooms are disabled" unless SiteSetting.relay_rooms_enabled

      body = request_body
      payload = parse(body)

      {
        "node_name" => presence(payload.dig("data", "nodeName")) || I18n.t("relay_rooms.unknown_node"),
        "node_role" => presence(payload.dig("data", "role")),
        "node_code" => presence(payload.dig("data", "localNodeCode")),
        "room_count" => integer(payload.dig("data", "roomCount")) || rooms_of(payload).size,
        "update_time" => presence(payload.dig("data", "updateTime")),
        "update_timestamp" => integer(payload.dig("data", "updateTimestamp")),
        "rooms" => rooms_of(payload),
        "fetched_at" => Time.zone.now.to_i,
      }
    end

    private

    def request_body
      uri = endpoint_uri
      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/json"
      request["User-Agent"] = "Discourse-RelayRooms/#{RelayRooms::VERSION}"
      # Some relay deployments sit behind a CDN that caches aggressively.
      request["Cache-Control"] = "no-cache"

      response =
        Net::HTTP.start(
          uri.host,
          uri.port,
          use_ssl: uri.scheme == "https",
          open_timeout: timeout,
          read_timeout: timeout,
        ) { |http| http.request(request) }

      unless response.is_a?(Net::HTTPSuccess)
        raise HttpError, "upstream returned HTTP #{response.code}"
      end

      body = response.body.to_s
      raise HttpError, "upstream response is too large" if body.bytesize > MAX_BODY_BYTES

      body
    end

    def endpoint_uri
      url = SiteSetting.relay_rooms_api_url.to_s.strip
      raise HttpError, "relay_rooms_api_url is not configured" if url.blank?

      uri = URI.parse(url)
      unless uri.is_a?(URI::HTTP)
        raise HttpError, "relay_rooms_api_url must be an http(s) URL"
      end

      uri
    rescue URI::InvalidURIError
      raise HttpError, "relay_rooms_api_url is not a valid URL"
    end

    def parse(body)
      parsed = JSON.parse(body)
      raise ParseError, "upstream payload is not a Hash" unless parsed.is_a?(Hash)
      raise ParseError, "upstream reported an error (ok=false)" if parsed.key?("ok") && parsed["ok"] != true

      parsed
    rescue JSON::ParserError
      raise ParseError, "upstream payload is not valid JSON"
    end

    def rooms_of(payload)
      rooms = payload.dig("data", "rooms")
      rooms.is_a?(Array) ? rooms.select { |room| room.is_a?(Hash) } : []
    end

    def presence(value)
      string = value.to_s.strip
      string.presence
    end

    def integer(value)
      Integer(value, exception: false)
    end

    def timeout
      SiteSetting.relay_rooms_http_timeout.to_i.clamp(2, 30)
    end
  end
end
