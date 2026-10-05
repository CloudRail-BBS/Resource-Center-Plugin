import Controller from "@ember/controller";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { decorateRooms } from "../../lib/relay-rooms";

const ROOMS_URL = "/relay-rooms/rooms.json";
const MIN_REFRESH_SECONDS = 5;

export default class RelayRoomsIndexController extends Controller {
  @service siteSettings;
  @service appEvents;

  @tracked rooms = [];
  @tracked meta = null;
  @tracked loading = false;
  @tracked loadedOnce = false;
  @tracked errorMessage = null;

  #timer = null;
  #visibilityHandler = null;
  #destroyed = false;

  get refreshSeconds() {
    const value = Number(this.siteSettings.relay_rooms_refresh_seconds) || 30;
    return Math.max(value, MIN_REFRESH_SECONDS);
  }

  get requestTimeoutMs() {
    const value = Number(this.siteSettings.relay_rooms_request_timeout_ms) || 10000;
    return Math.max(value, 2000);
  }

  get nodeName() {
    return this.meta?.node_name ?? "";
  }

  get hasRooms() {
    return this.rooms.length > 0;
  }

  get isOffline() {
    return Boolean(this.errorMessage) && !this.hasRooms;
  }

  init() {
    super.init(...arguments);

    this.#visibilityHandler = () => {
      if (document.hidden) {
        // Stop hammering the relay server while the tab is in the background.
        this.#clearTimer();
      } else {
        this.refresh();
        this.#scheduleNext();
      }
    };
  }

  setupController(_controller, model) {
    this.applyPayload(model);
  }

  startPolling() {
    this.#scheduleNext();
    document.addEventListener("visibilitychange", this.#visibilityHandler);
  }

  stopPolling() {
    this.#clearTimer();
    document.removeEventListener("visibilitychange", this.#visibilityHandler);
  }

  willDestroy() {
    this.#destroyed = true;
    this.stopPolling();
    super.willDestroy(...arguments);
  }

  applyPayload(payload) {
    if (!payload || typeof payload !== "object") {
      this.errorMessage = "relay_rooms.errors.generic";
      return;
    }

    // MUST go through decorateRooms. The component reads derived fields that the
    // API does not send — statusClass, statusLabel, chips, mapKindLabel,
    // meterState, meterStyle, capacityStateLabel, isJoinable, address. Assigning
    // payload.rooms directly leaves every one of them undefined, which does not
    // throw: the status pill renders uncoloured and without its label, the
    // capacity meter never gets a width, and both the Join and Copy buttons
    // disappear entirely because `{{#if room.isJoinable}}` is falsy.
    this.rooms = decorateRooms(payload.rooms);
    this.meta = payload.meta ?? null;
    this.errorMessage = null;
  }

  @action
  async refresh() {
    if (this.loading) {
      return;
    }

    this.loading = true;
    this.appEvents?.trigger("relay-rooms:refresh");

    try {
      const payload = await ajax(ROOMS_URL);
      this.applyPayload(payload);
    } catch (error) {
      // A 502 from our own endpoint means the relay node is unreachable; keep
      // showing the last good data instead of blanking the table.
      this.errorMessage = error?.jqXHR?.responseJSON?.errors?.[0]
        ? null
        : "relay_rooms.errors.generic";
      if (error?.jqXHR?.status === 502) {
        this.errorMessage = "relay_rooms.errors.generic";
      }
    } finally {
      this.loading = false;
      this.loadedOnce = true;
      if (this.#destroyed) {
        return;
      }
      this.#scheduleNext();
    }
  }

  #scheduleNext() {
    this.#clearTimer();

    if (document.hidden) {
      return;
    }

    this.#timer = window.setTimeout(() => {
      if (!this.#destroyed) {
        this.refresh();
      }
    }, this.refreshSeconds * 1000);
  }

  #clearTimer() {
    if (this.#timer) {
      window.clearTimeout(this.#timer);
      this.#timer = null;
    }
  }
}
