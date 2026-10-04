import { ajax } from "discourse/lib/ajax";
import DiscourseRoute from "discourse/routes/discourse";

export default class RelayRoomsStatusRoute extends DiscourseRoute {
  model() {
    // NOT /admin/plugins/<id> — that collides with core's own route.
    return ajax("/relay-rooms/rooms.json").catch(() => null);
  }
}
