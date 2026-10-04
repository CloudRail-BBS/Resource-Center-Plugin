import { withPluginApi } from "discourse/lib/plugin-api";
import { ajax } from "discourse/lib/ajax";
import { ROOMS_URL, decorateRooms, roomsToMarkdown } from "../lib/relay-rooms";

const SEL = ".d-editor-input";

function translation(key, params) {
  // eslint-disable-next-line no-undef
  return typeof i18n === "function" ? i18n(key, params) : key;
}

// Inserts text at the caret, keeping the composer's own undo history intact by
// going through `document.execCommand` rather than rewriting `value` — a direct
// assignment clears the redo stack and breaks the emoji/mention autocomplete
// state.
function insertAtCaret(composer, text) {
  const element = document.querySelector(SEL);
  if (!element) {
    composer.set("value", `${composer.value}\n${text}`);
    return;
  }

  element.focus();
  const supportsExecCommand = document.execCommand?.("insertText", false, text);
  if (!supportsExecCommand) {
    const { selectionStart = element.value.length, selectionEnd = selectionStart } = element;
    const next =
      element.value.slice(0, selectionStart) + text + element.value.slice(selectionEnd);
    element.value = next;
    element.selectionStart = element.selectionEnd = selectionStart + text.length;
    element.dispatchEvent(new Event("input", { bubbles: true }));
  }
}

export default {
  name: "relay-rooms-composer",

  initialize(container) {
    const siteSettings = container.lookup("service:site-settings");
    if (!siteSettings.relay_rooms_enabled) {
      return;
    }

    withPluginApi((api) => {
      api.addComposerToolbarPopupMenuOption({
        label: "relay_rooms.composer.label",
        icon: "plug",
        action: async (toolbarEvent) => {
          const composer = toolbarEvent?.composer;
          if (!composer) {
            return;
          }

          try {
            const payload = await ajax(ROOMS_URL);
            const rooms = decorateRooms(payload?.rooms);

            if (rooms.length === 0) {
              // eslint-disable-next-line no-undef
              api.container.lookup("service:toasts")?.error?.(
                translation("relay_rooms.composer.empty"),
              );
              return;
            }

            const markdown = roomsToMarkdown(rooms, {
              room: translation("relay_rooms.table.room"),
              host: translation("relay_rooms.table.host"),
              map: translation("relay_rooms.table.map"),
              players: translation("relay_rooms.table.players"),
              status: translation("relay_rooms.table.status"),
              address: translation("relay_rooms.actions.copy_address"),
              statuses: {
                battleroom: translation("relay_rooms.status.battleroom"),
                ingame: translation("relay_rooms.status.ingame"),
                closed: translation("relay_rooms.status.closed"),
                unknown: translation("relay_rooms.status.unknown"),
              },
            });

            insertAtCaret(composer, `\n${markdown}\n`);
            // eslint-disable-next-line no-undef
            api.container.lookup("service:toasts")?.success?.(
              translation("relay_rooms.composer.inserted"),
            );
          } catch {
            // eslint-disable-next-line no-undef
            api.container.lookup("service:toasts")?.error?.(
              translation("relay_rooms.composer.failed"),
            );
          }
        },
      });
    });
  },
};
