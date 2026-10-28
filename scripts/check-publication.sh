#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

git rev-parse --is-inside-work-tree >/dev/null
count=0
while IFS= read -r -d '' path; do
  case "$path" in
    LICENSE|README.md|CONTRIBUTING.md|SECURITY.md|.gitignore|Info.plist|build.sh|verify.sh|Launch.command|Sources/*.swift|Tests/*.swift|Tests/Fixtures/awesome-xiangqi.md|Docs/*.md|Docs/*.txt|scripts/*.sh|.github/workflows/*.yml) ;;
    *) printf 'Refusing unexpected public file: %s\n' "$path" >&2; exit 1 ;;
  esac
  size=$(git cat-file -s ":$path")
  if (( size > 524288 )); then
    printf 'Refusing unexpectedly large source file: %s\n' "$path" >&2; exit 1
  fi
  encoding=$(git show ":$path" | file -b --mime-encoding -)
  case "$encoding" in
    us-ascii|utf-8|empty) ;;
    *) printf 'Refusing non-text public file: %s\n' "$path" >&2; exit 1 ;;
  esac
  count=$((count + 1))
done < <(git ls-files -z)
(( count > 0 )) || { printf 'No staged/tracked files to audit.\n' >&2; exit 1; }

# Match values, not illustrative names of secret types. Do not print matches.
if git grep --cached -I -l -E \
  '(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{30,}|sk-(proj-)?[A-Za-z0-9_-]{30,}|AKIA[A-Z0-9]{16}|BEGIN ([A-Z]+ )?PRIVATE KEY|/(Users|home)/[A-Za-z0-9._-]+/)' \
  -- . >/dev/null; then
  printf 'Publication blocked: possible credential or personal workstation path in the index. Inspect locally.\n' >&2
  exit 1
fi
printf 'PASS publication boundary: %s small text files; no bundled books, models, executables or known credential patterns.\n' "$count"
printf 'This check does not replace copyright review or a full security audit.\n'
