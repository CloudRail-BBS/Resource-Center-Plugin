// Top-level plugin route.
//
// NOTE: this must export a *function*, not an object. The object form
// (`{ resource: "...", map() {} }`) mounts onto an existing route-tree node,
// and core's tree only ever contains the nodes core itself created
// (discovery, user, admin, topic…). A plugin's own route name is never among
// them, so the object form is dropped silently — no error, no log line, just a
// 404 that falls through to the catch-all.
//
// Same shape as core's app-route-map.js and discourse-cakeday's /cakeday.
export default function () {
  this.route("relay-rooms", { path: "/relay-rooms" }, function () {
    this.route("index", { path: "/" });
  });
}
