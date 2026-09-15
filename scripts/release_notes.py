"""Validate and extract the changelog entry used by the release workflow."""

import re
import sys
from pathlib import Path


def release_notes(changelog, tag):
    if not re.fullmatch(r"v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*))?", tag):
        raise ValueError("Expected a release tag such as v1.2.4.")
    sections = re.split(r"^##[ \t]+(.+?)[ \t]*$", changelog, flags=re.MULTILINE)
    entries = [sections[i + 1] for i in range(1, len(sections), 2) if sections[i] == tag]
    if len(entries) != 1:
        raise ValueError(f"CHANGELOG.md must contain exactly one '## {tag}' section.")
    bullets = [line.strip() for line in entries[0].splitlines() if line.strip()]
    if not 2 <= len(bullets) <= 4 or not all(re.fullmatch(r"- \S.*", line) for line in bullets):
        raise ValueError(f"CHANGELOG.md section {tag} needs 2–4 nonempty, single-line '- ' bullets.")
    return "\n".join([
        "## What's changed", "", *bullets, "", "## Download", "",
        f"Download `Glance-{tag[1:]}-universal.dmg`, open it, and drag Glance into Applications.",
        "Supports Apple Silicon and Intel Macs running macOS 14 or later.",
        "A SHA-256 checksum is included with the installer.", "",
        "The app is ad hoc signed and is not notarized by Apple.", "",
    ])


if __name__ == "__main__":
    try:
        if len(sys.argv) != 2:
            raise ValueError("Usage: python3 scripts/release_notes.py vMAJOR.MINOR[.PATCH]")
        changelog = Path(__file__).resolve().parent.parent / "CHANGELOG.md"
        print(release_notes(changelog.read_text(), sys.argv[1]), end="")
    except (ValueError, OSError) as error:
        sys.exit(f"Release notes validation failed: {error}")
