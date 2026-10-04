# frozen_string_literal: true

# Exercises the plugin's REAL parsing code against the captured relay payload.
#
# This deliberately does not re-implement the parsing: a test that copies the
# logic under test passes even when the real file diverges, which is the one
# failure mode it exists to catch. It loads lib/relay_rooms/room_presenter.rb
# directly and only shims the two Rails/ActiveSupport bits that file needs.
#
# Usage: ruby scripts/test_parsing.rb [payload.json]

require "json"

# --- minimal ActiveSupport shims, so the real file loads without Rails --------
class Object
  def blank?
    respond_to?(:empty?) ? !!empty? : !self
  end

  def presence
    blank? ? nil : self
  end
end

class NilClass
  def blank?
    true
  end
end

# room_presenter.rb reads this when building a join link.
module SiteSetting
  def self.relay_rooms_join_link_scheme
    ENV.fetch("RELAY_JOIN_SCHEME", "raw")
  end
end

require_relative "../lib/relay_rooms/room_presenter"

PRESENTER = RelayRooms::RoomPresenter
FAILURES = []

def check(label, actual, expected)
  if actual == expected
    puts "ok    #{label}"
  else
    puts "FAIL  #{label}\n        expected: #{expected.inspect}\n        actual:   #{actual.inspect}"
    FAILURES << label
  end
end

# ---------------------------------------------------------------------------
puts "=== map name parsing (real implementation) ==="

[
  ["NEW_PATH|maps2/14P现代中东战争by和平铁锈.tmx", "14P现代中东战争by和平铁锈", "custom"],
  ["MOD|0B3D282BAE46091C9A53CE81556E1673765D1274A9FA09AA9C52B2F03F38233E//maps/官方陆战图.tmx",
   "官方陆战图", "mod"],
  ["[z;p10]Crossing Large (10p).tmx", "[z;p10]Crossing Large (10p)", "unknown"],
  ["maps/官方陆战图.tmx", "官方陆战图", "unknown"],
  ["MOD|abc//地图/[p10]草地 (10p).tmx", "[p10]草地 (10p)", "mod"],
  ["", nil, "unknown"],
  [nil, nil, "unknown"],
  ["foo.tmz", "foo", "unknown"],
  ["foo.map", "foo", "unknown"],
  ["dir/nested/deep.tmx", "deep", "unknown"],
].each do |input, expected_name, expected_kind|
  got = PRESENTER.parse_map_name(input)
  check("parse_map_name(#{input.inspect[0, 40]})",
        [got["name"], got["kind"]], [expected_name, expected_kind])
end

puts
puts "=== status normalisation ==="

{
  "battleroom" => "battleroom",
  "BATTLE_ROOM" => "battleroom",
  "lobby" => "battleroom",
  "ingame" => "ingame",
  "In_Game" => "ingame",
  "playing" => "ingame",
  "closed" => "closed",
  "finished" => "closed",
  "" => "unknown",
  "something-new" => "unknown",
}.each do |input, expected|
  check("normalize_status(#{input.inspect})", PRESENTER.normalize_status(input), expected)
end

puts
puts "=== join url ==="

check("bare host", PRESENTER.join_url("www.cnkd.fun/RKC682"), "http://www.cnkd.fun/RKC682")
check("protocol-relative", PRESENTER.join_url("//www.cnkd.fun/RKC682"), "http://www.cnkd.fun/RKC682")
check("already https", PRESENTER.join_url("https://x.test/a"), "https://x.test/a")
check("blank", PRESENTER.join_url(""), nil)
check("nil", PRESENTER.join_url(nil), nil)

puts
puts "=== effective room count ==="
check("nil input", PRESENTER.effective_room_count(nil), 0)
check("empty", PRESENTER.effective_room_count([]), 0)
check("counts non-closed",
      PRESENTER.effective_room_count(
        [{ "status" => "ingame" }, { "status" => "battleroom" }, { "status" => "closed" }],
      ), 2)

# ---------------------------------------------------------------------------
payload_path = ARGV[0] || File.expand_path("../rooms_sample.json", __dir__)

if File.exist?(payload_path)
  puts
  puts "=== live payload (#{File.basename(payload_path)}) ==="

  payload = JSON.parse(File.read(payload_path, encoding: "utf-8"))
  rooms = payload.dig("data", "rooms") || []

  if rooms.empty?
    puts "FAIL  payload contains no rooms"
    FAILURES << "payload empty"
  else
    puts "node:  #{payload.dig('data', 'nodeName')}"
    puts "rooms: #{rooms.size}"
    puts
    printf("%-10s %-11s %-6s %-8s %s\n", "ROOM", "STATUS", "PLAY", "MAPKIND", "MAP NAME")
    puts "-" * 76

    rooms.each do |room|
      map = PRESENTER.parse_map_name(room["mapName"])
      status = PRESENTER.normalize_status(room["status"])

      # Every status must land on a key the locale files actually define, or the
      # UI renders a raw i18n key.
      unless %w[battleroom ingame closed unknown].include?(status)
        puts "FAIL  unmapped status #{room['status'].inspect}"
        FAILURES << "status #{room['status']}"
      end

      printf("%-10s %-11s %-6s %-8s %s\n",
             room["displayId"], status,
             "#{room['activeConnectionCount'] || room['activeConnectionSize']}/#{room['playerSize']}",
             map["kind"], map["name"])
    end

    # The first room's joinLink is the documented shape; assert it builds.
    sample = rooms.first["joinLink"]
    check("live joinLink builds", PRESENTER.join_url(sample).to_s.start_with?("http"), true)
  end
else
  puts
  puts "note  no payload at #{payload_path}; skipped the live-data section"
end

# ---------------------------------------------------------------------------
puts
if FAILURES.empty?
  puts "ALL PARSING CHECKS PASSED"
  exit 0
else
  puts "#{FAILURES.size} FAILURE(S)"
  exit 1
end
