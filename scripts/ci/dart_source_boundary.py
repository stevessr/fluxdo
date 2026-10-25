"""Audit local Dart module boundaries, including every conditional URI.

Only directives are interpreted. Comments and strings in implementation code
cannot hide a real directive or create false imports. Flutter/Dart still perform
the language/type checks; this is the pre-build source isolation gate.
"""
from __future__ import annotations

from pathlib import Path
import re
from urllib.parse import unquote, urlsplit


def _tokens(source: str):
    i = 0
    while i < len(source):
        if source[i].isspace():
            i += 1
            continue
        if source.startswith("//", i):
            end = source.find("\n", i + 2)
            i = len(source) if end < 0 else end + 1
            continue
        if source.startswith("/*", i):
            depth = 1
            i += 2
            while i < len(source) and depth:
                if source.startswith("/*", i):
                    depth += 1
                    i += 2
                elif source.startswith("*/", i):
                    depth -= 1
                    i += 2
                else:
                    i += 1
            if depth:
                raise ValueError("Unterminated Dart comment")
            continue
        raw = source[i] == "r" and i + 1 < len(source) and source[i + 1] in "'\""
        if raw or source[i] in "'\"":
            if raw:
                i += 1
            quote = source[i]
            delimiter = quote * (3 if source.startswith(quote * 3, i) else 1)
            i += len(delimiter)
            start = i
            while i < len(source) and not source.startswith(delimiter, i):
                i += 2 if not raw and source[i] == "\\" else 1
            if i >= len(source):
                raise ValueError("Unterminated Dart string")
            yield ("string", source[start:i])
            i += len(delimiter)
            continue
        match = re.match(r"[a-zA-Z_$][a-zA-Z0-9_$]*", source[i:])
        if match:
            value = match.group()
            yield ("word", value)
            i += len(value)
        else:
            yield ("symbol", source[i])
            i += 1


def directive_uris(source: str) -> list[str]:
    # Import/export/part directives precede declarations. Stop before scanning
    # implementation strings (which may contain complex Dart interpolation).
    tokens = iter(_tokens(source))
    result = []
    head = next(tokens, None)
    while head is not None:
        kind, value = head
        if head == ("symbol", "@"):
            # Metadata can precede a library/import or the first declaration.
            # Skip only the annotation, then inspect the following token.
            head = next(tokens, None)
            if head is None or head[0] != "word":
                raise ValueError("Invalid Dart annotation")
            head = next(tokens, None)
            while head == ("symbol", "."):
                name = next(tokens, None)
                if name is None or name[0] != "word":
                    raise ValueError("Invalid qualified Dart annotation")
                head = next(tokens, None)
            for opening, closing in (("<", ">"), ("(", ")")):
                if head != ("symbol", opening):
                    continue
                depth = 1
                for token in tokens:
                    if token == ("symbol", opening):
                        depth += 1
                    elif token == ("symbol", closing):
                        depth -= 1
                        if not depth:
                            break
                else:
                    raise ValueError("Unterminated Dart annotation")
                head = next(tokens, None)
            continue
        if kind != "word" or value not in ("library", "import", "export", "part"):
            break
        declaration = []
        for token in tokens:
            if token == ("symbol", ";"):
                break
            declaration.append(token)
        else:
            raise ValueError("Unterminated Dart directive")
        head = next(tokens, None)
        if value == "library" or (value == "part" and declaration[:1] == [("word", "of")]):
            continue
        if not declaration or declaration[0][0] != "string":
            raise ValueError("Dart directive lacks a URI")
        uris = [declaration[0][1]]
        uris += [token[1] for index, token in enumerate(declaration[1:], 1)
                 if token[0] == "string" and declaration[index - 1] == ("symbol", ")")]
        for uri in uris:
            if not uri or "\\" in uri or "$" in uri:
                raise ValueError("Escaped or interpolated Dart import URI is unsupported")
            result.append(uri)
    return result


def verify_dart_sources(stage: Path, *, own_package: str,
                        allowed_packages: set[str] | None = None,
                        pending_generated: set[Path] | None = None) -> set[str]:
    stage = stage.resolve()
    pending = {p.resolve() for p in (pending_generated or set())}
    packages: set[str] = set()
    errors = []
    for source in sorted((stage / "lib").rglob("*.dart")):
        try:
            uris = directive_uris(source.read_text(encoding="utf-8"))
        except ValueError as error:
            errors.append(f"{source.relative_to(stage)}: {error}")
            continue
        for uri in uris:
            parsed = urlsplit(uri)
            decoded = unquote(parsed.path)
            if parsed.query or parsed.fragment or parsed.netloc:
                errors.append(f"{source.relative_to(stage)} -> {uri} (invalid URI)")
                continue
            if parsed.scheme == "dart":
                continue
            if parsed.scheme == "package":
                package, separator, relative = decoded.partition("/")
                if not separator or not re.fullmatch(r"[a-z][a-z0-9_]*", package):
                    errors.append(f"{source.relative_to(stage)} -> {uri} (invalid package)")
                    continue
                if package != own_package:
                    packages.add(package)
                    if allowed_packages is not None and package not in allowed_packages:
                        errors.append(f"{source.relative_to(stage)} -> {uri} (forbidden package)")
                    continue
                target = stage / "lib" / relative
            elif parsed.scheme or decoded.startswith("/"):
                errors.append(f"{source.relative_to(stage)} -> {uri} (unsupported URI)")
                continue
            else:
                target = source.parent / decoded
            resolved = target.resolve()
            if not resolved.is_relative_to(stage):
                errors.append(f"{source.relative_to(stage)} -> {uri} (escapes stage)")
            elif not target.is_file() and resolved not in pending:
                errors.append(f"{source.relative_to(stage)} -> {uri} (missing source)")
    if errors:
        raise RuntimeError("Broken Dart import graph:\n" + "\n".join(errors[:30]))
    return packages
