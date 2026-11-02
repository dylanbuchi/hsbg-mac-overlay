#!/bin/sh
# Prints the GitHub release body for a version: docs/release-notes-<version>.md without its
# "# title" line and its "## Verify the download" section, then the generic download note.
# Usage: sh scripts/release-notes.sh 0.2.0 > notes.md   (fails if the notes file is missing or empty)
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION="${1:?usage: release-notes.sh <version, e.g. 0.2.0>}"
NOTES="$PROJECT_DIR/docs/release-notes-$VERSION.md"

if [ ! -s "$NOTES" ]; then
  echo "::error::Missing release notes: docs/release-notes-$VERSION.md. Write them before tagging v$VERSION." >&2
  exit 1
fi

# Drop the first "# " title and the "## Verify the download" section (up to the next "## " heading),
# then trim blank lines at the start and the end.
BODY=$(awk '
  !titled && /^# / { titled = 1; next }
  /^## / { skip = ($0 ~ /^## Verify the download/) }
  !skip { print }
' "$NOTES" | awk 'NF { started = 1 } started' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')

if [ -z "$BODY" ]; then
  echo "::error::docs/release-notes-$VERSION.md has no content besides its title." >&2
  exit 1
fi

printf '%s\n\n---\n\n' "$BODY"
cat <<'EOF'
Built by GitHub Actions from the tagged source. First launch: see Install in the README (macOS asks you to allow the app once, because it is not notarized). SHA-256 is in the .sha256 file. To verify the download, first cd to the folder you saved it in (for example cd ~/Downloads), then run: shasum -a 256 -c HSBG-Mac-Overlay.zip.sha256 and gh attestation verify HSBG-Mac-Overlay.zip --owner dylanbuchi
EOF
