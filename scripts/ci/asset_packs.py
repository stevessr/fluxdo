#!/usr/bin/env python3
"""独立、确定性、可校验的 Fluxdo 静态资源包构建器（仅标准库）。"""
import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import sys
import zipfile

PACKS = {
    "font-misans": ("assets/fonts/MiSansVF.ttf", False),
    "render-cook": ("assets/cook/discourse-cook.js", False),
    "render-polyfill": ("assets/polyfill/compat-polyfill.js", False),
    "ai-brands": ("assets/ai_brands", False),
    "avatar-touhou": ("assets/images/avater/touhou", False),
    "avatar-blue-archive": ("assets/images/avater/blue_archive", False),
    "avatar-witch-judgment": ("assets/images/avater/witch_judgment", False),
    "avatar-llm": ("assets/images/avater/llm", True),
    "avatar-stevessr": ("assets/images/avater/stevessr", True),
}
EXTENSIONS = {".ttf", ".js", ".svg", ".webp", ".png", ".json", ".md"}
MAX_FILE = 128 * 1024 * 1024
MAX_PACK = 512 * 1024 * 1024
STAMP = (1980, 1, 1, 0, 0, 0)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def json_bytes(value):
    return (json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n").encode()


def safe_path(name):
    return (
        isinstance(name, str) and bool(name) and
        not name.startswith("/") and "\\" not in name and "\x00" not in name and
        all(part not in ("", ".", "..") for part in name.split("/"))
    )


def sources(root, path, generated):
    source = root / path
    if not source.exists():
        if generated:
            return []
        raise ValueError("缺少必需资源: " + path)
    if source.is_symlink():
        raise ValueError("禁止符号链接: " + path)
    files = sorted(source.rglob("*")) if source.is_dir() else [source]
    result = []
    for file in files:
        if file.is_dir():
            continue
        rel = file.relative_to(root).as_posix()
        if file.is_symlink() or not file.is_file() or not file.resolve().is_relative_to(root.resolve()):
            raise ValueError("不安全资源: " + rel)
        if file.name == ".gitkeep":
            continue
        if not safe_path(rel) or file.suffix.lower() not in EXTENSIONS:
            raise ValueError("不支持的资源: " + rel)
        if file.stat().st_size > MAX_FILE:
            raise ValueError("单文件过大: " + rel)
        result.append((rel, file.read_bytes()))
    if not result and not generated:
        raise ValueError("必需资源组为空: " + path)
    if sum(len(data) for _, data in result) > MAX_PACK:
        raise ValueError("资源包过大: " + path)
    return result


def add(archive, path, data):
    info = zipfile.ZipInfo(path, date_time=STAMP)
    info.create_system = 3
    info.external_attr = 0o100644 << 16
    info.compress_type = zipfile.ZIP_DEFLATED
    archive.writestr(info, data, compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)


def build(root, out, only=None):
    if only is not None and not set(only).issubset(PACKS):
        raise ValueError('未知资源包 ID')
    root = root.resolve()
    out.mkdir(parents=True, exist_ok=True)
    catalog = {"schema": 1, "packs": [], "skippedGenerated": []}
    for pack_id, (path, generated) in PACKS.items():
        if only is not None and pack_id not in only:
            continue
        files = sources(root, path, generated)
        if not files:
            catalog["skippedGenerated"].append(pack_id)
            continue
        entries = [{"path": name, "sha256": sha(data), "bytes": len(data)} for name, data in files]
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w") as archive:
            add(archive, "manifest.json", json_bytes({"schema": 1, "id": pack_id, "files": entries}))
            for name, data in files:
                add(archive, name, data)
        content = buf.getvalue()
        digest = sha(content)
        filename = f"{pack_id}-{digest[:16]}.zip"
        (out / filename).write_bytes(content)
        catalog["packs"].append({
            "id": pack_id, "filename": filename, "sha256": digest,
            "bytes": len(content), "files": len(files),
            "uncompressedBytes": sum(item["bytes"] for item in entries)
        })
    (out / "catalog.json").write_bytes(json_bytes(catalog))
    return catalog


def verify(catalog_path):
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    if catalog.get("schema") != 1 or not isinstance(catalog.get("packs"), list):
        raise ValueError("catalog 版本不支持")
    seen = set()
    for pack in catalog["packs"]:
        pack_id, filename = pack["id"], pack["filename"]
        if pack_id not in PACKS or pack_id in seen:
            raise ValueError("未知或重复资源包: " + pack_id)
        seen.add(pack_id)
        if not safe_path(filename) or "/" in filename:
            raise ValueError("文件名不安全: " + filename)
        data = (catalog_path.parent / filename).read_bytes()
        if sha(data) != pack["sha256"] or len(data) != pack["bytes"] or filename != f"{pack_id}-{sha(data)[:16]}.zip":
            raise ValueError("资源包校验和错误: " + pack_id)
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            infos = archive.infolist()
            names = [item.filename for item in infos]
            if len(infos) > 1024 or sum(item.file_size for item in infos) > MAX_PACK:
                raise ValueError("资源 ZIP 超限: " + pack_id)
            if len(names) != len(set(names)) or any(not safe_path(name) for name in names):
                raise ValueError("ZIP 包含重复或不安全路径: " + pack_id)
            if not names or names[0] != "manifest.json":
                raise ValueError("资源包缺少 manifest: " + pack_id)
            manifest = json.loads(archive.read("manifest.json"))
            if manifest.get("schema") != 1 or manifest.get("id") != pack_id:
                raise ValueError("资源包 manifest 无效: " + pack_id)
            entries = manifest.get("files", [])
            if len(entries) != pack["files"] or names[1:] != [item["path"] for item in entries]:
                raise ValueError("ZIP 清单不匹配: " + pack_id)
            total = 0
            for entry in entries:
                name = entry["path"]
                info = archive.getinfo(name)
                if info.file_size > MAX_FILE:
                    raise ValueError("文件超限: " + name)
                content = archive.read(name)
                if len(content) != entry["bytes"] or sha(content) != entry["sha256"]:
                    raise ValueError("内容校验失败: " + name)
                total += len(content)
            if total != pack["uncompressedBytes"]:
                raise ValueError("总字节数错误: " + pack_id)
    return catalog


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build")
    b.add_argument("--root", type=Path, default=Path("."))
    b.add_argument("--out", type=Path, default=Path("build/asset-packs"))
    b.add_argument("--only", action="append", choices=sorted(PACKS))
    v = sub.add_parser("verify")
    v.add_argument("--catalog", type=Path, default=Path("build/asset-packs/catalog.json"))
    args = parser.parse_args()
    try:
        cat = build(args.root, args.out, args.only) if args.cmd == "build" else verify(args.catalog)
        if args.cmd == "build":
            verify(args.out / "catalog.json")
        for item in cat["packs"]:
            print(f'{item["id"]}: {item["files"]} files, {item["uncompressedBytes"]} -> {item["bytes"]} bytes')
        print("未生成的可选资源:", ", ".join(cat["skippedGenerated"]))
    except (ValueError, OSError, KeyError, TypeError, zipfile.BadZipFile) as err:
        print(f"资源包失败: {err}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
