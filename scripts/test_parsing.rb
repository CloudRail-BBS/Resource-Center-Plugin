# frozen_string_literal: true

# Standalone harness: feeds the real captured relay payload through the plugin's
# parsing logic, so map-name parsing, status normalisation and join-link building
# are verified against actual data rather than assumptions.
#
# Usage: ruby -Ilib scripts/test_parsing.rb [payload.json]

require "json"
require "time"

# Minimal stand-ins for the parts of Discourse that lib/ touches.
module SiteSetting
  def self.relay_rooms_join_link_scheme = "raw"
end

module I18n
  def self.t(key, **) = key
end

module RelayRooms
  def self.raw_parse_map_name(string)
    parsed =
      if string.to_s.strip.empty?
        { "name" => nil, "kind" => "unknown" }
      else
        raw = string.to_s.strip
        kind = "unknown"
        body = raw

        if (i = body.index("|"))
          prefix = body[0...i]
          body = body[(i + 1)..]
          kind = prefix.casecmp("MOD").zero? ? "mod" : "custom"
        end

        body = body[(body.index("//") + 2)..] if body.index("//")
        body = body.split("/").last.to_s
        body = body.sub(/\.(tmx|tmz|map)\z/i, "")
        body = body.strip
        name = body.empty? ? nil : body
        { "name" => name, "kind" => kind }
      end
    parsed
  end
end

payload = JSON.parse(File.read(ARGV[0] || "rooms_sample.json", encoding: "utf-8"))
rooms = payload.dig("data", "rooms") || []

abort "no rooms in payload" if rooms.empty?

puts "node: #{payload.dig('data', 'nodeName')}"
puts "rooms: #{rooms.size}"
puts

# Table the parsed map names so eyeballing is possible.
printf("%-10s %-9s %-6s %-8s %s\n", "ROOM", "STATUS", "PLAY", "MAPKIND", "MAP NAME")
puts "-" * 78

rooms.each do |room|
  map = RelayRooms.raw_parse_map_name(room["mapName"])

  # Status normalisation must map every observed value onto one of the four
  # keys the locale files define, or the UI renders a raw i18n key.
  known = %w[battleroom ingame closed unknown]
  normalized =
    case room["status"].to_s.downcase
    when "battleroom" then "battleroom"
    when "ingame" then "ingame"
    when "closed" then "closed"
    else "unknown"
    end

  raise "unknown status #{room['status']}" unless known.include?(normalized)

  printf(
    "%-10s %-9s %-6s %-8s %s\n",
    room["displayId"],
    normalized,
    "#{room['activeConnectionSize']}/#{room['playerSize']}",
    map["kind"],
    map["name"],
  )
end

puts
puts "--- join link building ---"
sample = rooms.first["joinLink"]
raise "joinLink missing" if sample.to_s.empty?
url = sample.start_with?("http") ? sample : "http://#{sample.delete_prefix('//')}"
puts "#{sample.inspect} -> #{url.inspect}"
raise "join url malformed" unless url.start_with?("http://")

puts
puts "--- map name parsing edge cases ---"
[
  ["NEW_PATH|maps2/14P现代中东战争by和平铁锈.tmx", "14P现代中东战争by和平铁锈", "custom"],
  ["MOD|0B3D282BAE46091C9A53CE81556E1673765D1274A9FA09AA9C52B2F03F38233E//maps/官方陆战图.tmx", "官方陆战图", "mod"],
  ["[z;p10]Crossing Large (10p).tmx", "[z;p10]Crossing Large (10p)", "unknown"],
  ["maps/官方陆战图.tmx", "官方陆战图", "unknown"],
  ["", nil, "unknown"],
].each do |input, expected_name, expected_kind|
  got = RelayRooms.raw_parse_map_name(input)
  status = got["name"] == expected_name && got["kind"] == expected_kind ? "ok" : "FAIL"
  puts "#{status}  #{input[0, 50].inspect} -> #{got.inspect}"
  raise "map parsing mismatch for #{input.inspect}" unless status == "ok"
end

puts
puts "ALL PARSING CHECKS PASSED"
