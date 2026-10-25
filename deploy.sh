#!/usr/bin/env bash
#
# Deploy back2able to the Hetzner VPS (host `one`) with Kamal.
#
#   ./deploy.sh              # deploy the current git revision
#   ./deploy.sh --version=X  # extra flags are passed to `kamal deploy`
#
set -euo pipefail

cd "$(dirname "$0")"

if ! command -v kamal >/dev/null 2>&1; then
  echo "kamal not found. Install it with: gem install kamal" >&2
  exit 1
fi

VERSION="${VERSION:-$(git rev-parse --short HEAD)}"

exec kamal deploy --version="$VERSION" "$@"
