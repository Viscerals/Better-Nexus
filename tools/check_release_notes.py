"""Read-only release-note branding check. Does not publish or modify files."""
import argparse
import hashlib
from pathlib import Path

BODY_SLOT = b"{{release_specific_body}}"
# Exact normalized prefix retained from public release 9094, including disclaimer.
PREFIX_SHA256 = "3319df3329eeffed9efb76fd6f5d8e90b03feee8a8dcbfa373b56281af249110"
DEFAULT_TEMPLATE = Path(__file__).resolve().parents[1] / "docs" / "RELEASE_NOTES_TEMPLATE.md"


def normalized(data):
    return data.replace(b"\r\n", b"\n")


def validate(notes, template):
    """Return readable errors; preserve both supplied byte buffers unchanged."""
    notes, template = normalized(notes), normalized(template)
    if template.count(BODY_SLOT) != 1:
        return ["Release template must contain exactly one body slot."]
    prefix, _, suffix = template.partition(BODY_SLOT)
    if suffix.strip() or hashlib.sha256(prefix).hexdigest() != PREFIX_SHA256:
        return ["Canonical branding prefix changed; review the template and pinned reference."]
    errors = []
    if not notes.startswith(prefix):
        errors.append("Release notes must start with the complete canonical branding prefix.")
    if notes.count(prefix) > 1:
        errors.append("Release notes contain a duplicate branding prefix.")
    body = notes[len(prefix):] if notes.startswith(prefix) else b""
    if not body.strip():
        errors.append("Release-specific notes are missing.")
    if BODY_SLOT in notes:
        errors.append("Replace the release-specific body placeholder.")
    return errors


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("notes", type=Path, help="Exact release-notes file to check")
    args = parser.parse_args(argv)
    try:
        errors = validate(args.notes.read_bytes(), DEFAULT_TEMPLATE.read_bytes())
    except OSError as exc:
        parser.exit(2, "Could not read release notes or template: %s\n" % exc)
    for error in errors:
        print("FAIL: " + error)
    if not errors:
        print("PASS: canonical branding and release-specific content are present.")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
