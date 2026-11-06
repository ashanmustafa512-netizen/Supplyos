#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v node >/dev/null 2>&1; then
  echo "ERROR: Node.js is not installed. Install Node.js 22 LTS from https://nodejs.org/ first." >&2
  exit 1
fi
node -e 'const [a,b]=process.versions.node.split(".").map(Number); if (!(a>20||(a===20&&b>=9))) { console.error("Node.js 20.9+ required; Node.js 22 LTS recommended."); process.exit(1); }'
if [ ! -d node_modules ]; then
  echo "First run: installing website dependencies (internet required)..."
  npm install --no-audit --no-fund
fi
if [ ! -f .env.local ]; then
  echo "NOTE: .env.local is missing. The website will open its /setup screen until Supabase is configured."
fi
echo "Starting SupplyOS at http://localhost:3000. Leave this terminal open; Ctrl+C stops it."
npm run dev
