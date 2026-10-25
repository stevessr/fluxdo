#!/usr/bin/env python3
"""Generate the host allowlist, independent Gradle graph and version defaults."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from android_plugin_catalog import ROOT, SHARED_LIBRARIES, PluginCatalog, load_catalog

HOST_CATALOG = Path("android/app/src/main/kotlin/com/github/lingyan000/fluxdo/OptionalPluginCatalog.kt")


def quote(value: str) -> str:
    # JSON and Kotlin share these escapes; Kotlin additionally interpolates $.
    return json.dumps(value, ensure_ascii=False).replace("$", r"\$")


def generated_files(catalog: PluginCatalog) -> dict[Path, str]:
    kotlin = '''// Generated from android_modular/plugins.json. Do not edit by hand.
package com.github.lingyan000.fluxdo

import android.content.ComponentName

internal data class OptionalPluginSpec(
    val id: String,
    val name: String,
    val packageName: String,
    val serviceClass: String,
    val operations: Set<String>,
    val activityClass: String? = null,
) {
    val component get() = ComponentName(packageName, serviceClass)
}

internal object OptionalPluginCatalog {
    val specs: List<OptionalPluginSpec> = listOf(
'''
    for spec in catalog.native:
        kotlin += "        OptionalPluginSpec(\n"
        for field in (spec.id, spec.name, spec.package, spec.service):
            kotlin += f"            {quote(field)},\n"
        kotlin += "            setOf(" + ", ".join(quote(op) for op in spec.operations) + "),\n"
        if spec.activity:
            kotlin += f"            {quote(spec.activity)},\n"
        kotlin += "        ),\n"
    sticker = catalog.plugin("sticker")
    kotlin += "    )\n"
    kotlin += f"    const val STICKER_PACKAGE = {quote(sticker.package)}\n"
    kotlin += f"    const val STICKER_ACTIVITY = {quote(sticker.activity)}\n}}\n"

    # A separate Gradle root: neither Flutter's plugin loader nor :app is
    # evaluated. Projects still share their original source and signing files.
    settings = '''// Generated from android_modular/plugins.json. Do not edit by hand.
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
plugins {
    id("com.android.application") version "8.11.1" apply false
    id("com.android.library") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}
rootProject.name = "fluxdo-native-companions"
'''
    libraries = [lib for lib in SHARED_LIBRARIES if any(lib in p.libraries for p in catalog.native)]
    for module in libraries + [p.module for p in catalog.native]:
        settings += f'include(":{module}")\nproject(":{module}").projectDir = file("../{module}")\n'
    versions = "# Generated from android_modular/plugins.json. Do not edit by hand.\n"
    for spec in catalog.plugins:
        versions += f"{spec.id}.versionCode={spec.version_code}\n{spec.id}.versionName={spec.version_name}\n"
    return {
        HOST_CATALOG: kotlin,
        Path("android/native_plugins/settings.gradle.kts"): settings,
        Path("android/plugin-versions.properties"): versions,
    }


def synchronize(root: Path = ROOT, *, check: bool = False) -> None:
    files = generated_files(load_catalog(root / "android_modular/plugins.json"))
    stale = []
    for relative, content in files.items():
        path = root / relative
        if path.is_file() and path.read_text(encoding="utf-8") == content:
            continue
        if check:
            stale.append(str(relative))
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8")
    if stale:
        raise RuntimeError("Stale plugin catalog outputs; run generator: " + ", ".join(stale))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    synchronize(check=parser.parse_args().check)
