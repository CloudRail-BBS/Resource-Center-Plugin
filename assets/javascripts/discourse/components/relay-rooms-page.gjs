import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import RelayRoomsIcon from "./relay-rooms-icon";

// `i18n` MUST be imported. Strict-mode .gjs templates have no implicit globals:
// every helper and component is resolved from the module scope, and an
// unresolved one is a COMPILE error, not a runtime miss. The whole plugin bundle
// is then replaced by a single `throw`, so the route, the initializers and the
// components all vanish at once while the server-rendered page still works —
// which makes it look like a routing problem rather than a template one.
//
// Note `discourse-i18n` sets only `globalThis.I18n` (capital I). There is no
// lowercase `i18n` global, so this import is required in .js files too.
import { i18n } from "discourse-i18n";

// `eq` is not an auto-registered helper either: every template identifier must
// be in scope, and an unresolved helper is the same compile failure described
// above.
import { eq } from "discourse/truth-helpers";

// Status filters. Each entry precomputes its own i18n key so the template only
// ever calls {{i18n}} with a static string — a template-literal key is invisible
// to the i18n coverage checker and easy to typo.
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

  get lastUpdatedLabel() {
    return this.meta?.update_time ? String(this.meta.update_time) : null;
  }

  get descriptionParams() {
    return {
      node: this.nodeName || "-",
      seconds: String(this.refreshSeconds),
    };
  }

  // A count per filter turns the chips into information rather than just
  // controls: "等待中 2" answers "is there anything joinable?" without a click.
  // A count of 0 is still shown — that is a useful answer too — but the chip
  // dims so an empty tab does not compete for attention.
  get filters() {
    return FILTERS.map((filter) => {
      const count =
        filter.value === "all"
          ? this.rooms.length
          : this.rooms.filter((room) => room.status === filter.value).length;

      const isActive = filter.value === this.statusFilter;

      return {
        ...filter,
        count,
        isActive,
        isEmpty: count === 0 && filter.value !== "all",
        className: [
          "relay-rooms__chip",
          isActive && "is-active",
          count === 0 && filter.value !== "all" && "is-empty",
        ]
          .filter(Boolean)
          .join(" "),
      };
    });
  }

  get refreshLabel() {
    return this.loading
      ? "relay_rooms.actions.refreshing"
      : "relay_rooms.actions.refresh";
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

  // Three placeholder rows rather than a spinner: the list is the page, so
  // showing its shape makes the wait feel shorter than a centred spinner does.
  get skeletonRows() {
    return [1, 2, 3];
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
      <header class="relay-rooms__hero">
        <span class="relay-rooms__hero-mark">
          <RelayRoomsIcon @name="server" @size="20" />
        </span>

        <div class="relay-rooms__hero-text">
          <h1 class="relay-rooms__title">{{i18n "relay_rooms.heading"}}</h1>
          <p class="relay-rooms__subtitle">
            {{i18n
              "relay_rooms.description"
              node=this.descriptionParams.node
              seconds=this.descriptionParams.seconds
            }}
          </p>
        </div>

        <div class="relay-rooms__live">
          <span class="relay-rooms__pulse" aria-hidden="true"></span>
          <span class="relay-rooms__live-label">{{i18n "relay_rooms.live"}}</span>
          {{#if this.lastUpdatedLabel}}
            <span class="relay-rooms__live-time">{{this.lastUpdatedLabel}}</span>
          {{/if}}
        </div>
      </header>

      <div class="relay-rooms__bar">
        <div
          class="relay-rooms__chips"
          role="group"
          aria-label={{i18n "relay_rooms.filters.aria"}}
        >
          {{#each this.filters as |filter|}}
            <button
              type="button"
              class={{filter.className}}
              aria-pressed={{filter.isActive}}
              {{on "click" (fn this.setFilter filter.value)}}
            >
              <span class="relay-rooms__chip-text">{{i18n filter.label}}</span>
              <span class="relay-rooms__chip-count">{{filter.count}}</span>
            </button>
          {{/each}}
        </div>

        <button
          type="button"
          class="relay-rooms__refresh"
          disabled={{this.loading}}
          {{on "click" this.onRefresh}}
        >
          <span class="relay-rooms__refresh-icon">
            <RelayRoomsIcon @name="refresh" @size="14" />
          </span>
          <span>{{i18n this.refreshLabel}}</span>
        </button>
      </div>

      {{#if this.isOffline}}
        <div class="relay-rooms__state relay-rooms__state--alert" role="alert">
          <span class="relay-rooms__state-mark">
            <RelayRoomsIcon @name="alert" @size="20" />
          </span>
          <div class="relay-rooms__state-text">
            <strong>{{i18n "relay_rooms.offline"}}</strong>
            <p>{{i18n "relay_rooms.offline_hint"}}</p>
          </div>
        </div>
      {{/if}}

      {{#if this.showSkeleton}}
        <ul class="relay-rooms__list relay-rooms__list--skeleton" aria-hidden="true">
          {{#each this.skeletonRows as |row|}}
            <li class="relay-rooms__room relay-rooms__room--skeleton">
              <span class="relay-rooms__sk relay-rooms__sk--code"></span>
              <span class="relay-rooms__sk relay-rooms__sk--line"></span>
              <span class="relay-rooms__sk relay-rooms__sk--meter"></span>
              <span class="relay-rooms__sk relay-rooms__sk--btn"></span>
            </li>
          {{/each}}
        </ul>
        <p class="relay-rooms__loading">{{i18n "relay_rooms.loading"}}</p>
      {{else if this.showEmpty}}
        <div class="relay-rooms__state">
          <span class="relay-rooms__state-mark">
            <RelayRoomsIcon @name="map" @size="20" />
          </span>
          <div class="relay-rooms__state-text">
            <strong>{{i18n "relay_rooms.empty"}}</strong>
            <p>{{i18n "relay_rooms.empty_hint"}}</p>
          </div>
        </div>
      {{else if this.filteredEmpty}}
        <div class="relay-rooms__state relay-rooms__state--compact">
          <div class="relay-rooms__state-text">
            <strong>{{i18n "relay_rooms.empty"}}</strong>
          </div>
        </div>
      {{/if}}

      {{#if this.visibleRooms.length}}
        <ul class="relay-rooms__list">
          {{#each this.visibleRooms as |room|}}
            <li class="relay-rooms__room relay-rooms__room--{{room.status}}">
              <div class="relay-rooms__identity">
                <span class="relay-rooms__code">{{room.display_id}}</span>
                <span class="relay-rooms__status {{room.statusClass}}">
                  <span class="relay-rooms__dot" aria-hidden="true"></span>
                  {{i18n room.statusLabel}}
                </span>
              </div>

              <div class="relay-rooms__context">
                <div class="relay-rooms__context-top">
                  <span class="relay-rooms__map" title={{room.map_name}}>
                    {{room.map_name}}
                  </span>

                  {{#if room.mapKindLabel}}
                    <span class="relay-rooms__tag">{{i18n room.mapKindLabel}}</span>
                  {{/if}}

                  {{#each room.chips as |chip|}}
                    <span class="relay-rooms__tag">{{i18n chip.label}}</span>
                  {{/each}}
                </div>

                <div class="relay-rooms__context-bottom">
                  <span class="relay-rooms__meta">
                    <RelayRoomsIcon @name="user" @size="13" />
                    <span class="relay-rooms__host">{{room.host_name}}</span>
                  </span>

                  {{#if room.uptime_label}}
                    <span class="relay-rooms__meta relay-rooms__meta--dim">
                      <RelayRoomsIcon @name="clock" @size="13" />
                      <span>{{room.uptime_label}}</span>
                    </span>
                  {{/if}}
                </div>
              </div>

              <div
                class="relay-rooms__capacity relay-rooms__capacity--{{room.meterState}}"
                title={{i18n
                  "relay_rooms.capacity"
                  active=room.active_connection_size
                  total=room.player_size
                }}
              >
                <span class="relay-rooms__meter" aria-hidden="true">
                  <span
                    class="relay-rooms__meter-fill"
                    style={{room.meterStyle}}
                  ></span>
                </span>

                <span class="relay-rooms__count">
                  <b>{{room.active_connection_size}}</b><i>/</i>{{room.player_size}}
                </span>

                {{#if room.capacityStateLabel}}
                  <span class="relay-rooms__flag">{{i18n room.capacityStateLabel}}</span>
                {{/if}}
              </div>

              <div class="relay-rooms__actions">
                {{#if room.isJoinable}}
                  <a
                    class="btn btn-small btn-primary relay-rooms__join"
                    href={{room.join_url}}
                    rel="noopener noreferrer"
                  >
                    <span>{{i18n "relay_rooms.actions.join"}}</span>
                    <RelayRoomsIcon @name="arrowRight" @size="14" />
                  </a>
                {{/if}}

                {{#if room.address}}
                  <button
                    type="button"
                    class="relay-rooms__copy"
                    aria-label={{i18n "relay_rooms.actions.copy_address"}}
                    title={{i18n "relay_rooms.actions.copy_address"}}
                    {{on "click" (fn this.copyAddress room)}}
                  >
                    {{#if (eq this.copiedRoomId room.id)}}
                      <RelayRoomsIcon @name="check" @size="15" />
                    {{else}}
                      <RelayRoomsIcon @name="copy" @size="15" />
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
