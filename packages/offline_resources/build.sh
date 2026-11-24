#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
src="$root/packages/offline_resources"
out="${1:-$root/build/offline-resources}"
mkdir -p "$out"
out="$(realpath "$out")"
sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:?Android SDK not configured}}"
bt="$(find "$sdk/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -1)"
platform="$sdk/platforms/android-35/android.jar"
test -f "$platform"
python3 "$src/prepare_assets.py" "$out/assets"
mkdir -p "$out/classes" "$out/dex"
javac -source 8 -target 8 -classpath "$platform" -d "$out/classes" "$src/PackActivity.java"
"$bt/d8" --min-api 23 --lib "$platform" --output "$out/dex" "$out/classes/com/github/stevessr/fluxdo/resources/PackActivity.class"
"$bt/aapt2" link -I "$platform" --manifest "$src/AndroidManifest.xml" --version-code "${GITHUB_RUN_NUMBER:-1}" -o "$out/unsigned.apk"
python3 - "$out" <<'PY'
from pathlib import Path
import sys, zipfile
root = Path(sys.argv[1])
with zipfile.ZipFile(root / "unsigned.apk", "a", compression=zipfile.ZIP_DEFLATED) as apk:
    apk.write(root / "dex/classes.dex", "classes.dex")
    for asset in sorted((root / "assets").rglob("*")):
        if asset.is_file():
            apk.write(asset, asset.relative_to(root).as_posix())
PY
"$bt/zipalign" -f 4 "$out/unsigned.apk" "$out/aligned.apk"
: "${PACK_KEYSTORE:?signing keystore required}" "${PACK_KEY_ALIAS:?signing alias required}" "${PACK_STORE_PASSWORD:?store password required}" "${PACK_KEY_PASSWORD:?key password required}"
export PACK_STORE_PASSWORD PACK_KEY_PASSWORD
apk="$out/fluxdo-offline-font-emoji.apk"
"$bt/apksigner" sign --ks "$PACK_KEYSTORE" --ks-key-alias "$PACK_KEY_ALIAS" --ks-pass env:PACK_STORE_PASSWORD --key-pass env:PACK_KEY_PASSWORD --out "$apk" "$out/aligned.apk"
"$bt/apksigner" verify --verbose "$apk"
"$bt/aapt" dump xmltree "$apk" AndroidManifest.xml > "$out/manifest.txt"
grep -Fq 'com.github.lingyan000.fluxdo.action.PLUGIN' "$out/manifest.txt"
! grep -Fq 'android.intent.category.LAUNCHER' "$out/manifest.txt"
python3 - "$apk" <<'PY'
import sys, zipfile
from PIL import Image
import io
with zipfile.ZipFile(sys.argv[1]) as z:
    names = z.namelist()
    assert len([n for n in names if n.startswith("assets/fonts/")]) == 5
    assert len([n for n in names if n.startswith("assets/emoji_fonts/")]) == 3
    assert "assets/emoji/noto_3d/grinning.png" in names
    with Image.open(io.BytesIO(z.read("assets/emoji/noto_animated/grinning.webp"))) as im:
        assert im.n_frames > 1
    assert "assets/pack.json" in names
PY
ls -lh "$apk"
