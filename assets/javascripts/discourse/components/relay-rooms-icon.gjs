import Component from "@glimmer/component";

// Inline SVG icons, drawn locally on purpose.
//
// `discourse/helpers/d-icon` no longer exists in core (it moved to
// `discourse/ui-kit/helpers/d-icon`, which pins the plugin to a very recent
// Discourse). A local icon set has zero dependencies, works on any version, and
// `currentColor` makes the icons follow the active color scheme for free.
const PATHS = {
  users:
    "M5.5 7a2.25 2.25 0 1 0 0-4.5 2.25 2.25 0 0 0 0 4.5Zm5 0a2.25 2.25 0 1 0 0-4.5 2.25 2.25 0 0 0 0 4.5ZM1.5 13.25c0-1.876 1.79-3.4 4-3.4s4 1.524 4 3.4M10.5 9.85c2.21 0 4 1.524 4 3.4",
  map: "M1.5 3.5 6 2l4 1.5 4.5-1.5v10L10 13.5 6 12l-4.5 1.5v-10Zm4.5-1.5v10m4-8.5v10",
  refresh: "M13.5 8a5.5 5.5 0 1 1-1.61-3.89M13.5 2.5v3.2h-3.2",
  copy: "M5.5 5.5h6a1 1 0 0 1 1 1v6a1 1 0 0 1-1 1h-6a1 1 0 0 1-1-1v-6a1 1 0 0 1 1-1Zm-1 -1v-1.5a1 1 0 0 1 1-1h6a1 1 0 0 1 1 1v1.5",
  check: "M3 8.5 6.2 11.7 13 4.5",
  exit: "M6.5 3.5h-3a1 1 0 0 0-1 1v7a1 1 0 0 0 1 1h3M10 5.5 12.5 8 10 10.5M12.5 8h-6",
  plug: "M8 1.5v5M6 1.5v2.5M10 1.5v2.5M4.5 4h7v3.5a3.5 3.5 0 0 1-7 0V4ZM8 11v3.5",
  alert: "M8 2.5 14 13H2L8 2.5Zm0 4v3.2m0 1.8v.5",
  server:
    "M3 2.5h10a1 1 0 0 1 1 1v3a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1v-3a1 1 0 0 1 1-1Zm0 6h10a1 1 0 0 1 1 1v3a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1v-3a1 1 0 0 1 1-1ZM4.75 5h.01M4.75 11h.01",
};

export default class RelayRoomsIcon extends Component {
  get path() {
    return PATHS[this.args.name] ?? PATHS.alert;
  }

  get viewBox() {
    return this.args.viewBox ?? "0 0 16 16";
  }

  get size() {
    return this.args.size ?? 16;
  }

  // Thinner stroke at larger sizes, so a 24px icon does not look heavy.
  get strokeWidth() {
    return this.args.stroke ?? (this.size >= 22 ? 1 : 1.4);
  }

  <template>
    <svg
      class="relay-rooms__icon"
      width={{this.size}}
      height={{this.size}}
      viewBox={{this.viewBox}}
      fill="none"
      stroke="currentColor"
      stroke-width={{this.strokeWidth}}
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      <path d={{this.path}} />
    </svg>
  </template>
}
