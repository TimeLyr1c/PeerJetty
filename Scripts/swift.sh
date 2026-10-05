#!/bin/zsh
set -euo pipefail
PROJECT_ROOT="${0:A:h:h}"
cd "$PROJECT_ROOT"
export CLANG_MODULE_CACHE_PATH="$PROJECT_ROOT/.module-cache"
export SWIFT_MODULECACHE_PATH="$PROJECT_ROOT/.module-cache"
exec /usr/bin/swift "$@" --cache-path "$PROJECT_ROOT/.build/cache" --config-path "$PROJECT_ROOT/.build/config" --security-path "$PROJECT_ROOT/.build/security" --scratch-path "$PROJECT_ROOT/.build" --disable-sandbox
