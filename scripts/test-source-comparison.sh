#!/usr/bin/env bash
# Exact production-JS controller and connected DOM tests. No build or installation.
set -euo pipefail
SOURCE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
node --check "$SOURCE/ui/rabbita-job/source-comparison.js"
node --check "$SOURCE/ui/rabbita-job/source-brief-controls.js"
node --check "$SOURCE/ui/rabbita-job/observed-cases.js"
node --check "$SOURCE/ui/rabbita-job/observed-case-controls.js"
node --test "$SOURCE"/ui/rabbita-job/*.test.mjs
