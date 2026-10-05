import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";

// Required, like every other template identifier in a strict-mode .gjs: an
// unresolved helper is a compile error, and a compile error replaces the entire
// plugin bundle with a `throw`.
import { i18n } from "discourse-i18n";

// Explicit imports: these are NOT auto-registered as template helpers any more.
// Verified against core —
//   frontend/discourse/admin/templates/admin-logs/screened-urls.gjs
//     imports DPageSubheader from "discourse/ui-kit/d-page-subheader"
//   frontend/discourse/app/templates/exception.gjs
//     imports DButton from "discourse/ui-kit/d-button"
//
// Note `discourse/components/d-button` no longer exists — an older plugin would
// import that path and silently lose the entire bundle.
import DButton from "discourse/ui-kit/d-button";
import DPageSubheader from "discourse/ui-kit/d-page-subheader";

export default class RelayRoomsStatus extends Component {
  @service siteSettings;

  @tracked payload = null;
  @tracked checking = false;
  @tracked lastCheckedAt = null;

  // Derived lazily. A component is constructed before its model arrives, so
  // reading @model in a constructor reads undefined and blanks the page.
  get model() {
    return this.args.model ?? this.payload;
  }

  get meta() {
    return this.model?.meta ?? null;
  }

  get rooms() {
    return Array.isArray(this.model?.rooms) ? this.model.rooms : [];
  }

  get connected() {
    return Boolean(this.meta);
  }

  get connectionLabel() {
    return this.connected ? "relay_rooms.admin.connected" : "relay_rooms.admin.disconnected";
  }

  get connectionClass() {
    return this.connected
      ? "relay-rooms-status__value--ok"
      : "relay-rooms-status__value--error";
  }

  get endpoint() {
    return this.meta?.endpoint ?? null;
  }

  get nodeName() {
    return this.meta?.node_name ?? null;
  }

  get roomCount() {
    return this.meta?.room_count ?? this.rooms.length;
  }

  get updateTime() {
    return this.meta?.update_time ?? null;
  }

  get pluginVersion() {
    return this.meta?.plugin_version ?? null;
  }

  get enabled() {
    return Boolean(this.siteSettings.relay_rooms_enabled);
  }

  @action
  async testConnection() {
    if (this.checking) {
      return;
    }

    this.checking = true;

    try {
      this.payload = await ajax("/relay-rooms/rooms.json");
    } catch {
      this.payload = null;
    } finally {
      this.checking = false;
      this.lastCheckedAt = new Date().toLocaleTimeString();
    }
  }

  <template>
    <div class="relay-rooms-status">
      <DPageSubheader
        @titleLabel={{i18n "relay_rooms.admin.title"}}
        @descriptionLabel={{i18n "relay_rooms.admin.description"}}
      />

      {{#unless this.enabled}}
        <div class="relay-rooms-status__notice relay-rooms-status__notice--warn">
          {{i18n "relay_rooms.admin.enabled_hint"}}
        </div>
      {{/unless}}

      <div class="relay-rooms-status__grid">
        <div class="relay-rooms-status__row">
          <span class="relay-rooms-status__label">{{i18n "relay_rooms.admin.connection"}}</span>
          <span class="relay-rooms-status__value {{this.connectionClass}}">
            {{i18n this.connectionLabel}}
          </span>
        </div>

        <div class="relay-rooms-status__row">
          <span class="relay-rooms-status__label">{{i18n "relay_rooms.admin.node_name"}}</span>
          <span class="relay-rooms-status__value">
            {{#if this.nodeName}}
              {{this.nodeName}}
            {{else}}
              {{i18n "relay_rooms.admin.not_configured"}}
            {{/if}}
          </span>
        </div>

        <div class="relay-rooms-status__row">
          <span class="relay-rooms-status__label">{{i18n "relay_rooms.admin.room_count"}}</span>
          <span class="relay-rooms-status__value">{{this.roomCount}}</span>
        </div>

        <div class="relay-rooms-status__row">
          <span class="relay-rooms-status__label">{{i18n "relay_rooms.admin.last_update"}}</span>
          <span class="relay-rooms-status__value">
            {{#if this.updateTime}}
              {{this.updateTime}}
            {{else}}
              {{i18n "relay_rooms.admin.not_configured"}}
            {{/if}}
          </span>
        </div>

        <div class="relay-rooms-status__row">
          <span class="relay-rooms-status__label">{{i18n "relay_rooms.admin.endpoint"}}</span>
          <span class="relay-rooms-status__value relay-rooms-status__value--mono">
            {{#if this.endpoint}}
              {{this.endpoint}}
            {{else}}
              {{i18n "relay_rooms.admin.not_configured"}}
            {{/if}}
          </span>
        </div>

        <div class="relay-rooms-status__row">
          <span class="relay-rooms-status__label">{{i18n "relay_rooms.admin.plugin_version"}}</span>
          <span class="relay-rooms-status__value relay-rooms-status__value--mono">
            {{this.pluginVersion}}
          </span>
        </div>
      </div>

      <div class="relay-rooms-status__actions">
        <DButton
          @label="relay_rooms.admin.refresh_now"
          @icon="sync"
          @isLoading={{this.checking}}
          @action={{this.testConnection}}
        />
      </div>

      <p class="relay-rooms-status__hint">{{i18n "relay_rooms.admin.settings_hint"}}</p>
    </div>
  </template>
}
