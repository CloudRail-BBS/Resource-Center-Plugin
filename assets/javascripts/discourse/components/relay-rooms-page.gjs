import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import RelayRoomsIcon from "./relay-rooms-icon";

// `eq` is not an auto-registered helper: every template identifier must be in
// scope, and an unresolved helper is a compile-time failure which replaces the
// entire plugin bundle with a `throw`. Import it explicitly rather than relying
// on it being global.
import { eq } from "discourse/truth-helpers";

// Status tabs. Each entry precomputes its own i18n key so the template only
// ever calls {{i18n}} with a static string.
const FILTERS = [
  { value: "all", label: "relay_rooms.filters.all" },
  { value: "battleroom", label: "relay_rooms.status.battleroom" },
  { value: "ingame", label: "relay_rooms.status.ingame" },
];

export default class RelayRoomsPage extends Component {
  @tracked statusFilter = "all";
  @tracked copiedRoomId = null;

  #copyTimer = null;

  get controller() {
    return this.args.controller;
  }

  get rooms() {
    return this.controller?.rooms ?? [];
  }

  get meta() {
    return this.controller?.meta ?? null;
  }

  get loading() {
    return this.controller?.loading ?? false;
  }

  get loadedOnce() {
    return this.controller?.loadedOnce ?? false;
  }

  get errorMessage() {
    return this.controller?.errorMessage ?? null;
  }

  get isOffline() {
    return Boolean(this.errorMessage) && this.rooms.length === 0;
  }

  get nodeName() {
    return this.meta?.node_name ?? "";
  }

  get refreshSeconds() {
    return this.controller?.refreshSeconds ?? 30;
  }

  get filters() {
    return FILTERS.map((filter) => ({
      ...filter,
      isActive: filter.value === this.statusFilter,
      className: `btn btn-small relay-rooms__filter${
        filter.value === this.statusFilter ? " is-active" : ""
      }`,
    }));
  }

  // Derived lazily in a getter, never in a constructor — a component is
  // constructed before its model arrives, and reading the payload there throws
  // and blanks the page with no visible error.
  get visibleRooms() {
    if (this.statusFilter === "all") {
      return this.rooms;
    }

    return this.rooms.filter((room) => room.status === this.statusFilter);
  }

  get filteredEmpty() {
    return this.loadedOnce && this.rooms.length > 0 && this.visibleRooms.length === 0;
  }

  get showEmpty() {
    return this.loadedOnce && !this.isOffline && this.rooms.length === 0;
  }

  get showSkeleton() {
    return !this.loadedOnce && !this.isOffline;
  }

  get lastUpdatedLabel() {
    return this.meta?.update_time ? String(this.meta.update_time) : null;
  }

  get descriptionParams() {
    return {
      node: this.nodeName || "-",
      seconds: String(this.refreshSeconds),
    };
  }

  @action
  setFilter(value) {
    this.statusFilter = value;
  }

  @action
  onRefresh() {
    return this.controller?.refresh();
  }

  @action
  async copyAddress(room, event) {
    event?.preventDefault?.();
    event?.stopPropagation?.();

    if (!room?.address) {
      return;
    }

    try {
      if (navigator.clipboard?.writeText) {
        await navigator.clipboard.writeText(room.address);
      } else {
        this.#legacyCopy(room.address);
      }

      this.copiedRoomId = room.id;
      window.clearTimeout(this.#copyTimer);
      this.#copyTimer = window.setTimeout(() => (this.copiedRoomId = null), 1600);
    } catch {
      this.copiedRoomId = null;
    }
  }

  willDestroy() {
    window.clearTimeout(this.#copyTimer);
    super.willDestroy(...arguments);
  }

  #legacyCopy(text) {
    const input = document.createElement("textarea");
    input.value = text;
    input.setAttribute("readonly", "");
    input.style.position = "fixed";
    input.style.opacity = "0";
    document.body.appendChild(input);
    input.select();
    document.execCommand("copy");
    document.body.removeChild(input);
  }

  <template>
    <div class="relay-rooms">
      <header class="relay-rooms__header">
        <RelayRoomsIcon @name="server" @size="24" />

        <div class="relay-rooms__header-text">
          <h1 class="relay-rooms__title">{{i18n "relay_rooms.heading"}}</h1>
          <p class="relay-rooms__description">
            {{i18n
              "relay_rooms.description"
              node=this.descriptionParams.node
              seconds=this.descriptionParams.seconds
            }}
          </p>
        </div>
      </header>

      <div class="relay-rooms__toolbar">
        <div class="relay-rooms__filters" role="group" aria-label={{i18n "relay_rooms.heading"}}>
          {{#each this.filters as |filter|}}
            <button
              type="button"
              class={{filter.className}}
              aria-pressed={{filter.isActive}}
              {{on "click" (fn this.setFilter filter.value)}}
            >
              {{i18n filter.label}}
            </button>
          {{/each}}
        </div>

        <div class="relay-rooms__toolbar-right">
          {{#if this.lastUpdatedLabel}}
            <span class="relay-rooms__updated">
              {{i18n "relay_rooms.last_updated" time=this.lastUpdatedLabel}}
            </span>
          {{/if}}

          <button
            type="button"
            class="btn btn-small btn-default relay-rooms__refresh"
            disabled={{this.loading}}
            {{on "click" this.onRefresh}}
          >
            <RelayRoomsIcon @name="refresh" @size="14" />
            {{#if this.loading}}
              {{i18n "relay_rooms.actions.refreshing"}}
            {{else}}
              {{i18n "relay_rooms.actions.refresh"}}
            {{/if}}
          </button>
        </div>
      </div>

      {{#if this.isOffline}}
        <div class="relay-rooms__notice relay-rooms__notice--error" role="alert">
          <RelayRoomsIcon @name="alert" @size="18" />
          <div>
            <strong>{{i18n "relay_rooms.offline"}}</strong>
            <p>{{i18n "relay_rooms.offline_hint"}}</p>
          </div>
        </div>
      {{/if}}

      {{#if this.showSkeleton}}
        <div class="relay-rooms__notice">
          <RelayRoomsIcon @name="plug" @size="18" />
          <p>{{i18n "relay_rooms.loading"}}</p>
        </div>
      {{else if this.showEmpty}}
        <div class="relay-rooms__notice">
          <RelayRoomsIcon @name="map" @size="18" />
          <div>
            <strong>{{i18n "relay_rooms.empty"}}</strong>
            <p>{{i18n "relay_rooms.empty_hint"}}</p>
          </div>
        </div>
      {{else if this.filteredEmpty}}
        <div class="relay-rooms__notice">
          <p>{{i18n "relay_rooms.empty"}}</p>
        </div>
      {{/if}}

      {{#if this.visibleRooms.length}}
        <ul class="relay-rooms__list">
          {{#each this.visibleRooms as |room|}}
            <li class="relay-rooms__room relay-rooms__room--{{room.status}}">
              <div class="relay-rooms__room-main">
                <div class="relay-rooms__room-id">
                  <span class="relay-rooms__room-code">{{room.display_id}}</span>
                  <span class="relay-rooms__status {{room.statusClass}}">
                    {{i18n room.statusLabel}}
                  </span>
                </div>

                <div class="relay-rooms__room-host">
                  <RelayRoomsIcon @name="users" @size="14" />
                  <span>{{room.host_name}}</span>
                </div>
              </div>

              <div class="relay-rooms__room-details">
                <div class="relay-rooms__detail">
                  <RelayRoomsIcon @name="map" @size="14" />
                  <span class="relay-rooms__map-name" title={{room.map_name}}>
                    {{room.map_name}}
                  </span>
                  {{#if room.mapKindLabel}}
                    <span class="relay-rooms__badge relay-rooms__badge--muted">
                      {{i18n room.mapKindLabel}}
                    </span>
                  {{/if}}
                </div>

                <div class="relay-rooms__detail">
                  <RelayRoomsIcon @name="users" @size="14" />
                  <span>
                    {{i18n
                      "relay_rooms.players_count"
                      active=room.active_connection_size
                      total=room.player_size
                    }}
                  </span>
                </div>

                {{#if room.uptime_label}}
                  <div class="relay-rooms__detail relay-rooms__detail--muted">
                    {{i18n "relay_rooms.table.uptime"}} {{room.uptime_label}}
                  </div>
                {{/if}}

                {{#if room.badges.length}}
                  <div class="relay-rooms__badges">
                    {{#each room.badges as |badge|}}
                      <span class="relay-rooms__badge">{{i18n badge.label}}</span>
                    {{/each}}
                  </div>
                {{/if}}
              </div>

              <div class="relay-rooms__room-actions">
                {{#if room.isJoinable}}
                  <a
                    class="btn btn-small btn-primary relay-rooms__join"
                    href={{room.join_url}}
                    rel="noopener noreferrer"
                  >
                    <RelayRoomsIcon @name="exit" @size="14" />
                    {{i18n "relay_rooms.actions.join"}}
                  </a>
                {{/if}}

                {{#if room.address}}
                  <button
                    type="button"
                    class="btn btn-small btn-default"
                    title={{i18n "relay_rooms.actions.copy_address"}}
                    {{on "click" (fn this.copyAddress room)}}
                  >
                    {{#if (eq this.copiedRoomId room.id)}}
                      <RelayRoomsIcon @name="check" @size="14" />
                      {{i18n "relay_rooms.actions.copied"}}
                    {{else}}
                      <RelayRoomsIcon @name="copy" @size="14" />
                      {{i18n "relay_rooms.actions.copy"}}
                    {{/if}}
                  </button>
                {{/if}}
              </div>
            </li>
          {{/each}}
        </ul>
      {{/if}}
    </div>
  </template>
}
