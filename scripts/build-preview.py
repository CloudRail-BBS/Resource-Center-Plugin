#!/usr/bin/env python3
"""Builds preview/index.html — a standalone visual reference for the page UI.

Two deliberate choices, both about not letting the preview drift from the thing
it previews:

1. The room data goes through the REAL decorator. `lib/relay-rooms.js` is loaded
   by node (with a two-line shim for its `@ember/template` import) and
   `decorateRooms()` is called on the sample payload. Re-implementing the
   decoration here would mean the preview could show a capacity meter that the
   plugin never renders.
2. The labels are read from the REAL locale file, `config/locales/client.zh_CN.yml`,
   rather than retyped.

The CSS is the compiled output of the real stylesheet (`npx sass
assets/stylesheets/relay-rooms.scss`), and the custom properties come from the
site's own compiled colour schemes, so light and dark are the real schemes rather
than approximations.

Usage:  python scripts/build-preview.py [--lang zh_CN]
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Output lives inside the plugin and is gitignored, so this works from a plain
# clone rather than assuming a particular workspace layout.
PREVIEW = ROOT / "preview"

# The SERIALIZED payload, not the raw relay response.
#
# `decorateRoom` runs on what the plugin's own /relay-rooms/rooms.json returns —
# snake_case fields like active_connection_size and player_size. The upstream
# relay API uses camelCase (activeConnectionSize, playerSize), so feeding it the
# raw response silently yields undefined for every capacity field and all the
# meters render empty. Capture the fixture once:
#
#   curl -H "Accept: application/json" \
#     https://<your-forum>/relay-rooms/rooms.json > preview/rooms.serialized.json
#
# Without it the script falls back to synthetic rooms so it still runs offline.
SAMPLE = PREVIEW / "rooms.serialized.json"


# --------------------------------------------------------------------------
# Real decorator, via node
# --------------------------------------------------------------------------
def decorate_with_real_module(rooms: list[dict]) -> list[dict]:
    """Runs lib/relay-rooms.js in node and returns decorateRooms(rooms).

    The module's single bare import (`htmlSafe` from `@ember/template`) is
    replaced with a passthrough so it can load outside Ember. Everything else —
    status normalisation, meter ratio, chip assembly — is the shipped code.
    """
    source = (ROOT / "assets/javascripts/discourse/lib/relay-rooms.js").read_text(
        encoding="utf-8"
    )

    shimmed = source.replace(
        'import { htmlSafe } from "@ember/template";',
        "const htmlSafe = (value) => value;",
    )

    if 'from "@ember/template"' in shimmed:
        raise SystemExit("relay-rooms.js import shape changed; update the shim")

    tmp_dir = ROOT / ".preview-tmp"
    tmp_dir.mkdir(exist_ok=True)
    module_path = tmp_dir / "relay-rooms.mjs"
    module_path.write_text(shimmed, encoding="utf-8")

    runner = tmp_dir / "run.mjs"
    runner.write_text(
        "import { decorateRooms } from './relay-rooms.mjs';\n"
        "const payload = JSON.parse(process.argv[2]);\n"
        "process.stdout.write(JSON.stringify(decorateRooms(payload)));\n",
        encoding="utf-8",
    )

    result = subprocess.run(
        ["node", str(runner), json.dumps(rooms)],
        capture_output=True,
        text=True,
        cwd=str(tmp_dir),
    )

    if result.returncode != 0:
        raise SystemExit(f"decorator run failed:\n{result.stderr}")

    return json.loads(result.stdout)


# --------------------------------------------------------------------------
# Real locale strings
# --------------------------------------------------------------------------
def load_labels(lang: str) -> dict:
    import yaml  # type: ignore

    data = yaml.safe_load((ROOT / "config/locales/client.zh_CN.yml").read_text(encoding="utf-8"))
    labels = data["zh_CN"]["js"]["relay_rooms"]

    if lang != "zh_CN":
        other = yaml.safe_load(
            (ROOT / "config/locales/client.en.yml").read_text(encoding="utf-8")
        )["en"]["js"]["relay_rooms"]
        labels = _merge(labels, other)

    return labels


def _merge(base: dict, override: dict) -> dict:
    out = dict(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(out.get(key), dict):
            out[key] = _merge(out[key], value)
        else:
            out[key] = value
    return out


def t(labels: dict, key: str, **params) -> str:
    node = labels
    for part in key.split("."):
        node = node[part]

    for name, value in params.items():
        node = node.replace(f"%{{{name}}}", str(value))
    return node


def esc(value) -> str:
    return (
        str(value)
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


# --------------------------------------------------------------------------
# Markup — mirrors relay-rooms-page.gjs
# --------------------------------------------------------------------------
ICON = {
    "server": "M3 2.5h10a1 1 0 0 1 1 1v3a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1v-3a1 1 0 0 1 1-1Zm0 6h10a1 1 0 0 1 1 1v3a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1v-3a1 1 0 0 1 1-1ZM4.75 5h.01M4.75 11h.01",
    "user": "M8 7.5a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5ZM3 13.5c0-2.21 2.24-4 5-4s5 1.79 5 4",
    "clock": "M8 1.75a6.25 6.25 0 1 0 0 12.5 6.25 6.25 0 0 0 0-12.5ZM8 4.5V8l2.4 1.6",
    "refresh": "M13.5 8a5.5 5.5 0 1 1-1.61-3.89M13.5 2.5v3.2h-3.2",
    "copy": "M5.5 5.5h6a1 1 0 0 1 1 1v6a1 1 0 0 1-1 1h-6a1 1 0 0 1-1-1v-6a1 1 0 0 1 1-1Zm-1 -1v-1.5a1 1 0 0 1 1-1h6a1 1 0 0 1 1 1v1.5",
    "check": "M3 8.5 6.2 11.7 13 4.5",
    "arrowRight": "M2.5 8h10.5M9.5 4.5 13 8l-3.5 3.5",
    "alert": "M8 2.5 14 13H2L8 2.5Zm0 4v3.2m0 1.8v.5",
    "map": "M1.5 3.5 6 2l4 1.5 4.5-1.5v10L10 13.5 6 12l-4.5 1.5v-10Zm4.5-1.5v10m4-8.5v10",
}


def icon(name: str, size: int = 16) -> str:
    stroke = 1 if size >= 22 else 1.4
    return (
        f'<svg class="relay-rooms__icon" width="{size}" height="{size}" viewBox="0 0 16 16"'
        f' fill="none" stroke="currentColor" stroke-width="{stroke}"'
        f' stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"'
        f' focusable="false"><path d="{ICON[name]}"/></svg>'
    )


def hero(labels: dict, meta: dict) -> str:
    return f"""
      <header class="relay-rooms__hero">
        <span class="relay-rooms__hero-mark">{icon("server", 20)}</span>
        <div class="relay-rooms__hero-text">
          <h1 class="relay-rooms__title">{esc(t(labels, "heading"))}</h1>
          <p class="relay-rooms__subtitle">{esc(t(labels, "description", node=meta.get("node_name") or "-", seconds=30))}</p>
        </div>
        <div class="relay-rooms__live">
          <span class="relay-rooms__pulse" aria-hidden="true"></span>
          <span class="relay-rooms__live-label">{esc(t(labels, "live"))}</span>
          <span class="relay-rooms__live-time">{esc(meta.get("update_time") or "")}</span>
        </div>
      </header>"""


def bar(labels: dict, counts: dict, active: str = "all", busy: bool = False) -> str:
    chips = []
    for value, label_key in (
        ("all", "filters.all"),
        ("battleroom", "status.battleroom"),
        ("ingame", "status.ingame"),
    ):
        count = counts.get(value, 0)
        classes = ["relay-rooms__chip"]
        if value == active:
            classes.append("is-active")
        if count == 0 and value != "all":
            classes.append("is-empty")

        chips.append(
            f'<button type="button" class="{" ".join(classes)}" aria-pressed="{"true" if value == active else "false"}">'
            f'<span class="relay-rooms__chip-text">{esc(t(labels, label_key))}</span>'
            f'<span class="relay-rooms__chip-count">{count}</span></button>'
        )

    refresh_label = t(labels, "actions.refreshing" if busy else "actions.refresh")
    disabled = " disabled" if busy else ""

    return f"""
      <div class="relay-rooms__bar">
        <div class="relay-rooms__chips" role="group" aria-label="{esc(t(labels, "filters.aria"))}">
          {"".join(chips)}
        </div>
        <button type="button" class="relay-rooms__refresh"{disabled}>
          <span class="relay-rooms__refresh-icon">{icon("refresh", 14)}</span>
          <span>{esc(refresh_label)}</span>
        </button>
      </div>"""


def room_row(labels: dict, room: dict, copied: bool = False) -> str:
    chips = "".join(
        f'<span class="relay-rooms__tag">{esc(t(labels, chip["label"].replace("relay_rooms.", "")))}</span>'
        for chip in room.get("chips", [])
    )

    map_kind = ""
    if room.get("mapKindLabel"):
        map_kind = f'<span class="relay-rooms__tag">{esc(t(labels, room["mapKindLabel"].replace("relay_rooms.", "")))}</span>'

    uptime = ""
    if room.get("uptime_label"):
        uptime = (
            f'<span class="relay-rooms__meta relay-rooms__meta--dim">{icon("clock", 13)}'
            f'<span>{esc(room["uptime_label"])}</span></span>'
        )

    flag = ""
    if room.get("capacityStateLabel"):
        flag = f'<span class="relay-rooms__flag">{esc(t(labels, room["capacityStateLabel"].replace("relay_rooms.", "")))}</span>'

    join = ""
    if room.get("isJoinable"):
        join = (
            f'<a class="btn btn-small btn-primary relay-rooms__join" href="{esc(room.get("join_url") or "#")}" rel="noopener noreferrer">'
            f'<span>{esc(t(labels, "actions.join"))}</span>{icon("arrowRight", 14)}</a>'
        )

    copy = ""
    if room.get("address"):
        copy = (
            f'<button type="button" class="relay-rooms__copy" aria-label="{esc(t(labels, "actions.copy_address"))}"'
            f' title="{esc(t(labels, "actions.copy_address"))}">'
            f'{icon("check" if copied else "copy", 15)}</button>'
        )

    return f"""
            <li class="relay-rooms__room relay-rooms__room--{room["status"]}">
              <div class="relay-rooms__identity">
                <span class="relay-rooms__code">{esc(room.get("display_id"))}</span>
                <span class="relay-rooms__status {room["statusClass"]}">
                  <span class="relay-rooms__dot" aria-hidden="true"></span>
                  {esc(t(labels, room["statusLabel"].replace("relay_rooms.", "")))}
                </span>
              </div>
              <div class="relay-rooms__context">
                <div class="relay-rooms__context-top">
                  <span class="relay-rooms__map" title="{esc(room.get("map_name"))}">{esc(room.get("map_name"))}</span>
                  {map_kind}{chips}
                </div>
                <div class="relay-rooms__context-bottom">
                  <span class="relay-rooms__meta">{icon("user", 13)}<span class="relay-rooms__host">{esc(room.get("host_name"))}</span></span>
                  {uptime}
                </div>
              </div>
              <div class="relay-rooms__capacity relay-rooms__capacity--{room["meterState"]}"
                   title="{esc(t(labels, "capacity", active=room.get("active_connection_size", 0), total=room.get("player_size", 0)))}">
                <span class="relay-rooms__meter" aria-hidden="true">
                  <span class="relay-rooms__meter-fill" style="{room["meterStyle"]}"></span>
                </span>
                <span class="relay-rooms__count"><b>{room.get("active_connection_size", 0)}</b><i>/</i>{room.get("player_size", 0)}</span>
                {flag}
              </div>
              <div class="relay-rooms__actions">{join}{copy}</div>
            </li>"""


def skeleton_row() -> str:
    return """
            <li class="relay-rooms__room relay-rooms__room--skeleton">
              <span class="relay-rooms__sk relay-rooms__sk--code"></span>
              <span class="relay-rooms__sk relay-rooms__sk--line"></span>
              <span class="relay-rooms__sk relay-rooms__sk--meter"></span>
              <span class="relay-rooms__sk relay-rooms__sk--btn"></span>
            </li>"""


def state_block(labels: dict, kind: str) -> str:
    if kind == "offline":
        return f"""
      <div class="relay-rooms__state relay-rooms__state--alert" role="alert">
        <span class="relay-rooms__state-mark">{icon("alert", 20)}</span>
        <div class="relay-rooms__state-text">
          <strong>{esc(t(labels, "offline"))}</strong>
          <p>{esc(t(labels, "offline_hint"))}</p>
        </div>
      </div>"""

    if kind == "empty":
        return f"""
      <div class="relay-rooms__state">
        <span class="relay-rooms__state-mark">{icon("map", 20)}</span>
        <div class="relay-rooms__state-text">
          <strong>{esc(t(labels, "empty"))}</strong>
          <p>{esc(t(labels, "empty_hint"))}</p>
        </div>
      </div>"""

    return f"""
      <div class="relay-rooms__state relay-rooms__state--compact">
        <div class="relay-rooms__state-text"><strong>{esc(t(labels, "empty"))}</strong></div>
      </div>"""


def page(labels: dict, meta: dict, counts: dict, body: str) -> str:
    return f"""<div class="relay-rooms">{hero(labels, meta)}{bar(labels, counts)}{body}
    </div>"""


def noscript_table(labels: dict, rooms: list[dict]) -> str:
    rows = "".join(
        f"""
          <tr>
            <td><a href="{esc(r.get("join_url") or "#")}">{esc(r.get("display_id"))}</a></td>
            <td>{esc(r.get("host_name"))}</td>
            <td>{esc(r.get("map_name"))}</td>
            <td>{r.get("active_connection_size", 0)} / {r.get("player_size", 0)}</td>
            <td>{esc(t(labels, r["statusLabel"].replace("relay_rooms.", "")))}</td>
          </tr>"""
        for r in rooms
    )

    return f"""
    <div class="relay-rooms-noscript">
      <table class="relay-rooms-noscript__table">
        <thead><tr>
          <th>{esc(t(labels, "table.room"))}</th><th>{esc(t(labels, "table.host"))}</th>
          <th>{esc(t(labels, "table.map"))}</th><th>{esc(t(labels, "table.players"))}</th>
          <th>{esc(t(labels, "table.status"))}</th>
        </tr></thead>
        <tbody>{rows}
        </tbody>
      </table>
    </div>"""


# --------------------------------------------------------------------------
def main() -> int:
    lang = "zh_CN"
    if "--lang" in sys.argv:
        lang = sys.argv[sys.argv.index("--lang") + 1]

    labels = load_labels(lang)

    payload = json.loads(SAMPLE.read_text(encoding="utf-8"))
    raw_rooms = payload["rooms"]
    meta = {
        "node_name": payload["meta"].get("node_name"),
        "update_time": payload["meta"].get("update_time"),
    }

    rooms = decorate_with_real_module(raw_rooms)

    # Append two synthetic rooms so the two extreme capacity states are visible;
    # the live sample happens to contain neither a full nor an empty room.
    # Same serialized shape as above, since that is what the decorator expects.
    rooms = rooms + decorate_with_real_module(
        [
            {
                "id": "demo-full",
                "display_id": "RKC900",
                "status": "ingame",
                "host_name": "满员示例房主",
                "map_name": "满员演示图 4P",
                "map_kind": "custom",
                "player_size": 4,
                "active_connection_size": 4,
                "is_mod": False,
                "is_public": True,
                "is_custom": False,
                "join_url": "http://www.cnkd.fun/RKC900",
                "uptime_label": "12m",
            },
            {
                "id": "demo-empty",
                "display_id": "RKC901",
                "status": "battleroom",
                "host_name": "空房示例房主",
                "map_name": "空房演示图 10P",
                "map_kind": "mod",
                "player_size": 10,
                "active_connection_size": 0,
                "is_mod": True,
                "is_public": True,
                "is_custom": False,
                "join_url": "http://www.cnkd.fun/RKC901",
                "uptime_label": "3m",
            },
        ]
    )

    counts = {
        "all": len(rooms),
        "battleroom": sum(1 for r in rooms if r["status"] == "battleroom"),
        "ingame": sum(1 for r in rooms if r["status"] == "ingame"),
    }

    rows = "".join(room_row(labels, r, copied=(i == 0)) for i, r in enumerate(rooms))

    sections = {
        "list": page(labels, meta, counts, f'\n      <ul class="relay-rooms__list">{rows}\n      </ul>'),
        "skeleton": page(
            labels,
            meta,
            {"all": 0, "battleroom": 0, "ingame": 0},
            '\n      <ul class="relay-rooms__list relay-rooms__list--skeleton" aria-hidden="true">'
            + skeleton_row() * 3
            + f'\n      </ul>\n      <p class="relay-rooms__loading">{esc(t(labels, "loading"))}</p>',
        ),
        "empty": page(labels, meta, {"all": 0, "battleroom": 0, "ingame": 0}, state_block(labels, "empty")),
        "filtered": page(labels, meta, counts, state_block(labels, "filtered"), ),
        "offline": page(labels, meta, {"all": 0, "battleroom": 0, "ingame": 0}, state_block(labels, "offline")),
    }

    css = (PREVIEW / "relay-rooms.css").read_text(encoding="utf-8")
    light = (PREVIEW / "theme-light.css").read_text(encoding="utf-8")
    dark = (PREVIEW / "theme-dark.css").read_text(encoding="utf-8")

    html = f"""<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>联机房 UI 预览 · Relay Rooms</title>
<style>
/* Real colour schemes, copied verbatim from the site's compiled CSS. */
{light}
[data-theme="dark"] {{
{dark}
}}
</style>
<style>
/* The plugin's real compiled stylesheet (npx sass assets/stylesheets/relay-rooms.scss). */
{css}
</style>
<style>
/* Preview chrome only — not part of the plugin. */
:root {{ --header-offset: 0px; }}
* {{ box-sizing: border-box; }}
body {{
  margin: 0;
  padding: 0;
  background: var(--secondary);
  color: var(--primary);
  font-family: var(--font-family, system-ui, -apple-system, "Segoe UI", "PingFang SC", "Microsoft YaHei", sans-serif);
  font-size: 15px;
  line-height: 1.45;
  -webkit-font-smoothing: antialiased;
}}
.pv-shell {{ max-width: 1180px; margin: 0 auto; padding: 1.5em 1.25em 4em; }}
.pv-head {{ margin-bottom: 1.5em; }}
.pv-head h1 {{ margin: 0 0 0.2em; font-size: 1.5em; }}
.pv-head p {{ margin: 0; color: var(--primary-medium); font-size: 0.9em; }}
.pv-controls {{ display: flex; flex-wrap: wrap; gap: 0.5em; margin: 1em 0 2em; }}
.pv-btn {{
  padding: 0.4em 0.9em; border: 1px solid var(--content-border-color);
  border-radius: 999px; background: var(--secondary); color: var(--primary-high);
  font: inherit; font-size: 0.85em; cursor: pointer;
}}
.pv-btn.is-on {{ border-color: var(--tertiary); background: var(--tertiary-very-low); color: var(--tertiary); }}
.pv-sec {{ margin-bottom: 2.5em; }}
.pv-sec > h2 {{
  margin: 0 0 0.15em; font-size: 1.05em; font-weight: 600;
  display: flex; align-items: center; gap: 0.5em;
}}
.pv-sec > h2 span {{ font-weight: 400; font-size: 0.82em; color: var(--primary-medium); }}
.pv-sec > .pv-note {{ margin: 0 0 0.9em; color: var(--primary-medium); font-size: 0.85em; }}
.pv-frame {{
  border: 1px dashed var(--content-border-color);
  border-radius: 12px; padding: 0 1em;
}}
.pv-mobile {{ width: 390px; max-width: 100%; }}
.pv-mobile .pv-frame {{ padding: 0 0.85em; }}
/* The real page is inside Discourse's main outlet, which supplies horizontal
   padding; stand in for it so the sticky bar behaves the same way. */
.pv-frame {{ background: var(--secondary); }}
</style>
</head>
<body data-theme="light">
<div class="pv-shell">
  <div class="pv-head">
    <h1>联机房 UI 预览</h1>
    <p>真实样式表 + 真实配色 + 真实装饰逻辑 + 真实文案。仅预览外壳是本文件自带的。</p>
  </div>

  <div class="pv-controls">
    <button class="pv-btn is-on" data-theme-set="light">浅色</button>
    <button class="pv-btn" data-theme-set="dark">深色</button>
    <button class="pv-btn" data-width-set="wide">宽屏</button>
    <button class="pv-btn" data-width-set="mobile">移动端 390px</button>
  </div>

  <section class="pv-sec" id="sec-list">
    <h2>房间列表 <span>主状态 · 容量条 · 加入/复制</span></h2>
    <p class="pv-note">真实数据，另加一个满员房与一个空房以覆盖两端状态。滚动时工具条会吸顶。</p>
    <div class="pv-frame">{sections["list"]}</div>
  </section>

  <section class="pv-sec" id="sec-skeleton">
    <h2>载入中 <span>骨架屏</span></h2>
    <p class="pv-note">与真实行同构，数据到达时不会跳版。</p>
    <div class="pv-frame">{sections["skeleton"]}</div>
  </section>

  <section class="pv-sec" id="sec-empty">
    <h2>没有房间 <span>空状态</span></h2>
    <div class="pv-frame">{sections["empty"]}</div>
  </section>

  <section class="pv-sec" id="sec-filtered">
    <h2>筛选后为空 <span>紧凑状态</span></h2>
    <div class="pv-frame">{sections["filtered"]}</div>
  </section>

  <section class="pv-sec" id="sec-offline">
    <h2>中继不可达 <span>告警状态</span></h2>
    <div class="pv-frame">{sections["offline"]}</div>
  </section>

  <section class="pv-sec" id="sec-noscript">
    <h2>无 JS / 爬虫视图 <span>noscript 表格</span></h2>
    <p class="pv-note">这是搜索引擎与关闭 JS 的访客看到的内容，样式同样更新过。</p>
    <div class="pv-frame">{noscript_table(labels, rooms)}</div>
  </section>
</div>

<script>
const root = document.body;
document.querySelectorAll("[data-theme-set]").forEach((btn) => {{
  btn.addEventListener("click", () => {{
    root.dataset.theme = btn.dataset.themeSet;
    document.querySelectorAll("[data-theme-set]").forEach((b) => b.classList.toggle("is-on", b === btn));
  }});
}});
document.querySelectorAll("[data-width-set]").forEach((btn) => {{
  btn.addEventListener("click", () => {{
    const mobile = btn.dataset.widthSet === "mobile";
    document.querySelectorAll(".pv-sec").forEach((sec) => sec.classList.toggle("pv-mobile", mobile));
    document.querySelectorAll("[data-width-set]").forEach((b) => b.classList.toggle("is-on", b === btn));
  }});
}});
</script>
</body>
</html>
"""

    (PREVIEW / "index.html").write_text(html, encoding="utf-8")

    print(f"wrote {PREVIEW / 'index.html'}")
    print(f"rooms: {len(rooms)}  (battleroom={counts['battleroom']}, ingame={counts['ingame']})")
    print("capacity states:", sorted({r["meterState"] for r in rooms}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
