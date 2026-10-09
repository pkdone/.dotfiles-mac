#!/usr/bin/env bash
# Compatibility shim so existing callers of check.sh keep working.
# exec preserves arguments ("$@"), stdin, and the exit status.
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit
exec "$dir/macconfig-check.sh" "$@"
