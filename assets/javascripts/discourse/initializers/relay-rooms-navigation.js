import { withPluginApi } from "discourse/lib/plugin-api";

const ROUTE = "relay-rooms";
const ICON = "plug";

// MUST NOT collide with the page's root CSS class.
//
// A nav item's `name` is emitted as a CSS class on its <li>
// (NavigationItem renders `<li class={{... this.content.name}}>`). If this
// plugin also styled `.relay-rooms` as its page container — the obvious naming
// choice — the nav entry would inherit the page rule, and `max-width: 1100px`
// plus the nav bar's flex row would make the <li> absorb all the free space and
// stretch the ENTIRE navigation bar. Nothing errors; it just looks broken, and
// the cause is two files apart. Hence the `-nav-link` suffix.
//
// `addCommunitySectionLink` also documents that `name` must be dasherized and
// lowercase, which this is.
const LINK_NAME = "relay-rooms-nav-link";

export default {
  name: "relay-rooms-navigation",

  initialize(container) {
    const siteSettings = container.lookup("service:site-settings");
    if (!siteSettings.relay_rooms_enabled) {
      return;
    }

    withPluginApi((api) => {
      const title = () =>
        // `i18n` is a global on the Discourse client.
        // eslint-disable-next-line no-undef
        i18n("relay_rooms.nav_label");

      // Feeds the sidebar's Community section.
      //
      // The second argument is `secondary`, and it is NOT cosmetic: it selects
      // "the main or secondary section in the 'More...' links drawer". Passing
      // true (the earlier behaviour here) filed the link away inside the "More…"
      // drawer, so the page looked like it had no navigation entry at all.
      // Omit it to land in the main list.
      api.addCommunitySectionLink({
        name: LINK_NAME,
        route: ROUTE,
        title: title(),
        text: title(),
        icon: ICON,
      });

      // Feeds the header nav bar. A forum renders whichever surface its
      // `navigation_menu` setting selects, so registering only one leaves the
      // page unreachable on half the forums — a nav-bar item is invisible under
      // the default `sidebar` menu, with no warning, and the sidebar's Community
      // section is only rendered for logged-in users.
      api.addNavigationBarItem({
        name: LINK_NAME,
        displayName: title(),
        href: "/relay-rooms",
      });
    });
  },
};
