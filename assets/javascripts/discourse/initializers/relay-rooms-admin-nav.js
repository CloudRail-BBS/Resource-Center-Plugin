import { withPluginApi } from "discourse/lib/plugin-api";

// Must equal the plugin's `# name:`, which equals the installed directory name.
//
// These lookups are keyed off the DIRECTORY, not the `# name:`: core serializes
// the admin plugin list via `AdminPluginSerializer#id`, which returns
// `object.directory_name`. Because the directory and `# name:` are both
// `resource-center-plugin`, the two cannot disagree — registering the nav under
// one and having the page look for the other was the failure mode to avoid.
//
// Lowercase is required, not cosmetic: core's stylesheet route constrains :name
// to /[-a-z0-9_]+/, so an uppercase directory loses its CSS entirely. See
// plugin.rb.
const PLUGIN_ID = "resource-center-plugin";

export default {
  name: "relay-rooms-admin-plugin-configuration-nav",

  initialize(container) {
    const currentUser = container.lookup("service:current-user");
    if (!currentUser?.admin) {
      return;
    }

    // Deliberately NOT gated on `relay_rooms_enabled`.
    //
    // Gating it here meant that while the plugin was disabled — the default
    // before this was changed — its admin tab did not appear either, so there
    // was no in-admin way to discover the setting that turns it on. The tab
    // should be reachable precisely when the plugin is off; the status page
    // already reports "disabled" and points at the setting.
    withPluginApi((api) => {
      api.setAdminPluginIcon(PLUGIN_ID, "plug");
      api.addAdminPluginConfigurationNav(PLUGIN_ID, [
        {
          label: "relay_rooms.admin.title",
          route: "adminPlugins.show.relay-rooms-status",
        },
      ]);
    });
  },
};
