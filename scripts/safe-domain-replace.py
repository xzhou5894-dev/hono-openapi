#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import sys

EXCLUDE_DIRS = {".git", "node_modules", "frontend/node_modules", "backend/node_modules", "dist", "build", ".venv", "__pycache__"}
EXCLUDE_EXTENSIONS = {
    ".png", ".jpg", ".jpeg", ".gif", ".svg", ".ico", ".zip", ".tar", ".gz", ".tgz", ".7z", ".pdf", ".pptx", ".xlsx", ".docx",
    ".woff", ".woff2", ".eot", ".ttf", ".otf", ".db", ".sqlite", ".bin", ".exe", ".dll", ".dat", ".class", ".jar", ".pyc",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Safely replace an old domain with a new domain across text files in the repo.",
    )
    parser.add_argument("old", help="Old domain or string to replace")
    parser.add_argument("new", help="New domain or string to use")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show affected files and counts without modifying anything.",
    )
    parser.add_argument(
        "--backup",
        action="store_true",
        help="Create a .bak backup for each modified file.",
    )
    return parser.parse_args()


def is_excluded(path: Path, root: Path) -> bool:
    relative = path.relative_to(root)
    parts = relative.parts
    for excluded in EXCLUDE_DIRS:
        if excluded in parts:
            return True
    suffix = path.suffix.lower()
    if suffix in EXCLUDE_EXTENSIONS:
        return True
    return False


def is_text_file(path: Path) -> bool:
    try:
        with path.open("rb") as f:
            chunk = f.read(1024)
        chunk.decode("utf-8")
        return True
    except (UnicodeDecodeError, OSError):
        return False


def find_files(root: Path, old: str) -> list[Path]:
    matches: list[Path] = []
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        if is_excluded(path, root):
            continue
        if not is_text_file(path):
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        if old in text:
            matches.append(path)
    return matches


def main() -> int:
    args = parse_args()
    root = Path(__file__).resolve().parents[1]
    old = args.old
    new = args.new

    files = find_files(root, old)
    if not files:
        print(f"No text files containing '{old}' were found.")
        return 0

    print(f"Found {len(files)} file(s) containing '{old}':")
    for path in files:
        print(f"  {path.relative_to(root)}")

    if args.dry_run:
        print("\nDry run complete. No files modified.")
        return 0

    for path in files:
        text = path.read_text(encoding="utf-8")
        updated = text.replace(old, new)
        if updated != text:
            if args.backup:
                backup_path = path.with_suffix(path.suffix + ".bak")
                backup_path.write_text(text, encoding="utf-8")
            path.write_text(updated, encoding="utf-8")
            print(f"Replaced in {path.relative_to(root)}")
    print(f"\nReplaced '{old}' with '{new}' in {len(files)} files.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
