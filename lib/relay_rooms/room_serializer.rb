# frozen_string_literal: true

module ::RelayRooms
  # A plain (non-ActiveRecord) object so it can pass through
  # `ActiveModel::Serializer` without tripping Discourse's
  # accidental-serialization guard, which only allows ActiveRecord models,
  # Hashes and plain objects.
  #
  # Every method named in the serializer's `attributes` list must resolve, or
  # the whole endpoint 500s.
  class RoomSerializer < ::ApplicationSerializer
    attributes :id,
               :display_id,
               :lookup_id,
               :status,
               :status_label,
               :player_size,
               :active_connection_size,
               :host_name,
               :map_name,
               :map_kind,
               :is_mod,
               :is_public,
               :is_custom,
               :is_full,
               :is_empty,
               :join_url,
               :join_label,
               :created_at,
               :created_at_label,
               :last_activity_at,
               :last_activity_ago,
               :uptime_label,
               :activity_ratio

    def id
      object[:room_id]
    end

    def display_id
      object[:display_id].presence || object[:room_id]
    end

    def lookup_id
      object[:lookup_id].presence || display_id
    end

    def status
      object[:status]
    end

    def status_label
      I18n.t("relay_rooms.status.#{object[:status]}")
    end

    def player_size
      object[:player_size]
    end

    def active_connection_size
      object[:active_connection_size]
    end

    def host_name
      object[:host_name]
    end

    def map_name
      object[:map_name]
    end

    def map_kind
      object[:map_kind]
    end

    def is_mod
      object[:is_mod]
    end

    def is_public
      object[:is_public]
    end

    def is_custom
      object[:is_custom]
    end

    def is_full
      object[:is_full]
    end

    def is_empty
      object[:is_empty]
    end

    def join_url
      object[:join_url]
    end

    def join_label
      object[:join_label]
    end

    def created_at
      object[:created_at]
    end

    def created_at_label
      format_time(object[:created_at])
    end

    def last_activity_at
      object[:last_activity_at]
    end

    def last_activity_ago
      seconds = object[:last_activity_ago]
      return nil if seconds.nil?

      relative_time(seconds)
    end

    def uptime_label
      seconds = object[:uptime_seconds]
      return nil if seconds.nil? || seconds.negative?

      hours, remainder = seconds.divmod(3600)
      minutes = remainder / 60

      if hours.positive?
        "#{hours}h #{minutes}m"
      else
        "#{minutes}m"
      end
    end

    def activity_ratio
      object[:activity_ratio]
    end

    private

    def format_time(timestamp)
      return nil if timestamp.nil?

      Time.at(timestamp).utc.strftime("%Y-%m-%d %H:%M UTC")
    rescue StandardError
      nil
    end

    def relative_time(seconds)
      case seconds
      when 0..59 then I18n.t("relay_rooms.relative.just_now")
      when 60..3599 then I18n.t("relay_rooms.relative.minutes", count: seconds / 60)
      when 3600..86_399 then I18n.t("relay_rooms.relative.hours", count: seconds / 3600)
      else I18n.t("relay_rooms.relative.days", count: seconds / 86_400)
      end
    end
  end
end
