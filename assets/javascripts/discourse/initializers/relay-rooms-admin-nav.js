import { withPluginApi } from "discourse/lib/plugin-api";

// Must equal the plugin's `# name:`, which equals the installed directory name.
//
// These lookups are keyed off the DIRECTORY, not the `# name:`: core serializes
// the admin plugin list via `AdminPluginSerializer#id`, which returns
// `object.directory_name`. Because this repo's name, its directory and its
// `# name:` are all `Resource-Center-Plugin`, the two can no longer disagree —
// registering the nav under one and having the page look for the other was the
// failure mode to avoid.
const PLUGIN_ID = "Resource-Center-Plugin";

export default {
  name: "relay-rooms-admin-plugin-configuration-nav",

  initialize(container) {
    const currentUser = container.lookup("service:current-user");
    if (!currentUser?.admin) {
      return;
    }

    const siteSettings = container.lookup("service:site-settings");
    if (!siteSettings.relay_rooms_enabled) {
      return;
    }

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
