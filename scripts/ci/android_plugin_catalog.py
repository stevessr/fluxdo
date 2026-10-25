"""Validated source of truth for independently versioned Android companions.

This is a build-time allowlist, never an untrusted remote plugin discovery feed.
It intentionally cannot add host or third-party Gradle projects as dependencies.
"""
from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "android_modular/plugins.json"
HOST_PACKAGE = "com.github.lingyan000.fluxdo"
SHARED_LIBRARIES = ("plugin_api", "plugin_web_session")


@dataclass(frozen=True)
class PluginSpec:
    id: str
    name: str
    kind: str
    package: str
    module: str | None
    service: str | None
    activity: str | None
    operations: tuple[str, ...]
    libraries: tuple[str, ...]
    version_code: int
    version_name: str


@dataclass(frozen=True)
class PluginCatalog:
    protocol: int
    plugins: tuple[PluginSpec, ...]

    @property
    def native(self) -> tuple[PluginSpec, ...]:
        return tuple(p for p in self.plugins if p.kind == "native")

    def plugin(self, plugin_id: str) -> PluginSpec:
        for spec in self.plugins:
            if spec.id == plugin_id:
                return spec
        raise ValueError(f"Unknown Android plugin: {plugin_id}")


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def _unique_object(pairs: list[tuple[str, object]]) -> dict:
    result: dict = {}
    for key, value in pairs:
        _require(key not in result, f"Duplicate catalog key: {key}")
        result[key] = value
    return result


def load_catalog(path: Path = CATALOG) -> PluginCatalog:
    data = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=_unique_object)
    _require(isinstance(data, dict), "Catalog must be an object")
    _require(set(data) == {"schemaVersion", "protocolVersion", "hostPackage", "plugins"},
             "Unknown or missing catalog fields")
    _require(type(data["schemaVersion"]) is int and data["schemaVersion"] == 1,
             "Unsupported catalog schema")
    _require(type(data["protocolVersion"]) is int and data["protocolVersion"] == 1,
             "Unsupported plugin wire protocol")
    _require(data["hostPackage"] == HOST_PACKAGE, "Host identity cannot change")
    _require(isinstance(data["plugins"], list) and bool(data["plugins"]),
             "Expected nonempty plugin list")
    seen: set[str] = set()
    plugins = []
    required = {"id", "name", "kind", "package", "operations", "libraries", "versionCode", "versionName"}
    for item in data["plugins"]:
        _require(isinstance(item, dict) and required <= item.keys() and
                 item.keys() <= required | {"module", "service", "activity"},
                 "Unknown or missing plugin fields")
        plugin_id = item["id"]
        _require(isinstance(plugin_id, str) and re.fullmatch(r"[a-z][a-z0-9_]*", plugin_id) is not None,
                 "Invalid plugin ID")
        _require(plugin_id not in seen, f"Duplicate plugin ID: {plugin_id}")
        seen.add(plugin_id)
        _require(isinstance(item["name"], str) and 0 < len(item["name"]) <= 80 and
                 all(ord(c) >= 32 for c in item["name"]), "Invalid plugin name")
        package = HOST_PACKAGE + ".plugin." + plugin_id
        _require(item["package"] == package, f"Unexpected package for {plugin_id}")
        kind = item["kind"]
        _require(kind in ("native", "flutter"), "Unknown companion kind")
        for key in ("operations", "libraries"):
            value = item[key]
            _require(isinstance(value, list) and all(isinstance(x, str) for x in value),
                     f"{plugin_id}: expected {key} list")
            _require(len(set(value)) == len(value), f"{plugin_id}: duplicate {key}")
        _require(all(re.fullmatch(r"[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*", op)
                     for op in item["operations"]), "Invalid operation name")
        _require(set(item["libraries"]) <= set(SHARED_LIBRARIES),
                 f"{plugin_id}: host or unknown Gradle dependency")
        for key in ("service", "activity"):
            if key in item:
                _require(isinstance(item[key], str) and
                         re.fullmatch(re.escape(package) + r"\.[A-Z][A-Za-z0-9_]*", item[key]) is not None,
                         f"{plugin_id}: component escapes package")
        if kind == "native":
            _require(item.get("module") == "plugin_" + plugin_id,
                     f"{plugin_id}: invalid native module")
            _require(item["module"] not in SHARED_LIBRARIES,
                     f"{plugin_id}: application collides with shared library")
            _require("service" in item and bool(item["operations"]) and "plugin_api" in item["libraries"],
                     f"{plugin_id}: native IPC contract missing")
        else:
            _require(plugin_id == "sticker" and "activity" in item and
                     "module" not in item and "service" not in item and
                     not item["libraries"] and not item["operations"],
                     "Unsupported Flutter companion contract")
        version = item["versionCode"]
        _require(type(version) is int and 1 <= version < 2100000000, "Invalid Android versionCode")
        _require(isinstance(item["versionName"], str) and
                 re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.+_-]{0,79}", item["versionName"]) is not None,
                 "Invalid Android versionName")
        plugins.append(PluginSpec(
            plugin_id, item["name"], kind, package, item.get("module"),
            item.get("service"), item.get("activity"), tuple(item["operations"]),
            tuple(item["libraries"]), version, item["versionName"],
        ))
    _require(any(p.kind == "native" for p in plugins), "No native companions")
    _require("sticker" in seen, "Missing standalone Sticker companion")
    return PluginCatalog(data["protocolVersion"], tuple(plugins))
