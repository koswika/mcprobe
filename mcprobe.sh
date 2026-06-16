#!/bin/bash

set -e

VERSION="1.2.0"

WATCH_SECONDS=0
SERVER=""
PORT="25565"
DISCORD_WEBHOOK=""
DISCORD_NAME=""
DISCORD_AVATAR=""
DISCORD_COLOR=""
JSON_OUTPUT=false
PING_ENABLED=false
ALERT_ENABLED=false
SHORT_OUTPUT=false
FAVICON_PATH=""
NO_GEO=false
NO_DNS=false
MIN_PLAYERS=""
MAX_PLAYERS=""
LOG_FILE=""
TIMEOUT=""
RETRY=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            echo "Usage: $0 <server_address> [port] [options]"
            echo ""
            echo "Options:"
            echo "  --watch N               Refresh every N seconds"
            echo "  --discord WEBHOOK_URL   Send Discord embeds to the given webhook"
            echo "  --discord-name NAME     Custom name for Discord webhook"
            echo "  --discord-avatar URL    Custom avatar URL for Discord webhook"
            echo "  --discord-color HEX     Custom embed color (e.g., 0x00FF00)"
            echo "  --json                  Output raw JSON instead of human-readable text"
            echo "  --ping                  Ping the resolved IP address (3 packets) and show stats"
            echo "  --alert                 With --watch and --discord, send only on status change"
            echo "  --short                 Minimal output: only server, players, latency, MOTD"
            echo "  --favicon [FILE]        Save server favicon as PNG (default: server_icon.png)"
            echo "  --no-geo                Skip geolocation lookup"
            echo "  --no-dns                Skip DNS and SRV lookups"
            echo "  --min-players N         Alert when online players drop below N"
            echo "  --max-players N         Alert when online players exceed N"
            echo "  --log FILE              Append minimal log line to FILE"
            echo "  --timeout N             Set timeout in seconds for mcstatus query (default: 10)"
            echo "  --retry N               Retry N times if connection fails (default: 1)"
            echo "  --version               Show version information and exit"
            echo "  --install               Install this script system-wide (to /usr/local/bin)"
            echo "  --help, -h              Show this help message"
            echo ""
            echo "Example:"
            echo "  $0 play.hypixel.net --watch 10 --discord WEBHOOK --timeout 5 --retry 3"
            exit 0
            ;;
        --version)
            echo "mcprobe version $VERSION"
            exit 0
            ;;
        --watch)
            WATCH_SECONDS="$2"
            shift 2
            ;;
        --discord)
            DISCORD_WEBHOOK="$2"
            shift 2
            ;;
        --discord-name)
            DISCORD_NAME="$2"
            shift 2
            ;;
        --discord-avatar)
            DISCORD_AVATAR="$2"
            shift 2
            ;;
        --discord-color)
            DISCORD_COLOR="$2"
            shift 2
            ;;
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        --ping)
            PING_ENABLED=true
            shift
            ;;
        --alert)
            ALERT_ENABLED=true
            shift
            ;;
        --short)
            SHORT_OUTPUT=true
            shift
            ;;
        --favicon)
            if [[ -n "$2" && "$2" != --* ]]; then
                FAVICON_PATH="$2"
                shift 2
            else
                FAVICON_PATH="server_icon.png"
                shift
            fi
            ;;
        --no-geo)
            NO_GEO=true
            shift
            ;;
        --no-dns)
            NO_DNS=true
            shift
            ;;
        --min-players)
            MIN_PLAYERS="$2"
            shift 2
            ;;
        --max-players)
            MAX_PLAYERS="$2"
            shift 2
            ;;
        --log)
            LOG_FILE="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --retry)
            RETRY="$2"
            shift 2
            ;;
        --install)
            echo "Installing mcprobe to /usr/local/bin..."
            sudo pacman -S --noconfirm python3 bind-tools curl jq || true
            SCRIPT_PATH="$(realpath "$0")"
            sudo cp "$SCRIPT_PATH" /usr/local/bin/mcprobe
            sudo chmod +x /usr/local/bin/mcprobe
            echo "Installation complete. You can now run 'mcprobe' from anywhere."
            exit 0
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
    echo "Error: No server address provided." >&2
    echo "Run '$0 --help' for usage." >&2
    exit 1
fi

if ! command -v python3 &> /dev/null; then
    echo "python3 not found. Installing..."
    sudo pacman -S --noconfirm python3
fi

if ! command -v dig &> /dev/null; then
    echo "dig not found. Installing bind-tools..."
    sudo pacman -S --noconfirm bind-tools
fi

if ! command -v curl &> /dev/null; then
    echo "curl not found. Installing..."
    sudo pacman -S --noconfirm curl
fi

if ! command -v jq &> /dev/null; then
    echo "jq not found. Installing..."
    sudo pacman -S --noconfirm jq
fi

if $PING_ENABLED && ! command -v ping &> /dev/null; then
    echo "ping not found. Installing iputils..."
    sudo pacman -S --noconfirm iputils
fi

VENV_DIR="$HOME/.local/share/mcprobe_venv"
mkdir -p "$(dirname "$VENV_DIR")"

if [ ! -d "$VENV_DIR" ]; then
    echo "Creating virtual environment..." >&2
    python3 -m venv "$VENV_DIR"
fi

source "$VENV_DIR/bin/activate"

if ! python -c "import mcstatus" &> /dev/null; then
    echo "Installing mcstatus..." >&2
    pip install mcstatus > /dev/null
fi

hr() {
    [ "$JSON_OUTPUT" = false ] && echo "============================================================"
}

add_field() {
    local fields="$1"
    local name="$2"
    local value="$3"
    local inline="$4"
    echo "$fields" | jq --arg n "$name" --arg v "$value" --argjson i "$inline" \
        '. + [{"name": $n, "value": $v, "inline": $i}]'
}

send_discord_embed() {
    if [ -z "$DISCORD_WEBHOOK" ] || ! command -v curl &> /dev/null || ! command -v jq &> /dev/null; then
        return
    fi

    local online="$1"
    local version="$2"
    local protocol="$3"
    local motd="$4"
    local players="$5"
    local latency="$6"
    local software="$7"
    local plugins="$8"
    local player_list="$9"
    local dns_a="${10}"
    local dns_cname="${11}"
    local dns_srv="${12}"
    local geo_country="${13}"
    local geo_city="${14}"
    local geo_region="${15}"
    local geo_isp="${16}"
    local error_msg="${17}"
    local ping_stats="${18}"
    local warning_msg="${19}"

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local color title description
    if [ "$online" = "true" ]; then
        if [ -n "$DISCORD_COLOR" ]; then
            color=$((DISCORD_COLOR))
        else
            color=5763719
        fi
        title="$SERVER - ONLINE"
        if [ -n "$warning_msg" ]; then
            title="$title [WARNING]"
            color=16776960
        fi
        description="$(printf 'MOTD\n```\n%s\n```' "$motd")"
    else
        color=15548997
        title="$SERVER - OFFLINE"
        description="$(printf 'The server could not be reached.\n```\n%s\n```' "$error_msg")"
    fi

    local fields='[]'

    if [ "$online" = "true" ]; then
        fields=$(add_field "$fields" "Players" "$players" true)
        fields=$(add_field "$fields" "Latency (Minecraft)" "${latency} ms" true)
        if [ -n "$ping_stats" ]; then
            fields=$(add_field "$fields" "Ping (ICMP)" "$ping_stats" true)
        fi
        if [ -n "$warning_msg" ]; then
            fields=$(add_field "$fields" "⚠️ Alert" "$warning_msg" false)
        fi
        if [ "$SHORT_OUTPUT" = false ]; then
            fields=$(add_field "$fields" "Version" "$version" true)
            fields=$(add_field "$fields" "Protocol" "$protocol" true)
            if [ -n "$software" ]; then
                fields=$(add_field "$fields" "Software" "$software" true)
            fi
            if [ -n "$plugins" ] && [ "$plugins" != "none" ]; then
                fields=$(add_field "$fields" "Plugins" "$plugins" false)
            fi
            if [ -n "$player_list" ]; then
                fields=$(add_field "$fields" "Online Players" "$player_list" false)
            fi
        fi
    fi

    if [ "$SHORT_OUTPUT" = false ] && [ "$NO_DNS" = false ]; then
        local dns_value
        dns_value=""
        [ -n "$dns_a" ]     && dns_value="${dns_value}A: ${dns_a}"$'\n'
        [ -n "$dns_cname" ] && dns_value="${dns_value}CNAME: ${dns_cname}"$'\n'
        [ -n "$dns_srv" ]   && dns_value="${dns_value}SRV: ${dns_srv}"$'\n'
        [ -z "$dns_value" ] && dns_value="No records found"
        dns_value="${dns_value%$'\n'}"
        fields=$(add_field "$fields" "DNS Records" "$dns_value" false)
    fi

    if [ "$SHORT_OUTPUT" = false ] && [ "$NO_GEO" = false ]; then
        if [ -n "$dns_a" ] || [ -n "$geo_country" ]; then
            local geo_value
            geo_value=""
            [ -n "$dns_a" ]       && geo_value="${geo_value}IP: ${dns_a}"$'\n'
            [ -n "$geo_country" ] && geo_value="${geo_value}Country: ${geo_country}"$'\n'
            [ -n "$geo_city" ]    && geo_value="${geo_value}City/Region: ${geo_city}, ${geo_region}"$'\n'
            [ -n "$geo_isp" ]     && geo_value="${geo_value}ISP: ${geo_isp}"$'\n'
            geo_value="${geo_value%$'\n'}"
            fields=$(add_field "$fields" "Server Location" "$geo_value" false)
        fi
    fi

    local payload
    payload=$(jq -n \
        --arg title "$title" \
        --arg description "$description" \
        --argjson color "$color" \
        --argjson fields "$fields" \
        --arg timestamp "$timestamp" \
        --arg footer "mcstatus • $SERVER:$PORT" \
        --arg username "$DISCORD_NAME" \
        --arg avatar_url "$DISCORD_AVATAR" \
        '{
            "embeds": [{
                "title": $title,
                "description": $description,
                "color": $color,
                "fields": $fields,
                "footer": {"text": $footer},
                "timestamp": $timestamp
            }]
        }
        | if $username != "" then .username = $username else . end
        | if $avatar_url != "" then .avatar_url = $avatar_url else . end')

    curl -s -X POST -H "Content-Type: application/json" -d "$payload" "$DISCORD_WEBHOOK" > /dev/null
}

run_query() {
    local dns_a="" dns_cname="" dns_srv=""
    local geo_country="" geo_city="" geo_region="" geo_isp=""
    local ping_stats=""

    if ! $JSON_OUTPUT; then
        if [ "$SHORT_OUTPUT" = false ]; then
            hr
            echo "MINECRAFT SERVER INFORMATION for $SERVER"
            hr
        fi
    fi

    if [ "$SHORT_OUTPUT" = false ] && [ "$NO_DNS" = false ]; then
        if command -v dig &> /dev/null; then
            if ! $JSON_OUTPUT; then
                echo ""
                echo "DNS RECORDS:"
            fi
            dns_a=$(dig +short "$SERVER" A | head -1)
            [ -n "$dns_a" ] && { [ "$JSON_OUTPUT" = false ] && echo "  A record: $dns_a"; }

            dns_cname=$(dig +short "$SERVER" CNAME | head -1)
            [ -n "$dns_cname" ] && { [ "$JSON_OUTPUT" = false ] && echo "  CNAME: $dns_cname"; }

            local srv_raw
            srv_raw=$(dig +short "_minecraft._tcp.$SERVER" SRV)
            if [ -n "$srv_raw" ]; then
                local srv_port srv_target
                srv_port=$(echo "$srv_raw" | awk '{print $3}')
                srv_target=$(echo "$srv_raw" | awk '{print $4}' | sed 's/\.$//')
                dns_srv="port $srv_port -> $srv_target"
                if [ "$JSON_OUTPUT" = false ]; then
                    echo "  SRV: port $srv_port target $srv_target"
                fi
                if [ "$srv_port" != "25565" ]; then
                    PORT="$srv_port"
                    [ "$JSON_OUTPUT" = false ] && echo "  Using SRV port $PORT"
                fi
            else
                [ "$JSON_OUTPUT" = false ] && echo "  No Minecraft SRV record"
            fi
        else
            [ "$JSON_OUTPUT" = false ] && echo "dig not installed, skipping DNS lookup"
        fi
    fi

    if [ "$SHORT_OUTPUT" = false ] && [ "$NO_GEO" = false ]; then
        if [ -n "$dns_a" ] && command -v curl &> /dev/null; then
            if ! $JSON_OUTPUT; then
                echo ""
                echo "GEOLOCATION OF SERVER IP ($dns_a):"
            fi
            local geo
            geo=$(curl -s "http://ip-api.com/json/$dns_a?fields=status,country,city,regionName,isp")
            if echo "$geo" | grep -q '"status":"success"'; then
                geo_country=$(echo "$geo" | sed -n 's/.*"country":"\([^"]*\)".*/\1/p')
                geo_city=$(echo "$geo" | sed -n 's/.*"city":"\([^"]*\)".*/\1/p')
                geo_region=$(echo "$geo" | sed -n 's/.*"regionName":"\([^"]*\)".*/\1/p')
                geo_isp=$(echo "$geo" | sed -n 's/.*"isp":"\([^"]*\)".*/\1/p')
                if ! $JSON_OUTPUT; then
                    echo "  Country: ${geo_country:-unknown}"
                    echo "  City/Region: ${geo_city:-unknown}, ${geo_region:-unknown}"
                    echo "  ISP/Organization: ${geo_isp:-unknown}"
                fi
            else
                [ "$JSON_OUTPUT" = false ] && echo "  Geolocation query failed."
            fi
        fi
    fi

    if $PING_ENABLED && [ -n "$dns_a" ] && command -v ping &> /dev/null; then
        if ! $JSON_OUTPUT; then
            echo ""
            echo "PING TO SERVER IP ($dns_a):"
        fi
        local ping_output
        ping_output=$(ping -c 3 -W 1 "$dns_a" 2>/dev/null)
        local packet_loss=$(echo "$ping_output" | grep -oP '\d+(?=% packet loss)' | head -1)
        if [ -n "$packet_loss" ] && [ "$packet_loss" -eq 100 ]; then
            ping_stats="100% packet loss (host unreachable)"
            if ! $JSON_OUTPUT; then
                echo "  $ping_stats"
            fi
        else
            local rtt_min=$(echo "$ping_output" | grep "rtt min/avg/max/mdev" | awk -F'/' '{print $4}')
            local rtt_avg=$(echo "$ping_output" | grep "rtt min/avg/max/mdev" | awk -F'/' '{print $5}')
            local rtt_max=$(echo "$ping_output" | grep "rtt min/avg/max/mdev" | awk -F'/' '{print $6}')
            if [ -n "$rtt_avg" ]; then
                ping_stats="min=${rtt_min} ms, avg=${rtt_avg} ms, max=${rtt_max} ms"
            else
                ping_stats="ping completed but no RTT data"
            fi
            if ! $JSON_OUTPUT; then
                echo "  $ping_stats"
            fi
        fi
    fi

    if ! $JSON_OUTPUT; then
        echo ""
        echo "SERVER STATUS ($SERVER:$PORT)"
        echo "-----------------------------"
    fi

    local timeout_arg="${TIMEOUT:-10}"
    local retry_arg="${RETRY:-1}"

    local status_output
    if [ "$SHORT_OUTPUT" = true ]; then
        status_output=$(python3 -c "
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

def query_server():
    server = JavaServer.lookup('$SERVER:$PORT')
    status = server.status(timeout=$timeout_arg)
    print('Status: ONLINE')
    print('Version:', clean_text(status.version.name))
    print('MOTD:', clean_text(status.description))
    print('Players:', f'{status.players.online}/{status.players.max}')
    print('Latency (ms):', round(status.latency, 1))
    if hasattr(status, 'favicon') and status.favicon:
        print('FAVICON:', status.favicon)

retry_count = $retry_arg
for attempt in range(retry_count):
    try:
        query_server()
        break
    except Exception as e:
        if attempt == retry_count - 1:
            print('Status: OFFLINE')
            print('ERROR:', str(e))
            sys.exit(1)
        time.sleep(1)
")
    else
        status_output=$(python3 -c "
import sys, re, json, time
from mcstatus import JavaServer

def clean_text(text):
    if not isinstance(text, str):
        return str(text)
    text = re.sub(r'§[0-9a-fklmnor]', '', text)
    text = re.sub(r'<[^>]+>', '', text)
    text = re.sub(r'[\x00-\x1f\x7f]', '', text)
    text = re.sub(r'\s+', ' ', text)
    return text.strip()

def query_server():
    server = JavaServer.lookup('$SERVER:$PORT')
    status = server.status(timeout=$timeout_arg)
    query = None
    try:
        query = server.query(timeout=$timeout_arg)
    except:
        pass

    print('Status: ONLINE')
    print('Version:', clean_text(status.version.name))
    print('Protocol:', status.version.protocol)
    print('MOTD:', clean_text(status.description))
    print('Players:', f'{status.players.online}/{status.players.max}')
    print('Latency (ms):', round(status.latency, 1))
    if hasattr(status, 'favicon') and status.favicon:
        print('FAVICON:', status.favicon)

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

retry_count = $retry_arg
for attempt in range(retry_count):
    try:
        query_server()
        break
    except Exception as e:
        if attempt == retry_count - 1:
            print('Status: OFFLINE')
            print('ERROR:', str(e))
            sys.exit(1)
        time.sleep(1)
")
    fi

    if ! $JSON_OUTPUT; then
        echo "$status_output"
        hr
    fi

    if [ -n "$FAVICON_PATH" ]; then
        local favicon_b64
        favicon_b64=$(echo "$status_output" | grep "^FAVICON:" | sed 's/^FAVICON: //')
        if [ -n "$favicon_b64" ]; then
            echo "$favicon_b64" | base64 -d > "$FAVICON_PATH" 2>/dev/null
            if [ $? -eq 0 ]; then
                echo "Favicon saved to $FAVICON_PATH" >&2
            else
                echo "Failed to decode favicon" >&2
            fi
        else
            echo "No favicon available for this server" >&2
        fi
    fi

    local current_status=""
    if echo "$status_output" | grep -q "^Status: ONLINE"; then
        current_status="ONLINE"
    else
        current_status="OFFLINE"
    fi

    local online_players=""
    local latency_value=""
    local version_value=""
    if [ "$current_status" = "ONLINE" ]; then
        local players_line
        players_line=$(echo "$status_output" | grep "^Players:" | head -1)
        if [ -n "$players_line" ]; then
            online_players=$(echo "$players_line" | sed -E 's/.* ([0-9]+)\/[0-9]+$/\1/')
        fi
        local latency_line
        latency_line=$(echo "$status_output" | grep "^Latency (ms):" | head -1)
        if [ -n "$latency_line" ]; then
            latency_value=$(echo "$latency_line" | sed 's/^Latency (ms): //')
        fi
        local version_line
        version_line=$(echo "$status_output" | grep "^Version:" | head -1)
        if [ -n "$version_line" ]; then
            version_value=$(echo "$version_line" | sed 's/^Version: //')
        fi
    fi

    local warning_msg=""
    if [ "$current_status" = "ONLINE" ] && [ -n "$online_players" ]; then
        if [ -n "$MIN_PLAYERS" ] && [ "$online_players" -lt "$MIN_PLAYERS" ]; then
            warning_msg="Player count ($online_players) is below minimum ($MIN_PLAYERS)"
        elif [ -n "$MAX_PLAYERS" ] && [ "$online_players" -gt "$MAX_PLAYERS" ]; then
            warning_msg="Player count ($online_players) exceeds maximum ($MAX_PLAYERS)"
        fi
        if [ -n "$warning_msg" ] && ! $JSON_OUTPUT; then
            echo "WARNING: $warning_msg" >&2
        fi
    fi

    if [ -n "$LOG_FILE" ]; then
        local timestamp
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        local log_line="$timestamp | $SERVER:$PORT | $current_status"
        if [ "$current_status" = "ONLINE" ]; then
            log_line="$log_line | players: $online_players | latency: ${latency_value}ms | version: $version_value"
            if [ -n "$warning_msg" ]; then
                log_line="$log_line | alert: $warning_msg"
            fi
        else
            local error_msg
            error_msg=$(echo "$status_output" | grep "^ERROR:" | sed 's/^ERROR: //' | head -1)
            log_line="$log_line | error: $error_msg"
        fi
        echo "$log_line" >> "$LOG_FILE" 2>/dev/null || echo "Warning: Could not write to log file $LOG_FILE" >&2
    fi

    local should_send=true
    if [ "$ALERT_ENABLED" = true ] && [ -n "$DISCORD_WEBHOOK" ]; then
        local status_file="/tmp/mcprobe_status_${SERVER}_${PORT}"
        local last_status=""
        if [ -f "$status_file" ]; then
            last_status=$(cat "$status_file")
        fi
        if [ "$current_status" = "$last_status" ]; then
            should_send=false
        else
            echo "$current_status" > "$status_file"
        fi
    fi

    if [ -n "$DISCORD_WEBHOOK" ] && [ "$should_send" = true ]; then
        local s_version s_protocol s_motd s_players s_latency s_software s_plugins s_player_list s_error

        s_version=$(echo "$status_output"     | grep "^Version:"            | sed 's/^Version: //')
        s_protocol=$(echo "$status_output"    | grep "^Protocol:"           | sed 's/^Protocol: //')
        s_motd=$(echo "$status_output"        | grep "^MOTD:"               | sed 's/^MOTD: //')
        s_players=$(echo "$status_output"     | grep "^Players:"            | sed 's/^Players: //')
        s_latency=$(echo "$status_output"     | grep "^Latency (ms):"       | sed 's/^Latency (ms): //')
        s_software=$(echo "$status_output"    | grep "^Software:"           | sed 's/^Software: //')
        s_plugins=$(echo "$status_output"     | grep "^Plugins"             | sed 's/^Plugins[^:]*: //')
        s_player_list=$(echo "$status_output" | grep "^Online players sample:" | sed 's/^Online players sample: //')
        s_error=$(echo "$status_output"       | grep "^ERROR:"              | sed 's/^ERROR: //')

        if [ "$current_status" = "ONLINE" ]; then
            send_discord_embed "true" \
                "$s_version" "$s_protocol" "$s_motd" "$s_players" "$s_latency" \
                "$s_software" "$s_plugins" "$s_player_list" \
                "$dns_a" "$dns_cname" "$dns_srv" \
                "$geo_country" "$geo_city" "$geo_region" "$geo_isp" "" "$ping_stats" "$warning_msg"
        else
            send_discord_embed "false" \
                "" "" "" "" "" "" "" "" \
                "$dns_a" "$dns_cname" "$dns_srv" \
                "$geo_country" "$geo_city" "$geo_region" "$geo_isp" "$s_error" "$ping_stats" ""
        fi
    fi

    if $JSON_OUTPUT; then
        local status_line=$(echo "$status_output" | grep "^Status:" | sed 's/^Status: //')
        local version_line=$(echo "$status_output" | grep "^Version:" | sed 's/^Version: //')
        local motd_line=$(echo "$status_output" | grep "^MOTD:" | sed 's/^MOTD: //')
        local players_line=$(echo "$status_output" | grep "^Players:" | sed 's/^Players: //')
        local latency_line=$(echo "$status_output" | grep "^Latency (ms):" | sed 's/^Latency (ms): //')
        local favicon_line=$(echo "$status_output" | grep "^FAVICON:" | sed 's/^FAVICON: //')

        if [ "$SHORT_OUTPUT" = false ]; then
            local protocol_line=$(echo "$status_output" | grep "^Protocol:" | sed 's/^Protocol: //')
            local software_line=$(echo "$status_output" | grep "^Software:" | sed 's/^Software: //')
            local plugins_line=$(echo "$status_output" | grep "^Plugins" | sed 's/^Plugins[^:]*: //')
            local player_sample_line=$(echo "$status_output" | grep "^Online players sample:" | sed 's/^Online players sample: //')
            local error_line=$(echo "$status_output" | grep "^ERROR:" | sed 's/^ERROR: //')
            jq -n \
                --arg server "$SERVER" \
                --arg port "$PORT" \
                --arg status "$status_line" \
                --arg version "$version_line" \
                --arg protocol "$protocol_line" \
                --arg motd "$motd_line" \
                --arg players "$players_line" \
                --arg latency "$latency_line" \
                --arg software "$software_line" \
                --arg plugins "$plugins_line" \
                --arg player_sample "$player_sample_line" \
                --arg error "$error_line" \
                --arg dns_a "$dns_a" \
                --arg dns_cname "$dns_cname" \
                --arg dns_srv "$dns_srv" \
                --arg geo_country "$geo_country" \
                --arg geo_city "$geo_city" \
                --arg geo_region "$geo_region" \
                --arg geo_isp "$geo_isp" \
                --arg ping "$ping_stats" \
                --arg favicon "$favicon_line" \
                --arg alert "$warning_msg" \
                '{
                    "server": $server,
                    "port": $port,
                    "status": $status,
                    "version": $version,
                    "protocol": $protocol,
                    "motd": $motd,
                    "players": $players,
                    "latency_ms": ($latency | tonumber? // null),
                    "software": $software,
                    "plugins": $plugins,
                    "player_sample": $player_sample,
                    "error": $error,
                    "favicon_base64": $favicon,
                    "alert": $alert,
                    "dns": {
                        "a": $dns_a,
                        "cname": $dns_cname,
                        "srv": $dns_srv
                    },
                    "geolocation": {
                        "country": $geo_country,
                        "city": $geo_city,
                        "region": $geo_region,
                        "isp": $geo_isp
                    },
                    "ping_stats": $ping
                }'
        else
            local error_line=$(echo "$status_output" | grep "^ERROR:" | sed 's/^ERROR: //')
            jq -n \
                --arg server "$SERVER" \
                --arg port "$PORT" \
                --arg status "$status_line" \
                --arg version "$version_line" \
                --arg motd "$motd_line" \
                --arg players "$players_line" \
                --arg latency "$latency_line" \
                --arg error "$error_line" \
                --arg ping "$ping_stats" \
                --arg favicon "$favicon_line" \
                --arg alert "$warning_msg" \
                '{
                    "server": $server,
                    "port": $port,
                    "status": $status,
                    "version": $version,
                    "motd": $motd,
                    "players": $players,
                    "latency_ms": ($latency | tonumber? // null),
                    "error": $error,
                    "favicon_base64": $favicon,
                    "alert": $alert,
                    "ping_stats": $ping
                }'
        fi
    fi
}

cleanup() {
    deactivate 2>/dev/null || true
    exit 0
}

trap cleanup SIGINT SIGTERM

if [ "$JSON_OUTPUT" = true ] && [ "$WATCH_SECONDS" -gt 0 ]; then
    while true; do
        run_query
        sleep "$WATCH_SECONDS"
    done
elif [ "$WATCH_SECONDS" -gt 0 ]; then
    while true; do
        clear
        run_query
        sleep "$WATCH_SECONDS"
    done
else
    run_query
    deactivate 2>/dev/null || true
fi