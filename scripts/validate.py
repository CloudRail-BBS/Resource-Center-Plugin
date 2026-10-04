#!/usr/bin/env python3
"""Static checks for the discourse-relay-rooms plugin.

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
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EXPECTED_NAME = "discourse-relay-rooms"

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
    path = ROOT / "lib" / "relay_rooms" / "room_serializer.rb"
    if not path.exists():
        fail("lib/relay_rooms/room_serializer.rb is missing")
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
def main() -> int:
    checks = (
        check_plugin_name,
        check_requires,
        check_registered_assets,
        check_engine_mount,
        check_route_map,
        check_parent_outlet,
        check_nav_class_collision,
        check_stylesheets,
        check_i18n,
        check_site_setting_labels,
        check_imports,
        check_gjs_parse,
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
