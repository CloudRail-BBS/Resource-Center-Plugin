export const ROOMS_URL = "/relay-rooms/rooms.json";

// Room statuses arrive as "battleroom" / "ingame" / "closed". Anything else is
// folded into "unknown" so the template always has a translation to resolve.
export const KNOWN_STATUSES = ["battleroom", "ingame", "closed"];

export function normalizeStatus(raw) {
  const value = String(raw ?? "")
    .trim()
    .toLowerCase();

  if (KNOWN_STATUSES.includes(value)) {
    return value;
  }

  if (["battle_room", "battle", "lobby"].includes(value)) {
    return "battleroom";
  }

  if (["in_game", "playing", "started"].includes(value)) {
    return "ingame";
  }

  if (["close", "ended", "finished"].includes(value)) {
    return "closed";
  }

  return "unknown";
}

export function statusClass(status) {
  return `relay-rooms__status--${normalizeStatus(status)}`;
}

// The DNS name players type into the client, derived from the API-hosted value.
export function joinAddress(room) {
  const url = room?.join_url;
  if (!url) {
    return null;
  }

  return String(url).replace(/^[a-z]+:\/\//i, "").replace(/\/+$/, "");
}

export function playersLabel(room) {
  return { active: room?.active_connection_size ?? 0, total: room?.player_size ?? 0 };
}

// i18n keys are precomputed here so the template only ever needs `{{i18n key}}`
// with a static string — a template-literal key is invisible to the i18n
// coverage checker and easy to typo.
export function decorateRoom(room) {
  const status = normalizeStatus(room?.status);

  const badges = [];

  if (room?.is_mod) {
    badges.push({ key: "mod", label: "relay_rooms.badges.mod" });
  }
  if (room?.is_public) {
    badges.push({ key: "public", label: "relay_rooms.badges.public" });
  }
  if (room?.is_custom) {
    badges.push({ key: "custom", label: "relay_rooms.badges.custom" });
  }
  if (room?.is_full) {
    badges.push({ key: "full", label: "relay_rooms.badges.full" });
  }

  return {
    ...room,
    status,
    statusLabel: `relay_rooms.status.${status}`,
    statusClass: statusClass(status),
    address: joinAddress(room),
    badges,
    isJoinable: status !== "closed" && Boolean(room?.join_url),
    mapKindLabel:
      room?.map_kind === "mod"
        ? "relay_rooms.badges.mod"
        : room?.map_kind === "custom"
          ? "relay_rooms.badges.custom"
          : null,
  };
}

export function decorateRooms(rooms) {
  return Array.isArray(rooms) ? rooms.map(decorateRoom) : [];
}

// Builds the Markdown table inserted by the composer toolbar button.
export function roomsToMarkdown(rooms, labels) {
  const header = `| ${labels.room} | ${labels.host} | ${labels.map} | ${labels.players} | ${labels.status} | ${labels.address} |`;
  const divider = "| --- | --- | --- | --- | --- | --- |";

  const rows = rooms.map((room) => {
    const status = labels.statuses[room.status] ?? labels.statuses.unknown;
    const players = `${room.active_connection_size ?? 0} / ${room.player_size ?? 0}`;
    const address = room.address ? `[${room.address}](http://${room.address})` : "—";
    const host = escapeCell(room.host_name) || "—";
    const map = escapeCell(room.map_name) || "—";

    return `| ${escapeCell(room.display_id)} | ${host} | ${map} | ${players} | ${status} | ${address} |`;
  });

  return [header, divider, ...rows].join("\n");
}

function escapeCell(value) {
  return String(value ?? "")
    .replace(/\|/g, "\\|")
    .replace(/\n/g, " ")
    .trim();
}
