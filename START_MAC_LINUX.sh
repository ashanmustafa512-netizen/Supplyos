#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v node >/dev/null 2>&1; then
  echo "ERROR: Node.js is not installed. Install Node.js 22 LTS from https://nodejs.org/ first." >&2
  exit 1
fi
node -e 'if (Number(process.versions.node.split(".")[0]) !== 22) { console.error("This project is pinned to Node.js 22.x. Install Node.js 22 LTS."); process.exit(1); }'
if [ ! -d node_modules ]; then
  echo "First run: installing website dependencies (internet required)..."
  npm ci --no-audit --no-fund
fi
if [ ! -f .env.local ]; then
  echo "NOTE: .env.local is missing. The website will open its /setup screen until Supabase is configured."
fi
echo "Starting SupplyOS at http://localhost:3000. Leave this terminal open; Ctrl+C stops it."
npm run dev
