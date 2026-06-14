#!/bin/bash

set -e

WATCH_SECONDS=0
SERVER=""
PORT="25565"

while [[ $# -gt 0 ]]; do
    case $1 in
        --watch)
            WATCH_SECONDS="$2"
            shift 2
            ;;
        *)
            if [ -z "$SERVER" ]; then
                SERVER="$1"
            elif [ "$PORT" == "25565" ]; then
                PORT="$1"
            fi
            shift
            ;;
    esac
done

if [ -z "$SERVER" ]; then
    echo "Usage: $0 <server_address> [port] [--watch N]"
    echo "Example: $0 play.hypixel.net --watch 10"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$SCRIPT_DIR/.mcstatus_venv"

if ! command -v python3 &> /dev/null; then
    echo "ERROR: python3 not found. Please install Python 3.6+."
    exit 1
fi

if [ ! -d "$VENV_DIR" ]; then
    echo "Creating virtual environment..."
    python3 -m venv "$VENV_DIR"
fi

source "$VENV_DIR/bin/activate"

if ! python -c "import mcstatus" &> /dev/null; then
    echo "Installing mcstatus..."
    pip install mcstatus > /dev/null
fi

hr() {
    echo "============================================================"
}

run_query() {
    hr
    echo "MINECRAFT SERVER INFORMATION for $SERVER"
    hr

    if command -v dig &> /dev/null; then
        echo ""
        echo "DNS RECORDS:"
        ip=$(dig +short "$SERVER" A | head -1)
        if [ -n "$ip" ]; then
            echo "  A record: $ip"
        fi
        cname=$(dig +short "$SERVER" CNAME | head -1)
        if [ -n "$cname" ]; then
            echo "  CNAME: $cname"
        fi
        srv=$(dig +short "_minecraft._tcp.$SERVER" SRV)
        if [ -n "$srv" ]; then
            srv_port=$(echo "$srv" | awk '{print $3}')
            srv_target=$(echo "$srv" | awk '{print $4}' | sed 's/\.$//')
            echo "  SRV: port $srv_port target $srv_target"
            if [ "$srv_port" != "25565" ]; then
                PORT="$srv_port"
                echo "  Using SRV port $PORT"
            fi
        else
            echo "  No Minecraft SRV record"
        fi
    else
        echo "dig not installed, skipping DNS lookup"
        ip=""
    fi

    if [ -n "$ip" ] && command -v curl &> /dev/null; then
        echo ""
        echo "GEOLOCATION OF SERVER IP ($ip):"
        geo=$(curl -s "http://ip-api.com/json/$ip?fields=status,country,city,regionName,isp")
        if echo "$geo" | grep -q '"status":"success"'; then
            country=$(echo "$geo" | sed -n 's/.*"country":"\([^"]*\)".*/\1/p')
            city=$(echo "$geo" | sed -n 's/.*"city":"\([^"]*\)".*/\1/p')
            region=$(echo "$geo" | sed -n 's/.*"regionName":"\([^"]*\)".*/\1/p')
            isp=$(echo "$geo" | sed -n 's/.*"isp":"\([^"]*\)".*/\1/p')
            echo "  Country: ${country:-unknown}"
            echo "  City/Region: ${city:-unknown}, ${region:-unknown}"
            echo "  ISP/Organization: ${isp:-unknown}"
        else
            echo "  Geolocation query failed."
        fi
    fi

    echo ""
    echo "SERVER STATUS ($SERVER:$PORT)"
    echo "-----------------------------"

    python3 -c "
import sys, re, time
from mcstatus import JavaServer

def clean_text(text):
    if not isinstance(text, str):
        return str(text)
    text = re.sub(r'§[0-9a-fklmnor]', '', text)
    text = re.sub(r'<[^>]+>', '', text)
    text = re.sub(r'[\x00-\x1f\x7f]', '', text)
    text = re.sub(r'\s+', ' ', text)
    return text.strip()

try:
    server = JavaServer.lookup('$SERVER:$PORT')
    status = server.status()
    query = None
    try:
        query = server.query()
    except:
        pass

    print('Status: ONLINE')
    print('Version:', clean_text(status.version.name))
    print('Protocol:', status.version.protocol)
    print('MOTD:', clean_text(status.description))
    print('Players:', f'{status.players.online}/{status.players.max}')
    print('Latency (ms):', round(status.latency, 1))

    if query:
        print('Software:', clean_text(query.software.version))
        plugins = query.software.plugins
        if plugins:
            plugin_names = [clean_text(p) for p in plugins[:15]]
            print('Plugins ({}):'.format(len(plugins)), ', '.join(plugin_names))
        else:
            print('Plugins: none')
        players = query.players.names
        if players:
            player_names = [clean_text(p) for p in players[:20]]
            print('Online players sample:', ', '.join(player_names))
    else:
        print('Note: Query protocol disabled (no software/player list)')
except Exception as e:
    print('ERROR:', str(e))
    sys.exit(1)
"

    hr
}

cleanup() {
    deactivate 2>/dev/null || true
    exit 0
}

trap cleanup SIGINT SIGTERM

if [ "$WATCH_SECONDS" -gt 0 ]; then
    while true; do
        clear
        run_query
        sleep "$WATCH_SECONDS"
    done
else
    run_query
    deactivate 2>/dev/null || true
fi