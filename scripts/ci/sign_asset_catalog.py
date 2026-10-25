#!/usr/bin/env python3
"""Ed25519 sign/verify a validated catalog using external OpenSSL PEM keys."""
import argparse
from pathlib import Path
import subprocess
import sys

from asset_packs import verify


def sign(catalog: Path, key: Path, output: Path):
    verify(catalog)
    output.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["openssl", "pkeyutl", "-sign", "-rawin",
                    "-inkey", str(key), "-in", str(catalog), "-out", str(output)],
                   check=True)
    if len(output.read_bytes()) != 64:
        output.unlink(missing_ok=True)
        raise ValueError("Ed25519 signature must be 64 bytes")


def check(catalog: Path, key: Path, signature: Path):
    verify(catalog)
    if len(signature.read_bytes()) != 64:
        raise ValueError("Ed25519 signature must be 64 bytes")
    subprocess.run(["openssl", "pkeyutl", "-verify", "-rawin", "-pubin",
                    "-inkey", str(key), "-sigfile", str(signature),
                    "-in", str(catalog)], check=True)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("action", choices=("sign", "verify"))
    p.add_argument("--catalog", required=True, type=Path)
    p.add_argument("--key", required=True, type=Path)
    p.add_argument("--signature", required=True, type=Path)
    args = p.parse_args()
    try:
        if args.action == "sign":
            sign(args.catalog, args.key, args.signature)
        else:
            check(args.catalog, args.key, args.signature)
    except (OSError, subprocess.CalledProcessError, ValueError) as err:
        print(f"Catalog signing failed: {err}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
