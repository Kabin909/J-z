#!/usr/bin/env bash
set -euo pipefail
API_URL="${API_URL:-http://localhost:4000}"
WS_URL="${WS_URL:-http://localhost:4001}"
pass(){ printf '✓ %s\n' "$1"; }
fail(){ printf '✗ %s\n' "$1"; exit 1; }
curl -fsS "$API_URL/api/health" >/dev/null && pass 'API health' || fail 'API health'
curl -fsS "$API_URL/api/ready" >/dev/null && pass 'API readiness' || fail 'API readiness'
curl -fsS "$WS_URL/health" >/dev/null && pass 'WebSocket service health' || fail 'WebSocket service health'
if command -v docker >/dev/null 2>&1; then docker info >/dev/null 2>&1 && pass 'Docker daemon reachable' || printf '• Docker daemon unavailable (expected on control-only hosts)\n'; fi
