#!/usr/bin/env python3
"""Validate release-facing files and local links in tracked Markdown."""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
import html
from pathlib import Path, PurePosixPath
import re
import shlex
import subprocess
import sys
from urllib.parse import unquote, urlsplit
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parents[1]
REQUIRED_FILES = (
    "README.md",
    "README_CN.md",
    "LICENSE",
    "DEPENDENCIES.md",
    "project.godot",
    ".github/workflows/ci.yml",
    ".github/workflows/release.yml",
    "docs/images/studio-to-3d-editor.png",
    "docs/images/foveaengine-bonsai-runtime.png",
)
EXTERNAL_SCHEMES = {"data", "ftp", "http", "https", "mailto", "tel"}
GITHUB_ACTIONS_PAGE = re.compile(
    r"^https://github\.com/[^/]+/[^/]+/actions/workflows/[^/?#]+(?:/badge\.svg)?$"
)
MARKDOWN_LINK = re.compile(r"!?\[[^\]\n]*\]\(([^)\n]+)\)")
REFERENCE_LINK = re.compile(r"^\s*\[[^\]\n]+\]:\s*(\S+)", re.MULTILINE)
HTML_LINK = re.compile(r"\b(?:href|src)\s*=\s*([\"'])(.*?)\1", re.IGNORECASE)
FENCE = re.compile(r"(?:```|~~~).*?(?:```|~~~)", re.DOTALL)
WINDOWS_ABSOLUTE = re.compile(r"^[A-Za-z]:[\\/]")
HEADING = re.compile(r"^\s{0,3}#{1,6}\s+(.+?)\s*#*\s*$", re.MULTILINE)
EXPLICIT_ID = re.compile(r"\bid\s*=\s*([\"'])(.*?)\1", re.IGNORECASE)


@dataclass(frozen=True)
class Link:
    source: PurePosixPath
    line: int
    target: str


def git_files() -> set[PurePosixPath]:
    result = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "-z"],
        check=True,
        capture_output=True,
    )
    return {
        PurePosixPath(value.decode("utf-8"))
        for value in result.stdout.split(b"\0")
        if value
    }


def strip_fences(text: str) -> str:
    return FENCE.sub(lambda match: "\n" * match.group(0).count("\n"), text)


def first_target(value: str) -> str:
    value = html.unescape(value.strip())
    if value.startswith("<") and ">" in value:
        return value[1 : value.index(">")]
    try:
        parts = shlex.split(value, posix=True)
    except ValueError:
        parts = value.split()
    return parts[0] if parts else ""


def links_in(source: PurePosixPath) -> list[Link]:
    text = (ROOT / Path(source.as_posix())).read_text(encoding="utf-8")
    text = strip_fences(text)
    matches: list[tuple[int, str]] = []
    matches.extend((match.start(), match.group(1)) for match in MARKDOWN_LINK.finditer(text))
    matches.extend((match.start(), match.group(1)) for match in REFERENCE_LINK.finditer(text))
    matches.extend((match.start(), match.group(2)) for match in HTML_LINK.finditer(text))
    return [
        Link(source, text.count("\n", 0, offset) + 1, first_target(target))
        for offset, target in matches
        if first_target(target)
    ]


def github_slug(value: str) -> str:
    value = re.sub(r"<[^>]+>", "", value)
    value = value.replace("`", "").strip().lower()
    value = re.sub(r"[^\w\s-]", "", value, flags=re.UNICODE)
    return re.sub(r"\s", "-", value).strip("-")


def anchors_in(path: Path) -> set[str]:
    if path.suffix.lower() != ".md":
        return set()
    text = strip_fences(path.read_text(encoding="utf-8"))
    anchors = {html.unescape(match.group(2)) for match in EXPLICIT_ID.finditer(text)}
    counts: dict[str, int] = {}
    for match in HEADING.finditer(text):
        base = github_slug(match.group(1))
        if not base:
            continue
        count = counts.get(base, 0)
        anchors.add(base if count == 0 else f"{base}-{count}")
        counts[base] = count + 1
    return anchors


def case_exact(relative: PurePosixPath) -> tuple[bool, str]:
    current = ROOT
    for part in relative.parts:
        if part in {"", "."}:
            continue
        if part == "..":
            current = current.parent
            continue
        if not current.is_dir():
            return False, f"missing parent {current.relative_to(ROOT).as_posix()}"
        names = {entry.name for entry in current.iterdir()}
        if part not in names:
            folded = next((name for name in names if name.casefold() == part.casefold()), None)
            if folded is not None:
                return False, f"wrong case: expected {folded}"
            return False, "missing target"
        current /= part
    return current.exists(), "missing target"


def validate_link(link: Link) -> str | None:
    target = unquote(link.target)
    split = urlsplit(target)
    if split.scheme.lower() in EXTERNAL_SCHEMES or target.startswith("//"):
        return None
    if WINDOWS_ABSOLUTE.match(target) or target.startswith(("/C:/", "/F:/", "file://")):
        return "machine-absolute path"

    path_text = split.path.replace("\\", "/")
    if path_text.startswith("res://"):
        relative = PurePosixPath(path_text.removeprefix("res://"))
    elif path_text.startswith("/"):
        return "repository-external absolute path"
    elif path_text:
        relative = link.source.parent / PurePosixPath(path_text)
    else:
        relative = link.source

    normalized = PurePosixPath(*[part for part in relative.parts if part != "."])
    resolved = (ROOT / Path(normalized.as_posix())).resolve()
    try:
        repository_relative = PurePosixPath(resolved.relative_to(ROOT).as_posix())
    except ValueError:
        return "target escapes repository"

    exists, detail = case_exact(repository_relative)
    if not exists:
        return detail
    if split.fragment:
        anchor = html.unescape(split.fragment)
        if anchor not in anchors_in(resolved):
            return f"missing anchor #{anchor}"
    return None


def external_url(target: str) -> str | None:
    target = html.unescape(target)
    split = urlsplit(target)
    if split.scheme.lower() not in {"http", "https"}:
        return None
    return split._replace(fragment="").geturl()


def request_external(url: str, method: str) -> int:
    request = Request(
        url,
        method=method,
        headers={"User-Agent": "FoveaEngine-public-docs-check/1.0"},
    )
    with urlopen(request, timeout=12) as response:
        return int(response.status)


def validate_external(url: str) -> tuple[str | None, str | None]:
    try:
        status = request_external(url, "HEAD")
    except HTTPError as error:
        if error.code == 405:
            try:
                status = request_external(url, "GET")
            except (HTTPError, URLError, TimeoutError, OSError) as retry_error:
                return f"GET failed: {retry_error}", None
        elif error.code in {401, 403, 429} or (
            error.code == 404 and GITHUB_ACTIONS_PAGE.fullmatch(url)
        ):
            return None, f"HTTP {error.code} (access or rate limited)"
        else:
            return f"HTTP {error.code}", None
    except (URLError, TimeoutError, OSError) as error:
        return f"request failed: {error}", None
    if status >= 400:
        return f"HTTP {status}", None
    return None, None


def validate_required(tracked: set[PurePosixPath]) -> list[str]:
    errors: list[str] = []
    for value in REQUIRED_FILES:
        path = PurePosixPath(value)
        if path not in tracked:
            errors.append(f"required file is not tracked: {value}")
        elif not (ROOT / value).is_file():
            errors.append(f"required file is missing: {value}")

    license_text = (ROOT / "LICENSE").read_text(encoding="utf-8")
    if "MIT License" not in license_text or "Permission is hereby granted" not in license_text:
        errors.append("LICENSE does not contain the expected MIT grant")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--external",
        action="store_true",
        help="also probe unique HTTP(S) links; access-limited endpoints are warnings",
    )
    arguments = parser.parse_args()
    tracked = git_files()
    markdown_files = sorted(path for path in tracked if path.suffix.lower() == ".md")
    errors = validate_required(tracked)
    local_checked = 0
    external_urls: set[str] = set()
    for source in markdown_files:
        for link in links_in(source):
            url = external_url(link.target)
            if url is not None:
                external_urls.add(url)
                continue
            local_checked += 1
            problem = validate_link(link)
            if problem:
                errors.append(f"{link.source}:{link.line}: {problem}: {link.target}")

    warnings: list[str] = []
    if arguments.external:
        with ThreadPoolExecutor(max_workers=8) as executor:
            results = executor.map(validate_external, sorted(external_urls))
            for url, (problem, warning) in zip(sorted(external_urls), results, strict=True):
                if problem:
                    errors.append(f"external link: {problem}: {url}")
                if warning:
                    warnings.append(f"external link: {warning}: {url}")

    if errors:
        print(f"Public docs validation failed ({len(errors)} issue(s)):")
        for error in sorted(errors):
            print(f"  - {error}")
        for warning in sorted(warnings):
            print(f"  - warning: {warning}")
        return 1
    print(
        f"Public docs validation passed: {len(markdown_files)} Markdown files, "
        f"{local_checked} local links, {len(REQUIRED_FILES)} required files."
    )
    if arguments.external:
        print(
            f"External links probed: {len(external_urls)} total, "
            f"{len(warnings)} access-limited warning(s)."
        )
        for warning in sorted(warnings):
            print(f"  - warning: {warning}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
