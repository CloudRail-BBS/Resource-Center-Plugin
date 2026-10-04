// Mounts the plugin's extra admin tab.
//
// Object form with `resource: "admin.adminPlugins.show"` — that node EXISTS in
// core's route tree, so the map attaches. The function form targets the main-app
// tree, but core's `admin` namespace lives in a separate bundle
// (frontend/discourse/admin/routes/admin-route-map.js) with `resetNamespace: true`
// on every child, so a bare `this.route("admin", ...)` does not attach where the
// author expects.
//
// The route path must NOT be "settings" — core already claims
// `adminPlugins.show.settings` for the auto-generated settings page.
//
// Route names are prefixed with the plugin name because every plugin's admin
// tabs share one namespace; a bare `relay-rooms` could collide.
export default {
  resource: "admin.adminPlugins.show",
  path: "/plugins",
  map() {
    this.route("relay-rooms-status", { path: "relay-rooms" });
  },
};
