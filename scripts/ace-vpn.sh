#!/usr/bin/env bash
# Unified daily entrypoint for ace-vpn operations.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)

usage() {
  cat <<'EOF'
ace-vpn command wrapper

Usage:
  bash scripts/ace-vpn.sh <command> [args...]

Daily commands:
  route <url|host>         Show routing decision and local timing
  add <url|host> <target>  Add local rule; target = IN | DIRECT | VPS
  rules                   List local pending rules
  promote                 Promote local rules to VPS
  rollback [--last]       Roll back local overrides
  smoke [args...]         Direct subscription smoke test
  sync-sub [args...]      Safely deploy sub-converter.py to VPS

Diagnostics:
  doctor                  Local Mihomo / system proxy health check
  party [--fix]           Check/fix local Clash/Mihomo Party stale core state
  speed [args...]         Current network speed / latency test
  ip-check                Check current AI-visible exit IP
  diagnose                Full local diagnostic bundle
  route-test              Built-in routing regression test

Telemetry:
  collect [args...]       Collect one or continuous Mihomo telemetry sample
  report [args...]        Generate monthly traffic report

Deployment:
  install [args...]       Run VPS install entrypoint

Examples:
  bash scripts/ace-vpn.sh route https://www.forbes.com/
  bash scripts/ace-vpn.sh add waimai.meituan.com DIRECT --note "Meituan"
  bash scripts/ace-vpn.sh smoke --direct --query process=1
  bash scripts/ace-vpn.sh report --details-csv ~/Desktop/ace-vpn-traffic.csv
EOF
}

cmd=${1:-help}
if [[ $# -gt 0 ]]; then
  shift
fi

case "$cmd" in
  help|-h|--help)
    usage
    ;;
  route|test-route)
    exec bash "$ROOT_DIR/scripts/test/test-route.sh" "$@"
    ;;
  add|add-rule)
    exec bash "$ROOT_DIR/scripts/rules/add-rule.sh" "$@"
    ;;
  rules|list-rules)
    exec bash "$ROOT_DIR/scripts/rules/list-rules.sh" "$@"
    ;;
  promote)
    exec bash "$ROOT_DIR/scripts/rules/promote-to-vps.sh" "$@"
    ;;
  rollback)
    exec bash "$ROOT_DIR/scripts/rules/rollback-overrides.sh" "$@"
    ;;
  smoke|subscription-smoke)
    exec bash "$ROOT_DIR/scripts/test/subscription-smoke.sh" "$@"
    ;;
  sync-sub|sync-subconverter)
    exec bash "$ROOT_DIR/scripts/rules/sync-subconverter.sh" "$@"
    ;;
  doctor)
    exec bash "$ROOT_DIR/scripts/test/doctor.sh" "$@"
    ;;
  party|mihomo-party|clash-party)
    exec bash "$ROOT_DIR/scripts/common-tools/check-mihomo-party.sh" "$@"
    ;;
  speed|speed-test)
    exec bash "$ROOT_DIR/scripts/test/speed-test.sh" "$@"
    ;;
  ip-check)
    exec bash "$ROOT_DIR/scripts/test/ip-check.sh" "$@"
    ;;
  diagnose)
    exec bash "$ROOT_DIR/scripts/test/diagnose.sh" "$@"
    ;;
  route-test|route-regression)
    exec python3 "$ROOT_DIR/scripts/test/route-regression.py" "$@"
    ;;
  collect)
    exec python3 "$ROOT_DIR/scripts/telemetry/mihomo-traffic-collector.py" "$@"
    ;;
  report)
    exec python3 "$ROOT_DIR/scripts/telemetry/monthly-traffic-report.py" "$@"
    ;;
  install)
    exec bash "$ROOT_DIR/scripts/deploy/install.sh" "$@"
    ;;
  *)
    echo "ERROR: unknown command: $cmd" >&2
    echo >&2
    usage >&2
    exit 2
    ;;
esac
