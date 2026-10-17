#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
node --check ui/rabbita-job/blocked-recovery.js
node --check ui/rabbita-job/blocked-recovery-controls.js
node --test ui/rabbita-job/blocked-recovery.test.mjs ui/rabbita-job/procedures.test.mjs
