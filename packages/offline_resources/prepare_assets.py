"""Build-time resource acquisition; the installed APK needs no network."""
import base64
import concurrent.futures
import hashlib
import io
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import urllib.request
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
DEST = Path(sys.argv[1]).resolve()
REV = "b805eda63e1768ea861ff2fe00cf30c2ce2c504b"
SETS = ("noto", "twemoji", "fluentui", "openmoji", "unicode", "noto_3d", "noto_animated")
FONT_SPECS = (
    ("googlefonts/noto-emoji", "99701e07d3d1fe1bdbcdb14964547f0fd592966f", "2D/fonts/Noto-COLRv1.ttf", "d1c82373d26e6949d81bbaefa4323f1e19f77262", 5038236),
    ("googlefonts/color-fonts", "e830e042b0e93fd5b0197a7fe9f0398f6d87f467", "fonts/twemoji-glyf_colr_1.ttf", "d59b98d3b39c64a0d55df7d481b334fac1c61e3b", 1301060),
    ("hfg-gmuend/openmoji", "5acb7f049c45c57a98449122d470de9f09bb6794", "font/OpenMoji-color-glyf_colr_0/OpenMoji-color-glyf_colr_0.ttf", "b8fe4366a31141c57fd6fcb7b8cd477a5b7b7102", 2759076),
)

def get(url, limit=100_000_000):
    for attempt in range(3):
        try:
            with urllib.request.urlopen(url, timeout=90) as response:
                data = response.read(limit + 1)
                if len(data) > limit:
                    raise ValueError("asset exceeds limit")
                return data
        except OSError:
            if attempt == 2:
                raise

def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)

def normal_font(entry):
    pkg = entry["package"]
    url = f"https://registry.npmjs.org/{pkg}/-/{pkg.split('/')[-1]}-{entry['version']}.tgz"
    data = get(url)
    assert len(data) == entry["tarball"]["size"]
    assert "sha512-" + base64.b64encode(hashlib.sha512(data).digest()).decode() == entry["tarball"]["integrity"]
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
        member = archive.extractfile("package/" + entry["file"])
        assert member is not None
        font = member.read()
        assert len(font) == entry["size"]
        assert hashlib.sha256(font).hexdigest() == entry["sha256"]
        write(DEST / "fonts" / (entry["sha256"] + ".ttf"), font)
        notices = [m for m in archive.getmembers() if m.isfile() and
                   re.search(r"licen[cs]e|copying|ofl|notice|readme|授权|许可", Path(m.name).name, re.I)
                   and m.size < 2_000_000]
        assert notices, f"missing package license notices: {pkg}"
        for n, notice in enumerate(notices):
            write(DEST / "licenses" / entry["id"] / (str(n) + "-" + Path(notice.name).name),
                  archive.extractfile(notice).read())

def emoji_font(spec):
    repo, rev, path, sha, size = spec
    data = get(f"https://raw.githubusercontent.com/{repo}/{rev}/{path}")
    assert len(data) == size
    assert hashlib.sha1(f"blob {size}\0".encode() + data).hexdigest() == sha
    write(DEST / "emoji_fonts" / (sha + ".ttf"), data)
    notice = {"googlefonts/noto-emoji": "2D/fonts/LICENSE", "googlefonts/color-fonts": "LICENSE", "hfg-gmuend/openmoji": "LICENSE.txt"}[repo]
    write(DEST / "licenses" / (sha + "-LICENSE.txt"), get(f"https://raw.githubusercontent.com/{repo}/{rev}/{notice}"))

def convert(source, target):
    with Image.open(source) as image:
        frames, durations = [], []
        for i in range(image.n_frames):
            image.seek(i)
            frame = image.convert("RGBA")
            frame.thumbnail((128, 128), Image.Resampling.LANCZOS)
            frames.append(frame)
            durations.append(max(20, round(image.info.get("duration", 40))))
        target.parent.mkdir(parents=True, exist_ok=True)
        frames[0].save(target, format="WEBP", save_all=True,
                       append_images=frames[1:], duration=durations, loop=0, quality=82, method=3)
        if len(frames) > 1:
            with Image.open(target) as result:
                assert result.n_frames > 1, f"animation lost: {source}"

def artwork(work):
    source = work / "dist" / "emoji"
    counts = {}
    for name in SETS:
        folder = source / name
        dest = DEST / "emoji" / name
        ext = ".avif" if name == "noto_animated" else ".png"
        if not folder.is_dir():
            raise RuntimeError(f"missing artwork set {name}")
        paths = sorted(folder.rglob("*" + ext))
        count = 0
        converted = {}
        for p in paths:
            rel = p.relative_to(folder)
            if not re.fullmatch(r"[a-z0-9_+\-]+(?:/[1-6])?\.(?:avif|png)", rel.as_posix()):
                continue
            actual = p.resolve(strict=True)
            if not actual.is_relative_to(source.resolve()):
                raise RuntimeError(f"unsafe artwork alias {p}")
            target = dest / rel.with_suffix(".webp" if ext == ".avif" else ".png")
            if actual.stat().st_size < 64:
                # Some generated aliases are Git symlinks, never package pointer text.
                raise RuntimeError(f"unresolved artwork alias {p}")
            if ext == ".avif":
                if actual in converted:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(converted[actual], target)
                else:
                    convert(actual, target)
                    converted[actual] = target
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(actual, target)
            count += 1
        if count < 100:
            raise RuntimeError(f"incomplete {name}: {count}")
        counts[name] = count
    write(DEST / "licenses" / "discourse-attributions.md", (work / "attributions.md").read_bytes())
    write(DEST / "licenses" / "discourse-readme.md", (work / "Readme.md").read_bytes())
    print("Artwork counts:", counts)
    return counts

def main():
    DEST.mkdir(parents=True, exist_ok=True)
    # A separately distributed resource APK must not rebundle MiSans, whose
    # license restricts standalone redistribution. Keep its existing app path.
    entries = [e for e in json.loads((ROOT / "assets/fonts/catalog.json").read_text())["fonts"]
               if e["license"] in {"OFL-1.1", "IPA-1.0"}]
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(normal_font, entries))
        list(pool.map(emoji_font, FONT_SPECS))
    work = DEST.parent / "discourse-source"
    subprocess.run(["git", "init", str(work)], check=True)
    subprocess.run(["git", "-C", str(work), "remote", "add", "origin", "https://github.com/discourse/discourse-emojis.git"], check=True)
    subprocess.run(["git", "-C", str(work), "fetch", "--depth=1", "origin", REV], check=True)
    subprocess.run(["git", "-C", str(work), "checkout", "--detach", "FETCH_HEAD"], check=True)
    counts = artwork(work)
    write(DEST / "licenses" / "source-notices.md", (ROOT / "docs/emoji-render-styles.md").read_bytes())
    write(DEST / "pack.json", json.dumps({"api": 1, "artwork_revision": REV, "counts": counts}, sort_keys=True).encode())

if __name__ == "__main__":
    main()
