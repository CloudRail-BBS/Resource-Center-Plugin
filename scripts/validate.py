#!/usr/bin/env python3
"""Static checks for the relay rooms plugin.

The repo is named Resource-Center-Plugin; the plugin and its directory are
`resource-center-plugin`. Lowercase is required, not cosmetic -- see
check_plugin_name_charset for why an uppercase directory loses its stylesheet
entirely.

Every check here is one that has a silent failure mode in Discourse: the plugin
loads, nothing logs, and the feature just does not work. Everything is proven to
fail on a deliberately broken copy (see scripts/selftest.sh).

Run from the plugin root:  python scripts/validate.py
"""

from __future__ import annotations

import glob
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EXPECTED_NAME = "resource-center-plugin"

failures: list[str] = []
warnings: list[str] = []


def fail(message: str) -> None:
    failures.append(message)


def warn(message: str) -> None:
    warnings.append(message)


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def strip_ruby_comments(source: str) -> str:
    """Drop full-line comments.

    A comment *explaining* a hazard contains the very string a regex looks for,
    which produces a false pass — the same trap as a migration check whose regex
    is satisfied by a comment mentioning `ActiveRecord::Migration`.
    """
    return "\n".join(
        line for line in source.splitlines() if not line.strip().startswith("#")
    )


def strip_js_comments(source: str) -> str:
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    return "\n".join(
        line for line in source.splitlines() if not line.strip().startswith("//")
    )


# --------------------------------------------------------------------------
# 1. Plugin name must equal the directory name
# --------------------------------------------------------------------------
def check_plugin_name() -> None:
    plugin_rb = ROOT / "plugin.rb"
    if not plugin_rb.exists():
        fail("plugin.rb is missing")
        return

    source = plugin_rb.read_text(encoding="utf-8")
    name = None

    # Mirror Plugin::Metadata.parse: the header scan stops only at a
    # non-comment, NON-BLANK line.
    for line in source.splitlines():
        if line.strip() and not line.startswith("#"):
            break
        match = re.match(r"#\s*name:\s*(.+)", line)
        if match:
            name = match.group(1).strip()
            break

    if not name:
        fail("plugin.rb has no '# name:' metadata header")
        return

    if name != ROOT.name:
        fail(
            f"plugin name is '{name}', but the plugin directory is named "
            f"'{ROOT.name}' — pin the clone destination to '{name}'"
        )

    if name != EXPECTED_NAME:
        warn(f"plugin name is '{name}', expected '{EXPECTED_NAME}'")

    for field in ("about", "version", "authors", "url"):
        if not re.search(rf"^#\s*{field}:", source, re.M):
            fail(f"plugin.rb metadata is missing '# {field}:'")


# --------------------------------------------------------------------------
# 1b. The plugin name and directory must be lowercase
#
# This is the single highest-value check here, because the failure is invisible
# everywhere except the browser.
#
# Core's stylesheet route constrains the name to lowercase:
#
#     # config/routes.rb
#     get "stylesheets/:name" => "stylesheets#show",
#         constraints: { name: /[-a-z0-9_]+/, format: "css" }, format: true
#
# The <link> Discourse emits uses the plugin DIRECTORY name. With a directory
# named `Resource-Center-Plugin` the URL is
# /stylesheets/Resource-Center-Plugin_<digest>.css, the constraint does not match,
# the route never matches, and the request 404s.
#
# What makes it so hard to find is that everything else is correct: the compile
# succeeds, the stylesheet_cache row exists with the exact requested digest, the
# <link> is emitted, and every other plugin serves fine. The controller is simply
# never reached, so nothing logs and nothing in the app points at the name. The
# only symptom is a completely unstyled page -- default <ul> bullets and
# browser-default buttons -- and a console message about MIME type text/html.
# --------------------------------------------------------------------------
PLUGIN_NAME_CHARSET = re.compile(r"\A[-a-z0-9_]+\Z")


def check_plugin_name_charset() -> None:
    # The directory name is what ends up in the stylesheet URL.
    if not PLUGIN_NAME_CHARSET.match(ROOT.name):
        offenders = sorted({c for c in ROOT.name if not re.match(r"[-a-z0-9_]", c)})
        fail(
            f"the plugin directory is named '{ROOT.name}', which is not lowercase. "
            f"Offending characters: {', '.join(repr(c) for c in offenders)}. "
            "Discourse's stylesheet route constrains :name to /[-a-z0-9_]+/, so the "
            "<link> it emits for this plugin will never match a route and the "
            "stylesheet 404s — leaving the page unstyled while the compile, the "
            "cache row and every other plugin look perfectly healthy. Rename the "
            "directory (and '# name:') to lowercase."
        )

    # The `# name:` is compared against the directory by check_plugin_name, so a
    # lowercase directory already implies a lowercase name. Still worth checking
    # directly, since the two can be edited independently.
    plugin_rb = ROOT / "plugin.rb"
    if not plugin_rb.exists():
        return

    for line in plugin_rb.read_text(encoding="utf-8").splitlines():
        if line.strip() and not line.startswith("#"):
            break
        match = re.match(r"#\s*name:\s*(.+)", line)
        if match:
            name = match.group(1).strip()
            if not PLUGIN_NAME_CHARSET.match(name):
                fail(
                    f"plugin.rb '# name: {name}' is not lowercase; the directory "
                    "name (which becomes the stylesheet URL) must also be, or the "
                    "plugin's CSS 404s"
                )
            break


# --------------------------------------------------------------------------
# 2. Every require_relative target exists, and no app/ file is required
# --------------------------------------------------------------------------
def check_requires() -> None:
    source = read(ROOT / "plugin.rb")

    for target in re.findall(r'require_relative\s+"([^"]+)"', source):
        if target.startswith("app/"):
            fail(
                f"require_relative \"{target}\" — files under app/ are Zeitwerk-owned; "
                "requiring them raises Zeitwerk::NameError during boot"
            )
            continue

        if not (ROOT / f"{target}.rb").exists():
            fail(f"require_relative \"{target}\" points at a file that does not exist")


# --------------------------------------------------------------------------
# 3. Every registered asset exists
# --------------------------------------------------------------------------
def check_registered_assets() -> None:
    source = read(ROOT / "plugin.rb")

    for asset, target in re.findall(
        r'register_asset\s+"([^"]+)"(?:\s*,\s*:(\w+))?', source
    ):
        path = ROOT / "assets" / asset
        if not path.exists():
            fail(f"register_asset \"{asset}\" points at a missing file")
            continue

        # A component under assets/javascripts/ lives in the MAIN bundle, so its
        # styles cannot be admin-scoped — registering its stylesheet with :admin
        # would silently load nothing where the component renders.
        if target == "admin" and asset.startswith("stylesheets/"):
            if "admin" not in Path(asset).stem:
                warn(
                    f"register_asset \"{asset}\", :admin — confirm the components it "
                    "styles live under admin/assets/javascripts/"
                )

    # assets/javascripts/** is auto-bundled; register_asset on it is an error.
    js_registrations = re.findall(r'register_asset\s+"(javascripts/[^"]+)"', source)
    for js in js_registrations:
        fail(
            f"register_asset \"{js}\" — JS under assets/javascripts is automatically "
            "included; manual register_asset calls must be removed"
        )

    stylesheets = {
        p.name for p in (ROOT / "assets" / "stylesheets").glob("*.scss")
    }
    registered = {
        Path(a).name
        for a in re.findall(r'register_asset\s+"stylesheets/([^"]+)"', source)
    }
    for name in sorted(stylesheets - registered):
        warn(
            f"assets/stylesheets/{name} is never registered — an unregistered "
            "stylesheet silently does nothing"
        )


# --------------------------------------------------------------------------
# 4. Engine mount must use `draw` in config/routes.rb
# --------------------------------------------------------------------------
def check_engine_mount() -> None:
    routes = ROOT / "config" / "routes.rb"
    if not routes.exists():
        fail("config/routes.rb is missing — the page shell will 404 on direct visits")
        return

    body = strip_ruby_comments(read(routes))

    if "mount" not in body:
        fail("config/routes.rb does not mount the engine")

    if not re.search(r"mount\s+::RelayRooms::Engine\s*,\s*at:\s*\"(/relay-rooms)\"", body):
        fail('config/routes.rb must mount ::RelayRooms::Engine at: "/relay-rooms"')

    if not re.search(r"Discourse::Application\.routes\.draw", body):
        fail(
            "config/routes.rb must mount with Discourse::Application.routes.draw; "
            "`append` from after_initialize fails silently (route set already finalised)"
        )

    plugin_body = strip_ruby_comments(read(ROOT / "plugin.rb"))
    if re.search(r"routes\.(append|draw)", plugin_body):
        fail(
            "plugin.rb mounts routes — move the mount into config/routes.rb; "
            "a mount inside after_initialize 404s on every direct visit"
        )

    # The engine's own root route is required, or GET /relay-rooms matches the
    # application route but finds no action.
    if not re.search(r'get\s+"/"\s*=>\s*"pages#index"', body):
        fail('config/routes.rb is missing `get "/" => "pages#index"` in the engine')

    # The Engine must exist and set an engine_name.
    #
    # engine_name is `alias :engine_name :railtie_name` in railties, i.e. a
    # Rails-internal identifier: `mount` derives its default route name from it,
    # and it identifies the railtie inside Rails. A plugin name that is not a
    # conventional lowercase slug (uppercase, or containing characters that
    # cannot appear in a `def`) is therefore NOT safe to hand to engine_name —
    # `define_method` tolerates it, but any string-eval path would not. Require a
    # lowercase slug here and let PLUGIN_NAME stay whatever the directory is.
    engine_rb = ROOT / "lib" / "relay_rooms" / "engine.rb"
    if not engine_rb.exists():
        fail("lib/relay_rooms/engine.rb is missing — config/routes.rb references ::RelayRooms::Engine")
        return

    engine_body = strip_ruby_comments(read(engine_rb))

    if not re.search(r"<\s*::Rails::Engine", engine_body):
        fail("lib/relay_rooms/engine.rb does not subclass ::Rails::Engine")

    name_match = re.search(r"engine_name\s+(\"([^\"]+)\"|PLUGIN_NAME)", engine_body)
    if not name_match:
        fail(
            "lib/relay_rooms/engine.rb is missing `engine_name` — without it the "
            "railtie name defaults to the class name and the mounted route is unnamed"
        )
    else:
        literal = name_match.group(2)
        if literal is None:
            # `engine_name PLUGIN_NAME` — only safe when the plugin name is itself
            # a conventional slug.
            plugin_body = strip_ruby_comments(read(ROOT / "plugin.rb"))
            plugin_match = re.search(r'PLUGIN_NAME\s*=\s*"([^"]+)"', plugin_body)
            if plugin_match and not re.fullmatch(r"[a-z0-9_-]+", plugin_match.group(1)):
                fail(
                    f"engine_name PLUGIN_NAME with PLUGIN_NAME="
                    f'"{plugin_match.group(1)}" — engine_name aliases railtie_name, a '
                    "Rails-internal identifier used for route naming. Use an explicit "
                    'lowercase slug instead: engine_name "relay_rooms"'
                )
        elif not re.fullmatch(r"[a-z0-9_-]+", literal):
            fail(
                f'engine_name "{literal}" is not a conventional lowercase slug — '
                "engine_name aliases railtie_name and is used to derive route names"
            )

    # `config.autoload_paths << lib` (which the skeleton does) is only safe when
    # every lib file's name matches the constant it defines. Guard against the
    # combination rather than the individual pieces.
    if re.search(r"autoload_paths\s*<<.*[\"']lib[\"']", engine_body):
        for path in sorted((ROOT / "lib").rglob("*.rb")):
            leaf = path.stem
            camel = "".join(word.capitalize() for word in leaf.split("_"))
            if not re.search(rf"^\s*(class|module)\s+{camel}\b", read(path), re.M):
                fail(
                    f"engine.rb adds lib/ to autoload_paths, but lib/{path.name} does "
                    f"not define {camel} — Zeitwerk::NameError on eager load. Either "
                    "remove the autoload_paths line or rename the constant."
                )


# --------------------------------------------------------------------------
# 5. Route map form, and route/template file paths
# --------------------------------------------------------------------------
def check_route_map() -> None:
    route_map = ROOT / "assets" / "javascripts" / "discourse" / "relay-rooms-route-map.js"
    if not route_map.exists():
        fail("assets/javascripts/discourse/relay-rooms-route-map.js is missing")
        return

    body = strip_js_comments(read(route_map))

    # A top-level plugin route MUST export a function. The object form mounts
    # onto an existing tree node, and a plugin's own route name is never among
    # them — so it is dropped silently and the URL falls through to the 404
    # catch-all, with no console message, build warning or server log.
    if re.search(r"export\s+default\s+function", body):
        pass
    elif re.search(r"export\s+default\s*\{", body):
        fail(
            "relay-rooms-route-map.js uses the object form; a top-level plugin "
            "route must export a function (tree.extract(mapFn))"
        )
    else:
        fail("relay-rooms-route-map.js does not export a route map")

    files = {
        str(p.relative_to(ROOT / "assets" / "javascripts" / "discourse")).replace(
            os.sep, "/"
        )
        for p in (ROOT / "assets" / "javascripts" / "discourse").rglob("*")
        if p.is_file()
    }

    required = {
        "routes/relay-rooms/index.js",
        "controllers/relay-rooms/index.js",
        "templates/relay-rooms.gjs",
        "templates/relay-rooms/index.gjs",
    }
    for path in sorted(required):
        if path not in files:
            fail(f"missing {path} — the `relay-rooms.index` route cannot resolve")


# --------------------------------------------------------------------------
# 6. The parent template must render {{outlet}}
# --------------------------------------------------------------------------
def check_parent_outlet() -> None:
    parent = ROOT / "assets" / "javascripts" / "discourse" / "templates" / "relay-rooms.gjs"
    if not parent.exists():
        return

    body = strip_js_comments(read(parent))
    if "{{outlet}}" not in body:
        fail(
            "templates/relay-rooms.gjs does not render {{outlet}} — child routes "
            "have nowhere to render and the page is blank"
        )


# --------------------------------------------------------------------------
# 7. Nav item name must not collide with the page's root CSS class
# --------------------------------------------------------------------------
def check_nav_class_collision() -> None:
    initializer = (
        ROOT
        / "assets"
        / "javascripts"
        / "discourse"
        / "initializers"
        / "relay-rooms-navigation.js"
    )
    if not initializer.exists():
        warn("relay-rooms-navigation.js is missing; the page will be unreachable")
        return

    body = read(initializer)

    # Resolve simple constant indirection. The nav names are frequently declared
    # as `const LINK_NAME = "..."` and then referenced as `name: LINK_NAME`, so a
    # check that only greps `name: "..."` literals sees nothing and reports a
    # false OK — which is exactly how this check was wrong at first.
    constants = dict(re.findall(r'const\s+(\w+)\s*=\s*"([^"]+)"', body))

    nav_names: list[str] = []
    for value in re.findall(r"name:\s*(\"[^\"]+\"|\w+)", body):
        if value.startswith('"'):
            nav_names.append(value.strip('"'))
        else:
            nav_names.append(constants.get(value, value))

    if not nav_names or nav_names == ["value"]:
        fail("the navigation initializer registers no resolvable nav item name")
        return

    # A nav item's `name` is emitted as a CSS class on its <li>. If it equals the
    # page's root class, the nav entry inherits the page rule and (with
    # max-width / margin in that rule) stretches the entire navigation bar.
    page_root = "relay-rooms"
    for name in nav_names:
        if name == page_root:
            fail(
                f'nav item name "{name}" collides with the page root class '
                f'".{page_root}" — give the nav item its own namespace'
            )

    for registration in ("addCommunitySectionLink", "addNavigationBarItem"):
        if registration not in body:
            warn(
                f"the navigation initializer does not call {registration}; the page "
                "will be unreachable on forums using that navigation surface"
            )

    # apiInitializer("1.0", cb) is the old signature; the leading version string
    # is silently ignored.
    for path in (ROOT / "assets" / "javascripts").rglob("*.js"):
        if re.search(r'apiInitializer\(\s*"[\d.]+"', read(path)):
            warn(f'{path.name}: apiInitializer("1.0", …) is the legacy signature')


# --------------------------------------------------------------------------
# 7b. addCommunitySectionLink's second argument hides the link
#
# The signature is `addCommunitySectionLink(arg, secondary)`, documented as
# "Determines whether the section link should be added to the main or secondary
# section in the 'More...' links drawer." Passing true therefore files the link
# inside the "More…" drawer rather than the visible list.
#
# That is a silent failure: the registration succeeds, no warning is logged, and
# the only symptom is that the page appears to have no navigation entry at all —
# which reads like a routing or initializer bug and sends you looking in the
# wrong place. Omit the argument (or pass false) to land in the main list.
# --------------------------------------------------------------------------
def check_community_section_link_secondary() -> None:
    for path in sorted((ROOT / "assets" / "javascripts").rglob("*.js")):
        body = strip_js_comments(read(path))

        for match in re.finditer(r"addCommunitySectionLink\s*\(", body):
            # Walk the argument list to find whether a second top-level arg exists.
            depth = 1
            index = match.end()
            top_level_args = 1

            while index < len(body) and depth > 0:
                char = body[index]
                if char in "([{":
                    depth += 1
                elif char in ")]}":
                    depth -= 1
                elif char == "," and depth == 1:
                    top_level_args += 1
                index += 1

            if top_level_args < 2:
                continue

            tail = body[match.end() : index]
            # Everything after the first top-level comma is the `secondary` arg.
            depth = 1
            for position, char in enumerate(tail):
                if char in "([{":
                    depth += 1
                elif char in ")]}":
                    depth -= 1
                elif char == "," and depth == 1:
                    # Take the leading token of the second argument rather than
                    # comparing the whole tail: trailing commas and newlines make
                    # it "true,\n      )" instead of "true".
                    token = re.match(r"\s*([A-Za-z0-9_.]+)", tail[position + 1 :])
                    if token and token.group(1) == "true":
                        fail(
                            f"{path.name}: addCommunitySectionLink(..., true) files the "
                            "link inside the sidebar's \"More…\" drawer, so the page "
                            "looks like it has no navigation entry. Omit the argument "
                            "to place it in the main list."
                        )
                    break


# --------------------------------------------------------------------------
# 8. SCSS: no bare plugin-root rule, and balanced braces
# --------------------------------------------------------------------------
def check_stylesheets() -> None:
    root_class = "relay-rooms"

    for path in sorted((ROOT / "assets" / "stylesheets").glob("*.scss")):
        body = strip_js_comments(read(path))

        if body.count("{") != body.count("}"):
            fail(
                f"{path.name}: unbalanced braces ({body.count('{')} open vs "
                f"{body.count('}')} close) — a block that closes early silently "
                "moves later rules to top level and leaks them site-wide"
            )

        # The collision hazard is a rule targeting the bare root class that
        # carries LAYOUT properties. Such a rule is emitted on the nav item's
        # <li> (since a nav item's `name` becomes a CSS class there), and with
        # `max-width`/`margin` in it the <li> absorbs all the free space in the
        # nav bar's flex row and stretches the ENTIRE navigation bar.
        #
        # A bare `.relay-rooms { &__child { … } }` BEM block is safe and
        # necessary — qualifying the parent as `div.` would compile the children
        # to `div.relay-rooms__header` and silently stop matching. So the check
        # inspects the *declarations* of a bare root rule, not its existence.
        for match in re.finditer(r"^\.relay-rooms\s*\{", body, re.M):
            depth = 1
            declarations: list[str] = []

            for line in body[match.end() :].splitlines():
                stripped = line.strip()

                if depth == 1 and re.match(r"^&?[a-zA-Z_-]", stripped) and "{" in stripped:
                    # A nested selector at depth 1: stop collecting declarations.
                    break
                if depth == 1 and stripped and not stripped.startswith("}"):
                    declarations.append(stripped)

                depth += stripped.count("{") - stripped.count("}")
                if depth <= 0:
                    break

            joining = " ".join(declarations)
            for prop in ("max-width", "margin", "width", "flex", "display"):
                if re.search(rf"(^|[\s;]){prop}\s*:", joining):
                    fail(
                        f"{path.name}: bare `.relay-rooms` rule sets `{prop}:` — "
                        f"that property lands on a nav item's <li> and stretches the "
                        f"whole navigation bar. Move it to `div.relay-rooms`."
                    )
                    break

        # Every selector should be namespaced to avoid leaking site-wide.
        # Brace-depth aware: a naive line scan reports nested selectors
        # (`p`, `strong`, `td` inside a parent block) as top-level false
        # positives, and a check that cries wolf gets ignored.
        depth = 0
        for line in body.splitlines():
            stripped = line.strip()

            if not stripped or stripped.startswith(("/*", "*", "//")):
                continue

            opens = stripped.count("{")
            closes = stripped.count("}")

            if depth == 0 and opens and "{" in stripped:
                selector = stripped.split("{")[0].strip()
                if selector and not selector.startswith(
                    (".relay-rooms", "div.relay-rooms", "@", "//", "$")
                ):
                    warn(f"{path.name}: top-level selector `{selector}` is not scoped")

            depth += opens - closes
            if depth < 0:
                fail(f"{path.name}: brace depth went negative — check the nesting")
                depth = 0


# --------------------------------------------------------------------------
# 9. i18n: every key used from JS/GJS exists in the client locale files
# --------------------------------------------------------------------------
CLIENT_LOCALES = ["client.zh_CN.yml", "client.en.yml"]


def flatten(node: dict, prefix: str = "") -> set[str]:
    keys: set[str] = set()
    for key, value in node.items():
        full = f"{prefix}.{key}" if prefix else str(key)
        if isinstance(value, dict):
            keys |= flatten(value, full)
        else:
            keys.add(full)
    return keys


def load_yaml(path: Path):
    try:
        import yaml  # type: ignore
    except ImportError:
        return None

    with path.open(encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def check_i18n() -> None:
    locale_dir = ROOT / "config" / "locales"
    used: set[str] = set()

    search_roots = [
        ROOT / "assets" / "javascripts" / "discourse",
        ROOT / "admin" / "assets" / "javascripts" / "discourse",
    ]

    for base in search_roots:
        for path in base.rglob("*"):
            if path.suffix not in (".js", ".gjs"):
                continue
            body = read(path)
            # Static keys only — a template-literal key is invisible to a
            # grep-based check, which is exactly why keys are precomputed into
            # getters rather than built inline in templates.
            used |= set(re.findall(r'i18n\(\s*"([^"]+)"', body))
            used |= set(re.findall(r'i18n\s+"([^"]+)"', body))
            # @label="plugin.admin.save" on <DButton> is an i18n reference too.
            used |= set(re.findall(r'@label="([^"]+)"', body))

    # Keys built as data (statusLabel: `relay_rooms.status.${status}`) are
    # enumerated explicitly so the check can see them.
    used |= {
        "relay_rooms.status.battleroom",
        "relay_rooms.status.ingame",
        "relay_rooms.status.closed",
        "relay_rooms.status.unknown",
        "relay_rooms.badges.mod",
        "relay_rooms.badges.public",
        "relay_rooms.badges.custom",
        "relay_rooms.badges.full",
    }

    sets: dict[str, set[str]] = {}

    for name in CLIENT_LOCALES:
        path = locale_dir / name
        if not path.exists():
            fail(f"config/locales/{name} is missing")
            continue

        data = load_yaml(path)
        if data is None:
            warn("PyYAML is unavailable; skipping i18n key coverage")
            return

        locale = next(iter(data))
        # Client locale files are merged into the JS bundle, so their keys must
        # sit under `js:`. Miss the wrapper and every lookup renders as a raw key.
        if "js" not in data[locale]:
            fail(
                f"config/locales/{name} has no `js:` wrapper — client keys must be "
                "nested under js:, or every i18n() lookup fails"
            )
            continue

        sets[name] = flatten(data[locale]["js"])

    if not sets:
        return

    reference = sets.get(CLIENT_LOCALES[0], set())

    for name, keys in sets.items():
        missing = sorted(k for k in used if k not in keys)
        # Params-only entries (relative.minutes.one) are resolved by count, not
        # by a literal key, so they are not expected to be listed directly.
        if missing:
            fail(f"{name} is missing keys used in JS: {', '.join(missing)}")

    # Keep the key sets identical across locales; a missing key is invisible
    # until a user on that locale hits it.
    for name, keys in sets.items():
        if name == CLIENT_LOCALES[0]:
            continue
        diff = sorted(reference - keys)
        if diff:
            fail(f"{name} is missing keys present in {CLIENT_LOCALES[0]}: {', '.join(diff)}")


# --------------------------------------------------------------------------
# 10. Server locale files: every site setting needs a label
# --------------------------------------------------------------------------
def check_site_setting_labels() -> None:
    settings_path = ROOT / "config" / "settings.yml"
    data = load_yaml(settings_path)
    if data is None:
        warn("PyYAML is unavailable; skipping site setting label coverage")
        return

    names = set()
    for group in data.values():
        if isinstance(group, dict):
            names |= set(group.keys())

    for name in ("server_settings.zh_CN.yml", "server_settings.en.yml"):
        path = ROOT / "config" / "locales" / name
        if not path.exists():
            fail(f"config/locales/{name} is missing")
            continue

        locale_data = load_yaml(path)
        if locale_data is None:
            continue

        locale = next(iter(locale_data))
        # Server files have NO js: layer.
        labels = flatten(locale_data[locale].get("site_settings", {}))
        missing = sorted(n for n in names if n not in labels)
        if missing:
            fail(f"{name} has no label for: {', '.join(missing)}")


# --------------------------------------------------------------------------
# 11. Every core import path must resolve
# --------------------------------------------------------------------------
# Verified against a recursive listing of discourse/discourse@main. Paths in
# imports omit the `frontend/discourse/app/` prefix and the file extension.
KNOWN_CORE_IMPORTS = {
    "discourse/routes/discourse",
    "discourse/lib/ajax",
    "discourse/lib/plugin-api",
    "discourse/lib/show-modal",
    "discourse/ui-kit/d-button",
    "discourse/ui-kit/d-page-subheader",
    "discourse/ui-kit/helpers/d-icon",
    "discourse/truth-helpers",
}

# Modules that used to exist and now 404. A single unresolvable import replaces
# the ENTIRE plugin bundle with a `throw`, so these are hard failures.
BANNED_IMPORTS = {
    "discourse/components/d-button": "discourse/ui-kit/d-button",
    "discourse/components/d-modal": "discourse/ui-kit/d-modal",
    "discourse/components/date-picker": "discourse/ui-kit/d-date-picker",
    "discourse/components/d-page-subheader": "discourse/ui-kit/d-page-subheader",
    "discourse/helpers/d-icon": "discourse/ui-kit/helpers/d-icon",
}


def check_imports() -> None:
    core_tree = ROOT.parent / "core-tree.txt"
    tree: set[str] = set()
    if core_tree.exists():
        tree = set(read(core_tree).splitlines())

    for base in (
        ROOT / "assets" / "javascripts" / "discourse",
        ROOT / "admin" / "assets" / "javascripts" / "discourse",
    ):
        for path in base.rglob("*"):
            if path.suffix not in (".js", ".gjs"):
                continue

            body = read(path)

            for specifier in re.findall(r'from\s+"(discourse/[^"]+)"', body):
                if specifier in BANNED_IMPORTS:
                    fail(
                        f"{path.name}: `{specifier}` no longer exists in core — "
                        f"use `{BANNED_IMPORTS[specifier]}`"
                    )
                    continue

                if specifier in KNOWN_CORE_IMPORTS:
                    continue

                if tree and not resolve_core_import(specifier, tree):
                    fail(
                        f"{path.name}: `{specifier}` does not resolve in core — a "
                        "single unresolvable import replaces the whole bundle"
                    )

            # Relative imports must point at a real file.
            for specifier in re.findall(r'from\s+"(\.[^"]+)"', body):
                target = (path.parent / specifier).resolve()
                if not any(
                    target.with_suffix(suffix).exists()
                    for suffix in (".js", ".gjs", ".gts", "")
                ) and not target.is_dir():
                    fail(f"{path.name}: relative import `{specifier}` does not resolve")


def resolve_core_import(specifier: str, tree: set[str]) -> bool:
    suffix = specifier[len("discourse/") :]

    for prefix in ("frontend/discourse/app/", "frontend/discourse/"):
        for ext in (".js", ".gjs", ".gts", ".ts"):
            if f"{prefix}{suffix}{ext}" in tree:
                return True
        # A directory module (index.js)
        for ext in (".js", ".gjs", ".gts"):
            if f"{prefix}{suffix}/index{ext}" in tree:
                return True

    return False


# --------------------------------------------------------------------------
# 12. Templates must call {{outlet}} where required, and .gjs must be parseable
# --------------------------------------------------------------------------
def check_gjs_parse() -> None:
    checker = ROOT / "scripts" / "check-gjs.mjs"
    if not checker.exists():
        warn("scripts/check-gjs.mjs is missing; .gjs parse errors are not checked")
        return

    files = [
        str(p)
        for p in ROOT.rglob("*.gjs")
    ]
    if not files:
        return

    node = shutil_which("node")
    if not node:
        warn("node is unavailable; skipping .gjs parse check")
        return

    result = subprocess.run(
        [node, str(checker), *files],
        capture_output=True,
        text=True,
        cwd=str(ROOT),
    )
    if result.returncode != 0:
        for line in (result.stdout + result.stderr).splitlines():
            if line.startswith("FAIL"):
                fail(line)
        if result.returncode != 0 and "FAIL" not in result.stdout + result.stderr:
            fail(f"check-gjs.mjs exited {result.returncode}: {result.stderr.strip()}")


def shutil_which(name: str) -> str | None:
    import shutil

    return shutil.which(name)


# --------------------------------------------------------------------------
# 13. Serializer attributes must all resolve
# --------------------------------------------------------------------------
def check_serializer_attributes() -> None:
    path = ROOT / "app" / "serializers" / "relay_rooms" / "room_serializer.rb"
    if not path.exists():
        fail("app/serializers/relay_rooms/room_serializer.rb is missing")
        return

    body = strip_ruby_comments(read(path))
    body = "\n".join(line for line in body.splitlines() if not line.strip().startswith("#"))

    match = re.search(r"attributes\s+(.+?)\n\n", body, re.S)
    if not match:
        fail("room_serializer.rb: could not parse the attributes list")
        return

    declared = re.findall(r":(\w+)", match.group(1))

    # `send(key)` is used by ActiveModel::Serialization for every declared
    # attribute, so each must resolve to a method on the serializer.
    defined = set(re.findall(r"^\s*def\s+(\w+)", body, re.M))
    defined |= set(
        re.findall(r"^\s*(\w+)\s*=\s*", body, re.M)
    )

    unresolved = [attr for attr in declared if attr not in defined]
    if unresolved:
        fail(
            "room_serializer.rb declares attributes with no reader: "
            + ", ".join(unresolved)
            + " — every API endpoint serialising this class 500s at once"
        )


# --------------------------------------------------------------------------
# 14. No serialize_data on a singleton (double-wrapped root key)
# --------------------------------------------------------------------------
def check_serialize_data() -> None:
    for path in (ROOT / "app" / "controllers").rglob("*.rb"):
        body = strip_ruby_comments(read(path))

        for match in re.finditer(r"serialize_data\(\s*(\S+)", body):
            argument = match.group(1)
            # A collection-shaped argument (a relation, an array) emits a bare
            # array, for which AMS skips the root key. A bare local or ivar is a
            # singleton and gets double-wrapped.
            if re.fullmatch(r"@?[a-z_]+", argument) and not argument.endswith("s"):
                fail(
                    f"{path.name}: serialize_data({argument}) double-wraps the payload "
                    f"(root key). Use a root: false helper for singletons."
                )


# --------------------------------------------------------------------------
# 15. build_rooms: no per-row work that could N+1 or hammer the upstream
# --------------------------------------------------------------------------
def check_api_client() -> None:
    path = ROOT / "lib" / "relay_rooms" / "api_client.rb"
    if not path.exists():
        return

    body = read(path)
    # `Discourse.store.url_for` only exists on the S3 store; it raises
    # NoMethodError on local storage.
    if "Discourse.store.url_for" in body or "signed_url_for_path" in body:
        fail(
            "api_client.rb calls an S3-store-only method; it raises NoMethodError on "
            "forums using local file storage"
        )

    # A format gate on a page action turns Discourse's own JSON-accepting preload
    # XHRs into a 404 on a URL whose route matched perfectly.
    for path in (ROOT / "app" / "controllers").rglob("*.rb"):
        body = strip_ruby_comments(read(path))
        if re.search(r"request\.format\.html\?", body):
            fail(
                f"{path.name}: gate on request.format — Discourse issues JSON-accepting "
                "preload XHRs for page routes, so this 404s a matching URL. Use "
                "skip_before_action :check_xhr instead."
            )
        if "check_xhr" in body and "skip_before_action" not in body:
            warn(f"{path.name}: uses check_xhr without skipping it on the page action")


# --------------------------------------------------------------------------
# 16. PLUGIN_NAME must be defined before it is used
#
# `Plugin::Instance#activate!` runs `instance_eval File.read(path), path`, and
# nothing in core defines a PLUGIN_NAME constant (grep lib/plugin/instance.rb:
# zero hits). The official skeleton defines it explicitly. Undefined, every
# `requires_plugin PLUGIN_NAME` raises NameError — and because plugin.rb is
# evaluated from config/application.rb's body, i.e. BEFORE
# Rails.application.initialize!, that NameError is caught by
# Plugin.initialization_guard, which prints "You are unable to start Discourse
# due to errors in the plugin at <dir>" and calls `exit 1`. The `exit 1` then
# fails the later `rake db:migrate` step, so a missing constant surfaces as a
# migration error.
# --------------------------------------------------------------------------
def check_plugin_name_constant() -> None:
    plugin_rb = ROOT / "plugin.rb"
    if not plugin_rb.exists():
        return

    source = plugin_rb.read_text(encoding="utf-8")
    body = strip_ruby_comments(source)

    # Where is it defined, if at all?
    definition = re.search(
        r"module\s+::?(\w+)\s*\n(?:.*\n)*?\s*PLUGIN_NAME\s*=\s*\"([^\"]+)\"", body
    )

    users: list[tuple[str, str]] = []
    for path in list(ROOT.rglob("*.rb")):
        if "node_modules" in str(path) or path.name == "validate.py":
            continue
        if path == plugin_rb:
            continue
        text = strip_ruby_comments(read(path))
        if re.search(r"\bPLUGIN_NAME\b", text):
            users.append((str(path.relative_to(ROOT)), text))

    uses_it = bool(users) or re.search(r"\bPLUGIN_NAME\b", body)
    if not uses_it:
        return

    if not definition:
        fail(
            "PLUGIN_NAME is referenced but never defined. Core does not provide it; "
            "add `module ::YourPlugin; PLUGIN_NAME = \"your-plugin-name\"; end` at the "
            "top of plugin.rb. Undefined, this raises NameError during plugin "
            "activation, which aborts boot with \"You are unable to start Discourse\" "
            "and fails the later db:migrate step."
        )
        return

    namespace, value = definition.group(1), definition.group(2)

    if value != EXPECTED_NAME:
        fail(f"PLUGIN_NAME is \"{value}\" but the plugin name is \"{EXPECTED_NAME}\"")

    # Ordering only matters for files that READ PLUGIN_NAME at class-body
    # evaluation time (i.e. while plugin.rb is still being loaded). A file that
    # only uses it inside a method body resolves it at call time, long after
    # activation, so position is irrelevant there.
    define_at = body.find("PLUGIN_NAME = ")
    require_at = body.find('require_relative "lib/')

    readers = [
        relative
        for relative, text in users
        if re.search(r"^\s*(?:class|module)\s+\w+.*\n(?:.*\n)*?\s*\w*PLUGIN_NAME", text, re.M)
        or re.search(r"engine_name\s+PLUGIN_NAME", text)
    ]

    if readers and define_at != -1 and require_at != -1 and define_at > require_at:
        fail(
            "PLUGIN_NAME is defined AFTER the first require_relative, but "
            f"{', '.join(readers)} reads it during class-body evaluation — that "
            "raises NameError. Move the definition above the requires."
        )

    # A bare PLUGIN_NAME at plugin.rb's top level resolves against Object (the
    # file is a string eval), missing ::YourPlugin::PLUGIN_NAME.
    for line in strip_ruby_comments(source).splitlines():
        if re.search(r"\bPLUGIN_NAME\b", line) and "PLUGIN_NAME =" not in line:
            if not re.search(r"::|module\s|class\s", line):
                warn(
                    f'plugin.rb: bare PLUGIN_NAME in `{line.strip()}` — plugin.rb is a '
                    f"string eval whose cref is Object, so use ::{namespace}::PLUGIN_NAME"
                )

    for relative, text in users:
        # Inside `module ::YourPlugin`, a bare PLUGIN_NAME resolves correctly.
        if not re.search(rf"module\s+::?{namespace}\b", text):
            warn(f"{relative}: references PLUGIN_NAME outside module ::{namespace}")


# --------------------------------------------------------------------------
# 17. lib/ files must not subclass Zeitwerk-loaded app classes
#
# Plugin activation happens before the autoloader exists, so a lib/ file that is
# require_relative'd from plugin.rb cannot resolve ApplicationSerializer,
# ApplicationController, ActiveRecord::Base (app models), etc. That raises
# NameError during activation → boot abort + db:migrate failure.
#
# Such classes belong in app/, which Zeitwerk loads after boot. Every core plugin
# keeps serializers under app/serializers/ for exactly this reason.
# --------------------------------------------------------------------------
APP_LOADED_BASES = {
    "ApplicationSerializer",
    "ApplicationController",
    "ApplicationJob",
    "ActiveRecord::Base",
    "ActiveModel::Serializer",
    "Discourse::ApplicationController",
    "Admin::AdminController",
}


def check_lib_does_not_use_app_classes() -> None:
    lib_dir = ROOT / "lib"
    if not lib_dir.exists():
        return

    for path in sorted(lib_dir.rglob("*.rb")):
        body = strip_ruby_comments(read(path))

        for base in APP_LOADED_BASES:
            pattern = rf"class\s+\w+\s*<\s*(?:::)?{re.escape(base)}\b"
            if re.search(pattern, body):
                fail(
                    f"lib/{path.relative_to(lib_dir)} subclasses {base}. lib/ is "
                    "require_relative'd during plugin activation, which runs before "
                    "the autoloader exists, so this raises NameError and aborts boot. "
                    "Move the file to app/ (serializers → app/serializers/<ns>/)."
                )

        # Referencing any app constant at class-body time is the same hazard.
        if re.search(r"^\s*(class|module)\s+\w+.*<\s*(?:::)?Application\w+", body, re.M):
            fail(
                f"lib/{path.relative_to(lib_dir)} references an Application* class in "
                "its class body, which is not resolvable at plugin-activation time"
            )

    # The reverse rule: serializers must actually live under app/serializers.
    for path in sorted(ROOT.rglob("*.rb")):
        if "node_modules" in str(path):
            continue
        body = strip_ruby_comments(read(path))
        if re.search(r"class\s+\w*Serializer\s*<", body):
            # as_posix(): on Windows relative_to() yields backslashes, which would
            # never match a forward-slash prefix.
            relative = path.relative_to(ROOT).as_posix()
            if not relative.startswith("app/serializers/"):
                fail(
                    f"{relative} defines a serializer outside app/serializers/ — "
                    "it cannot resolve its base class during plugin activation"
                )


# --------------------------------------------------------------------------
# 18. lib/ filenames should match the constant they define
#
# lib/ is not autoloaded today, so a mismatch is harmless *until* someone adds
# `config.autoload_paths << lib` (which the official skeleton does). Then
# Zeitwerk expects path-derived constants and raises NameError on eager load.
# --------------------------------------------------------------------------
def check_lib_filename_constants() -> None:
    lib_dir = ROOT / "lib"
    if not lib_dir.exists():
        return

    for path in sorted(lib_dir.rglob("*.rb")):
        relative = path.relative_to(lib_dir)

        if not relative.parts:
            continue

        # lib/<ns>/<file>.rb → <Ns>::<CamelFile>
        parts = list(relative.with_suffix("").parts)
        expected = "::".join(
            "".join(word.capitalize() for word in part.split("_")) for part in parts
        )

        body = strip_ruby_comments(read(path))

        # Collect constants actually defined at module/class level.
        defined = set(re.findall(r"^\s*(?:class|module)\s+(\w+)", body, re.M))
        defined |= set(re.findall(r"^\s*([A-Z][A-Za-z0-9_]*)\s*=", body, re.M))

        leaf = parts[-1].split("_")
        leaf_camel = "".join(w.capitalize() for w in leaf)

        if leaf_camel not in defined:
            warn(
                f"lib/{relative} does not define {leaf_camel} (Zeitwerk would expect "
                f"{expected} if lib/ were ever added to autoload_paths)"
            )


# --------------------------------------------------------------------------
# 19. plugin.rb must survive Plugin::Metadata#parse_line
#
# This does not merely grep for a bare "#" — it replays the parser, because the
# hazard is any line for which `line[1..-1].split(":")` yields nothing:
#
#     attribute, *value = line[1..-1].split(":")
#     attribute = attribute.strip.gsub(/ /, "_").to_sym
#
# With no nil guard, `attribute` being nil raises
# "NoMethodError: undefined method 'strip' for nil".
#
# A bare "#" is the common case, but "#:" and "#::" do it too, and a grep for
# "#" would miss those. Plugin::Metadata.parse is called from
# Plugin::Instance.find_all — before ANY plugin is activated — so the whole boot
# aborts, and the backtrace points at lib/plugin/metadata.rb without naming a
# plugin, which makes it look like a core bug.
#
# Only plugin.rb is parsed this way (Plugin::Instance.parse_from_source does
# File.read on plugins/*/plugin.rb), so this is scoped to that one file. All three
# official plugins (discourse-solved, discourse-data-explorer, docker_manager)
# contain zero bare "#" lines, which is the convention.
# --------------------------------------------------------------------------
def ruby_split_colon(text: str) -> list[str]:
    """Ruby's String#split(":") drops trailing empty fields; Python's does not."""
    parts = text.split(":")
    while parts and parts[-1] == "":
        parts.pop()
    return parts


def check_metadata_parseable() -> None:
    plugin_rb = ROOT / "plugin.rb"
    if not plugin_rb.exists():
        return

    for number, raw in enumerate(plugin_rb.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()

        # parse_line returns false for the first non-comment, non-blank line,
        # which stops Plugin::Metadata.parse — later lines are never inspected.
        if line and not line.startswith("#"):
            break

        if not line:
            continue

        if not ruby_split_colon(line[1:]):
            fail(
                f'plugin.rb:{number} is "{line}", which makes '
                "Plugin::Metadata#parse_line call .strip on nil -> "
                '"NoMethodError: undefined method \'strip\' for nil". That runs '
                "before any plugin activates, so boot fails with a backtrace naming "
                "lib/plugin/metadata.rb and no plugin. Delete the line, or give it "
                "content (e.g. '# ---'). Note '#' alone is not the only trigger: "
                "'#:' does it too."
            )


# --------------------------------------------------------------------------
# 20. Every identifier used in a .gjs template must be in scope
#
# Strict-mode .gjs templates have NO implicit globals. Every helper and component
# is resolved from the module scope, and an unresolved one is a COMPILE error:
#
#   Attempted to resolve a component or helper in a strict mode template, but
#   that value was not in scope: i18n
#
# lib/plugin/js_compiler.rb turns that into
#   throw new Error("[PLUGIN x] Compile error: ...")
# as the plugin's ENTIRE JS bundle. So the route, every initializer and every
# component disappear together, while the server-rendered page keeps working —
# which makes it look like a routing or nav problem rather than a template one.
# That is exactly how `{{i18n ...}}` without an import broke this plugin.
#
# `i18n` is a named export of `discourse-i18n`; discourse-i18n assigns only
# `globalThis.I18n` (capital I), so there is no lowercase global to fall back on.
# `content-tag` (scripts/check-gjs.mjs) only validates SYNTAX, so it passes such
# a file happily — scope checking has to be done separately, which is this.
# --------------------------------------------------------------------------
TEMPLATE_KEYWORDS = {
    "if",
    "else",
    "unless",
    "each",
    "in",
    "outlet",
    "yield",
    "let",
    "as",
    "with",
    "has-block",
    "has-block-params",
    "component",
    "helper",
    "modifier",
    "mount",
    "array",
    "hash",
}


def extract_template_blocks(source: str) -> str:
    blocks = re.findall(r"<template>(.*?)</template>", source, re.S)
    return "\n".join(blocks)


def imported_names(source: str) -> set[str]:
    names: set[str] = set()

    for default in re.findall(r'import\s+([A-Za-z_$][\w$]*)\s+from\s*"', source):
        names.add(default)

    for group in re.findall(r'import\s*\{([^}]*)\}\s*from\s*"', source):
        for part in group.split(","):
            part = part.strip()
            if part:
                # `foo as bar` binds `bar`
                names.add(part.split(" as ")[-1].strip())

    return names


def check_gjs_template_scope() -> None:
    for path in sorted(ROOT.rglob("*.gjs")):
        if "node_modules" in str(path):
            continue

        source = read(path)
        template = extract_template_blocks(source)
        if not template:
            continue

        # Strip string literals so their contents are not mistaken for code.
        code = re.sub(r'"[^"]*"', '""', template)
        code = re.sub(r"'[^']*'", "''", code)

        available = imported_names(source)

        # Block params are in scope inside the template.
        for group in re.findall(r"as \|([^|]*)\|", code):
            available.update(name.strip() for name in group.split())

        used: set[str] = set()
        used |= set(re.findall(r"\{\{#?([a-zA-Z_][\w-]*)", code))  # {{x}} / {{#x}}
        used |= set(re.findall(r"\(([a-zA-Z_][\w-]*)", code))  # (x ...)
        used |= set(re.findall(r"<([A-Z][\w]*)", code))  # <X />

        unresolved = sorted(
            name
            for name in used
            if name not in TEMPLATE_KEYWORDS
            and name not in available
            and name != "this"
        )

        if unresolved:
            relative = path.relative_to(ROOT).as_posix()
            fail(
                f"{relative}: template uses {', '.join(unresolved)} with no import. "
                "Strict-mode .gjs templates have no implicit globals, so this is a "
                "compile error that replaces the plugin's ENTIRE JS bundle with a "
                '`throw new Error("[PLUGIN ...] Compile error: ...")` — the route, '
                "initializers and components all vanish at once while the "
                "server-rendered page still works. Import it, e.g. "
                '`import { i18n } from "discourse-i18n";`'
            )


# --------------------------------------------------------------------------
# 21. `i18n(` must come from an import, never from a global
#
# discourse-i18n assigns only `globalThis.I18n` (capital I). The lowercase `i18n`
# is a named export, so a bare `i18n(...)` in a .js file is a ReferenceError.
#
# The nastier variant is guarding it: `typeof i18n === "function" ? i18n(...) : key`
# turns a missing global into raw keys printed into the UI, which looks like a
# missing-translation bug rather than a missing import.
# --------------------------------------------------------------------------
def check_global_i18n_not_used() -> None:
    candidates = [
        path
        for path in list(ROOT.rglob("*.js")) + list(ROOT.rglob("*.gjs"))
        if "node_modules" not in str(path) and "scripts" not in path.parts
    ]

    for path in sorted(candidates):
        source = read(path)

        # `i18n(` as a call, not `I18n.t(` and not a property access.
        if not re.search(r"(?<![\w.$])i18n\s*\(", source):
            continue

        if re.search(r'import\s*\{[^}]*\bi18n\b[^}]*\}\s*from', source):
            continue
        if re.search(r'import\s+i18n\s+from', source):
            continue

        relative = path.relative_to(ROOT).as_posix()
        fail(
            f"{relative} calls i18n() without importing it. discourse-i18n assigns "
            "only `globalThis.I18n` (capital I), so there is no lowercase `i18n` "
            'global. Add `import { i18n } from "discourse-i18n";`. Do not guard the '
            'call with `typeof i18n === "function"` — that hides the failure and '
            "prints raw translation keys instead."
        )


# --------------------------------------------------------------------------
# 22. Derived room fields must actually be derived
#
# `decorateRoom` in lib/relay-rooms.js adds fields the API never sends —
# statusClass, statusLabel, chips, mapKindLabel, meterState, meterStyle,
# capacityStateLabel, isJoinable, address. The component reads them directly.
#
# If nothing calls the decorator, every one of those is `undefined`, and NONE of
# it throws: the status pill loses its colour and label, the capacity meter gets
# no width, and `{{#if room.isJoinable}}` is falsy so the Join and Copy buttons
# vanish. The page still renders, so it reads as a styling problem.
#
# This check derives the field list from the decorator itself rather than
# hardcoding it, so adding a derived field keeps the check honest.
# --------------------------------------------------------------------------
def decorator_derived_fields() -> set[str]:
    source = read(ROOT / "assets" / "javascripts" / "discourse" / "lib" / "relay-rooms.js")

    match = re.search(r"return \{\n(.*?)\n  \};", source, re.S)
    if not match:
        return set()

    body = match.group(1)
    fields = set(re.findall(r"^\s{4}([a-zA-Z_][\w]*):", body, re.M))
    fields |= set(re.findall(r"^\s{4}([a-zA-Z_][\w]*),$", body, re.M))
    return fields


def check_derived_fields_are_applied() -> None:
    derived = decorator_derived_fields()

    if not derived:
        warn("could not read derived fields from decorateRoom; check skipped")
        return

    js_root = ROOT / "assets" / "javascripts" / "discourse"

    # Which derived fields does any component/template actually read?
    used: dict[str, set[str]] = {}
    for path in sorted(js_root.rglob("*")):
        if path.suffix not in (".gjs", ".js") or "lib" in path.parts:
            continue
        body = read(path)
        for field in derived:
            if re.search(rf"\b\w+\.{re.escape(field)}\b", body):
                used.setdefault(field, set()).add(path.name)

    if not used:
        return

    readers = sorted({name for names in used.values() for name in names})

    # Check the ASSIGNMENT that feeds the page, not "is the decorator called
    # somewhere". A coarse check passes here for the wrong reason: the composer
    # toolbar button also calls decorateRooms (to build its Markdown table), so
    # "called anywhere" is satisfied even while the page's own controller hands
    # raw payload straight to the component.
    assignments: list[tuple[str, str]] = []
    for path in sorted((js_root / "controllers").rglob("*.js")):
        for match in re.finditer(r"this\.rooms\s*=\s*([^;]+);", read(path)):
            assignments.append((path.name, match.group(1).strip()))

    if not assignments:
        warn("no `this.rooms =` assignment found in controllers/; check skipped")
        return

    for name, rhs in assignments:
        if not re.search(r"\bdecorateRooms?\s*\(", rhs):
            fail(
                f"{name}: `this.rooms = {rhs}` does not go through decorateRooms(). The "
                f"component reads derived fields ({', '.join(sorted(used))}) that the API "
                "does not send, so all of them are undefined WITHOUT throwing: the status "
                "pill loses its colour and label, the capacity meter gets no width, and the "
                "Join/Copy buttons disappear because {{#if room.isJoinable}} is falsy. "
                f"Read in: {', '.join(readers)}."
            )


# --------------------------------------------------------------------------
# 24. Every registered stylesheet must actually compile
#
# Discourse compiles a plugin's stylesheet by generating an entrypoint of
# `prepended_scss` + `@import "<absolute path>"` and rendering it with
# SassC::Engine (sassc-embedded → dart-sass). For a PLUGIN target a Sass error is
# re-raised as Discourse::ScssError and fails the whole build; for a THEME it is
# swallowed into a comment. That asymmetry means a broken plugin stylesheet is
# loud — but only at build time, on the server.
#
# Checking it here costs one `sass` invocation and turns a failed rebuild into a
# local error. `npx sass` is used rather than a Ruby Sass binding so this works
# without a Discourse checkout; version drift is noted in the failure message.
#
# It also mirrors Discourse's `@import` entrypoint rather than compiling the file
# directly, because the two are not always equivalent.
# --------------------------------------------------------------------------
def check_scss_compiles() -> None:
    stylesheets = sorted((ROOT / "assets" / "stylesheets").glob("*.scss"))
    if not stylesheets:
        return

    sass = shutil_which("sass")
    use_npx = False
    if not sass:
        sass = shutil_which("npx")
        use_npx = True
    if not sass:
        warn("sass/npx not available; SCSS compile check skipped")
        return

    for path in stylesheets:
        # Everything goes in a real temp directory. Never pass a device path such
        # as /dev/null as sass's output: on Windows that creates a file literally
        # named `nul`, which is a reserved device name and then cannot be deleted,
        # renamed, or indexed by git — it breaks `git add -A` from that moment on.
        with tempfile.TemporaryDirectory() as tmp:
            entry = Path(tmp) / "_entrypoint.scss"
            out = Path(tmp) / "out.css"

            # Mirror Discourse: it compiles `prepended_scss + @import "<abs path>"`
            # rather than the file directly, and the two are not always equivalent.
            entry.write_text(f'@import "{path.name}";\n', encoding="utf-8")

            command = [sass]
            if use_npx:
                command.append("sass")
            command += [
                "--load-path",
                str(path.parent),
                "--style=compressed",
                "--no-source-map",
                str(entry),
                str(out),
            ]

            try:
                result = subprocess.run(command, capture_output=True, text=True, cwd=str(ROOT))
            except OSError as error:
                warn(f"could not run sass ({error}); SCSS compile check skipped")
                return

        # Sass prints deprecations on stderr but still exits 0; only a non-zero
        # exit is a real failure.
        if result.returncode != 0:
            detail = "\n".join(
                line
                for line in (result.stdout + result.stderr).splitlines()
                if "DEPRECATION" not in line and line.strip()
            )
            fail(
                f"assets/stylesheets/{path.name} fails to compile:\n{detail}\n"
                "Discourse renders plugin stylesheets through SassC::Engine and re-raises a "
                "Sass error as Discourse::ScssError for plugin targets, so this fails the "
                "whole rebuild. Check the installed sass version against the one Discourse "
                "ships (see sass-embedded in its Gemfile.lock)."
            )


# --------------------------------------------------------------------------
def main() -> int:
    checks = (
        check_plugin_name,
        check_plugin_name_charset,
        check_plugin_name_constant,
        check_metadata_parseable,
        check_requires,
        check_registered_assets,
        check_engine_mount,
        check_lib_does_not_use_app_classes,
        check_lib_filename_constants,
        check_route_map,
        check_parent_outlet,
        check_nav_class_collision,
        check_community_section_link_secondary,
        check_stylesheets,
        check_i18n,
        check_site_setting_labels,
        check_imports,
        check_gjs_parse,
        check_gjs_template_scope,
        check_global_i18n_not_used,
        check_derived_fields_are_applied,
        check_scss_compiles,
        check_serializer_attributes,
        check_serialize_data,
        check_api_client,
    )

    for check in checks:
        try:
            check()
        except Exception as error:  # noqa: BLE001 - a crashing check must not pass
            fail(f"{check.__name__} crashed: {error!r}")

    for message in warnings:
        print(f"WARN  {message}")

    if failures:
        for message in failures:
            print(f"FAIL  {message}")
        print(f"\n{len(failures)} failure(s), {len(warnings)} warning(s)")
        return 1

    print(f"OK    {len(checks)} checks passed, {len(warnings)} warning(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
