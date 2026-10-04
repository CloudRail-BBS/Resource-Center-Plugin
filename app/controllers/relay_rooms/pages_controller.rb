# frozen_string_literal: true

module ::RelayRooms
  # Server-rendered shell for /relay-rooms.
  #
  # It exists so a direct visit, a refresh or a crawler gets real HTML instead
  # of a 404 — Ember only handles in-app transitions. The markup lands inside a
  # <noscript> block, so it is invisible to JS-enabled visitors and free in the
  # common case, which is exactly why it should carry real content.
  class PagesController < ::ApplicationController
    requires_plugin PLUGIN_NAME

    # This is an HTML page, not an XHR endpoint. Do NOT additionally gate on
    # `request.format.html?` — Discourse itself issues JSON-accepting preload
    # XHRs for page routes, and such a check turns those into a 404 on a URL
    # whose route matched perfectly.
    skip_before_action :check_xhr, only: :index

    def index
      raise Discourse::NotFound unless SiteSetting.relay_rooms_enabled

      payload =
        begin
          RelayRooms::RoomList.cached
        rescue RelayRooms::ApiClient::Error
          nil
        end

      @node_name = payload&.fetch("node_name", nil) || I18n.t("relay_rooms.unknown_node")
      @rooms = payload ? payload["rooms"] : []
      @room_count = @rooms&.size.to_i
      @page_title = I18n.t("relay_rooms.page.title")
      @fetched_at = payload&.fetch("fetched_at", nil)
      @updated_at = payload&.fetch("update_time", nil)

      render :index
    end
  end
end
