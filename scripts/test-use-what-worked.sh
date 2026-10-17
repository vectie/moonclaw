#!/usr/bin/env bash
# Source/controller tests only: no install, provider, browser or native service.
set -euo pipefail
cd "$(dirname "$0")/.."
node --check ui/rabbita-job/procedures.js
node --check ui/rabbita-job/procedure-controls.js
node --test ui/rabbita-job/procedures.test.mjs ui/rabbita-job/book-outcome.test.mjs ui/rabbita-job/stream-drain.test.mjs
