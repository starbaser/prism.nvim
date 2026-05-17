#!/usr/bin/env bash
# Rename the template from eigenplug to a new plugin name.
# Usage: bash scripts/rename.sh <new-name>
# Example: bash scripts/rename.sh foobar
#   → produces lua/foobar/, plugin/foobar.lua, FOOBAR_ROOT, etc.

set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 <new-name>" >&2
  exit 1
fi

NEW="$1"
NEW_UPPER="$(echo "$NEW" | tr '[:lower:]' '[:upper:]')"
NEW_PASCAL="$(echo "${NEW:0:1}" | tr '[:lower:]' '[:upper:]')${NEW:1}"

if [ ! -d lua/eigenplug ]; then
  echo "error: lua/eigenplug not found — already renamed?" >&2
  exit 1
fi

# Filesystem moves
mv "lua/eigenplug" "lua/$NEW"
mv "plugin/eigenplug.lua" "plugin/$NEW.lua"

# Text replacements across tracked files (skip .git, result, .direnv)
mapfile -t FILES < <(
  find . \
    -path ./.git -prune -o \
    -path ./result -prune -o \
    -path ./.direnv -prune -o \
    -type f \
    \( -name '*.lua' -o -name '*.nix' -o -name '*.md' -o -name 'justfile' -o -name '.envrc' -o -name '.gitignore' \) \
    -print
)

for f in "${FILES[@]}"; do
  sed -i \
    -e "s/eigenplug/$NEW/g" \
    -e "s/EIGENPLUG/$NEW_UPPER/g" \
    -e "s/Eigenplug/$NEW_PASCAL/g" \
    "$f"
done

echo "Renamed eigenplug → $NEW. Next steps:"
echo "  1. Update flake description in flake.nix"
echo "  2. Re-enter the dev shell: direnv reload (or exit + nix develop)"
echo "  3. Run: just lua-test"
echo "  4. git init && git add . && git commit -m 'initial commit'"
