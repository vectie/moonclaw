#!/bin/bash

# MoonClaw Gateway Status Check Script
# Similar to `openclaw status` but for MoonClaw Gateway

set -e

GATEWAY_URL="${GATEWAY_URL:-http://localhost:18123}"
GATEWAY_PORT="${GATEWAY_PORT:-18123}"

echo ""
echo "🦞 MoonClaw Gateway Status Check"
echo ""

# Check if gateway is reachable
echo "Checking gateway at $GATEWAY_URL..."
if curl -s -o /dev/null -w "%{http_code}" "$GATEWAY_URL/v1/health" | grep -q "200"; then
    echo "✅ Gateway is reachable"
    echo ""
    
    # Get health info
    HEALTH=$(curl -s "$GATEWAY_URL/v1/health")
    
    STATUS=$(echo "$HEALTH" | grep -o '"status"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
    UPTIME_MS=$(echo "$HEALTH" | grep -o '"uptime_ms"[[:space:]]*:[[:space:]]*[0-9]*' | grep -o '[0-9]*')
    SESSIONS=$(echo "$HEALTH" | grep -o '"active_sessions"[[:space:]]*:[[:space:]]*[0-9]*' | grep -o '[0-9]*')
    PENDING=$(echo "$HEALTH" | grep -o '"pending_requests"[[:space:]]*:[[:space:]]*[0-9]*' | grep -o '[0-9]*')
    
    # Format uptime
    if [ "$UPTIME_MS" -lt 1000 ]; then
        UPTIME_FMT="${UPTIME_MS}ms"
    elif [ "$UPTIME_MS" -lt 60000 ]; then
        UPTIME_FMT="$((UPTIME_MS / 1000))s"
    elif [ "$UPTIME_MS" -lt 3600000 ]; then
        MINS=$((UPTIME_MS / 60000))
        SECS=$(((UPTIME_MS % 60000) / 1000))
        UPTIME_FMT="${MINS}m ${SECS}s"
    elif [ "$UPTIME_MS" -lt 86400000 ]; then
        HOURS=$((UPTIME_MS / 3600000))
        MINS=$(((UPTIME_MS % 3600000) / 60000))
        UPTIME_FMT="${HOURS}h ${MINS}m"
    else
        DAYS=$((UPTIME_MS / 86400000))
        HOURS=$(((UPTIME_MS % 86400000) / 3600000))
        UPTIME_FMT="${DAYS}d ${HOURS}h"
    fi
    
    echo "Gateway Status"
    echo "┌─────────────────┬────────────────────────────────────────────────────────┐"
    echo "│ Item            │ Value                                                  │"
    echo "├─────────────────┼────────────────────────────────────────────────────────┤"
    printf "│ Dashboard       │ http://127.0.0.1:%-47s │\n" "$GATEWAY_PORT/"
    printf "│ Gateway         │ ws://127.0.0.1:%-48s │\n" "$GATEWAY_PORT (reachable)"
    printf "│ Status          │ %-56s │\n" "$STATUS"
    printf "│ Uptime          │ %-56s │\n" "$UPTIME_FMT"
    printf "│ Sessions        │ %-56s │\n" "$SESSIONS active"
    printf "│ Pending         │ %-56s │\n" "$PENDING pending"
    echo "└─────────────────┴────────────────────────────────────────────────────────┘"
    echo ""
    
    # Get sessions
    echo "Sessions"
    SESSIONS_DATA=$(curl -s "$GATEWAY_URL/v1/sessions")
    SESSION_COUNT=$(echo "$SESSIONS_DATA" | grep -o '"session_id"' | wc -l | tr -d ' ')
    
    if [ "$SESSION_COUNT" -gt 0 ]; then
        echo "  Found $SESSION_COUNT session(s)"
    else
        echo "  No active sessions"
    fi
    echo ""
    
    echo "✅ Gateway is running properly!"
    echo ""
    echo "Next steps:"
    echo "  Need to debug live? moonclaw gateway logs --follow"
    echo "  Need more details?  moonclaw gateway connect"
    echo "  Need to test agent? moonclaw gateway agent --message \"hello\" --wait"
    
else
    echo "❌ Gateway is NOT reachable at $GATEWAY_URL"
    echo ""
    echo "The gateway might not be running. Start it with:"
    echo "  moonclaw gateway start"
    echo ""
    echo "Or check if something is running on port $GATEWAY_PORT:"
    echo "  lsof -i :$GATEWAY_PORT"
    exit 1
fi
