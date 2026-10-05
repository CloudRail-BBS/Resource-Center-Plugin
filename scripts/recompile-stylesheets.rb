# frozen_string_literal: true

# Recompiles this plugin's stylesheets through the real pipeline, bypassing the
# two places that swallow errors during a normal rebuild:
#
#   1. Builder#compile wraps StylesheetCache.add in a bare `rescue` and only logs
#      "Completely unexpected error adding item to cache ..." at warn level.
#   2. The assets:precompile rake task rescues NoMethodError and prints
#      "Skipping precompilation of CSS cause schema is old", aborting the rest of
#      the CSS precompile while still exiting 0.
#
# Either one leaves the page's <link> pointing at a stylesheet that was never
# written to the stylesheet_cache table, which the browser then rejects with
# "MIME type ('text/html') is not a supported stylesheet MIME type".
#
# Run it with:
#   bundle exec rails runner plugins/<plugin-dir>/scripts/recompile-stylesheets.rb
#
# Compiling here also WRITES the cache row the build failed to write, so the page
# often starts working immediately afterwards.

plugin_dir = File.basename(File.expand_path("..", __dir__))
targets = [plugin_dir, "#{plugin_dir}_admin"]

puts "plugin directory : #{plugin_dir}"
puts "Rails env        : #{Rails.env}"
puts

failures = []

targets.each do |target|
  puts "=== #{target} ==="

  before = StylesheetCache.where(target: target).count
  puts "  cache rows before : #{before}"

  begin
    builder = Stylesheet::Manager::Builder.new(target: target, manager: nil)
    css = builder.compile(force: true)
    puts "  compile           : ok (#{css.to_s.bytesize} bytes)"
  rescue StandardError => e
    failures << target
    puts "  compile           : FAILED"
    puts "  error             : #{e.class}: #{e.message}"
    # The first frames are the useful ones; the rest is Rails machinery.
    e.backtrace.to_a.first(12).each { |line| puts "      #{line}" }
  end

  after = StylesheetCache.where(target: target).order(id: :desc)
  puts "  cache rows after  : #{after.count}"

  if after.count.positive?
    row = after.first
    puts "  newest row        : digest=#{row.digest[0, 12]}… created=#{row.created_at}"
    puts "  row content       : #{row.content.to_s.bytesize} bytes"
  elsif !failures.include?(target)
    # Compile reported success but nothing landed: that is the swallowed add().
    puts "  !! compile succeeded but NO cache row was written."
    puts "     That is Builder#compile's bare rescue around StylesheetCache.add."
    puts "     Look for this line in log/rails_production.log or the build output:"
    puts "       Completely unexpected error adding item to cache"
  end

  puts
end

puts "=== what the page asks for ==="
# `send` because Builder#digest is not part of the public surface.
link_digest = Stylesheet::Manager::Builder.new(target: plugin_dir, manager: nil).send(:digest)
puts "  expected digest   : #{link_digest}"

targets.each do |target|
  found = StylesheetCache.where(target: target, digest: link_digest).exists?
  puts format("  %-34s %s", target, found ? "present" : "MISSING")
end
puts

if failures.empty? && targets.all? { |t| StylesheetCache.where(target: t, digest: link_digest).exists? }
  puts "Both targets are cached for the digest the page requests."
  puts "Hard-reload the page (Ctrl+Shift+R) and the styles should apply."
else
  puts "Not resolved. Paste this whole output back and it will show the cause."
end
