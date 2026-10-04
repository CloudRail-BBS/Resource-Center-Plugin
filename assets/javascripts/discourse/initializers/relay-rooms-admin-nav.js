import { withPluginApi } from "discourse/lib/plugin-api";

// Must equal the plugin name (its `# name:`), i.e. the installed directory name.
const PLUGIN_ID = "discourse-relay-rooms";

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
