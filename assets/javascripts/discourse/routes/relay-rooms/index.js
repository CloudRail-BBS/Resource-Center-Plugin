import DiscourseRoute from "discourse/routes/discourse";
import { ajax } from "discourse/lib/ajax";
import { action } from "@ember/object";

const ROOMS_URL = "/relay-rooms/rooms.json";

export default class RelayRoomsIndexRoute extends DiscourseRoute {
  queryParams = {
    status: { refreshModel: false },
  };

  model() {
    return ajax(ROOMS_URL).catch(() => null);
  }

  setupController(controller, model) {
    super.setupController(controller, model);
    controller.startPolling();
  }

  @action
  willTransition() {
    this.controllerFor("relay-rooms.index")?.stopPolling();
    return true;
  }
}
