#!/bin/bash
set -e

VERSION="1.3.0"

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
RETRY_DELAY=""
OUTPUT_FILE=""
CSV_FILE=""
NO_CLEAR=false
NO_AUTO_INSTALL=false
QUIET=false
BEDROCK=false
PORT_SET=false

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

err() { echo "$@" >&2; }

is_uint() {
    # Returns 0 if $1 is a non-negative integer
    [[ "$1" =~ ^[0-9]+$ ]]
}

while [[ $# -gt 0 ]]; do
case $1 in
    --help|-h)
        echo "Usage: $0 <server_address> [port] [options]"
        echo ""
        echo "Options:"
        echo "  --watch N              Refresh every N seconds"
        echo "  --discord WEBHOOK_URL  Send Discord embeds to the given webhook"
        echo "  --discord-name NAME    Custom name for Discord webhook"
        echo "  --discord-avatar URL   Custom avatar URL for Discord webhook"
        echo "  --discord-color HEX    Custom embed color (e.g., 0x00FF00)"
        echo "  --json                 Output raw JSON instead of human-readable text"
        echo "  --ping                 Ping the resolved IP address (3 packets) and show stats"
        echo "  --alert                With --watch and --discord, send only on status change"
        echo "  --short                Minimal output: only server, players, latency, MOTD"
        echo "  --favicon [FILE]       Save server favicon as PNG (default: server_icon.png)"
        echo "  --bedrock              Query a Bedrock (Pocket/Win10) server instead of Java"
        echo "  --no-geo               Skip geolocation lookup"
        echo "  --no-dns               Skip DNS and SRV lookups"
        echo "  --no-clear             In watch mode, do not clear screen (scroll output)"
        echo "  --no-auto-install      Never auto-install missing dependencies, just error out"
        echo "  --quiet                Suppress informational/status messages on stderr"
        echo "  --min-players N        Alert when online players drop below N"
        echo "  --max-players N        Alert when online players exceed N"
        echo "  --log FILE             Append minimal log line to FILE"
        echo "  --csv FILE             Append CSV data to FILE"
        echo "  --timeout N            Set timeout in seconds for mcstatus query (default: 10)"
        echo "  --retry N              Retry N times if connection fails (default: 1)"
        echo "  --retry-delay N        Seconds to wait between retries (default: 1)"
        echo "  --output FILE          Save output to FILE instead of stdout"
        echo "  --version              Show version information and exit"
        echo "  --install              Install this script system-wide (to /usr/local/bin)"
        echo "  --help, -h             Show this help message"
        echo ""
        echo "Example:"
        echo "  $0 play.hypixel.net --watch 10 --no-clear"
        exit 0
        ;;
    --version)
        echo "mcprobe version $VERSION"
        exit 0
        ;;
    --watch)
        WATCH_SECONDS="$2"
        if ! is_uint "$WATCH_SECONDS"; then
            err "Error: --watch requires a non-negative integer (got '$WATCH_SECONDS')"
            exit 1
        fi
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
    --bedrock)
        BEDROCK=true
        if [ "$PORT_SET" = false ]; then
            PORT="19132"
        fi
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
    --no-clear)
        NO_CLEAR=true
        shift
        ;;
    --no-auto-install)
        NO_AUTO_INSTALL=true
        shift
        ;;
    --quiet)
        QUIET=true
        shift
        ;;
    --min-players)
        MIN_PLAYERS="$2"
        if ! is_uint "$MIN_PLAYERS"; then
            err "Error: --min-players requires a non-negative integer"
            exit 1
        fi
        shift 2
        ;;
    --max-players)
        MAX_PLAYERS="$2"
        if ! is_uint "$MAX_PLAYERS"; then
            err "Error: --max-players requires a non-negative integer"
            exit 1
        fi
        shift 2
        ;;
    --log)
        LOG_FILE="$2"
        shift 2
        ;;
    --csv)
        CSV_FILE="$2"
        shift 2
        ;;
    --timeout)
        TIMEOUT="$2"
        if ! is_uint "$TIMEOUT" || [ "$TIMEOUT" -eq 0 ]; then
            err "Error: --timeout requires a positive integer"
            exit 1
        fi
        shift 2
        ;;
    --retry)
        RETRY="$2"
        if ! is_uint "$RETRY" || [ "$RETRY" -eq 0 ]; then
            err "Error: --retry requires a positive integer"
            exit 1
        fi
        shift 2
        ;;
    --retry-delay)
        RETRY_DELAY="$2"
        if ! is_uint "$RETRY_DELAY"; then
            err "Error: --retry-delay requires a non-negative integer"
            exit 1
        fi
        shift 2
        ;;
    --output)
        OUTPUT_FILE="$2"
        shift 2
        ;;
    --install)
        echo "Installing mcprobe to /usr/local/bin..."
        SCRIPT_PATH="$(realpath "$0")"
        sudo cp "$SCRIPT_PATH" /usr/local/bin/mcprobe
        sudo chmod +x /usr/local/bin/mcprobe
        echo "Installation complete. You can now run 'mcprobe' from anywhere."
        echo "(Dependencies will be checked/installed automatically on first run.)"
        exit 0
        ;;
    --*)
        err "Error: Unknown option '$1'"
        err "Run '$0 --help' for usage."
        exit 1
        ;;
    *)
        if [ -z "$SERVER" ]; then
            SERVER="$1"
        elif [ "$PORT_SET" = false ]; then
            PORT="$1"
            PORT_SET=true
        else
            err "Error: Unexpected extra argument '$1'"
            exit 1
        fi
        shift
        ;;
esac
done

if [ -z "$SERVER" ]; then
    err "Error: No server address provided."
    err "Run '$0 --help' for usage."
    exit 1
fi

if ! is_uint "$PORT" || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
    err "Error: Port must be an integer between 1 and 65535 (got '$PORT')."
    exit 1
fi

# ---------------------------------------------------------------------------
# Dependency installation (distro-agnostic, with opt-out)
# ---------------------------------------------------------------------------

PKG_INSTALL_CMD=""
detect_pkg_manager() {
    if command -v apt-get &> /dev/null; then
        PKG_INSTALL_CMD="sudo apt-get install -y"
    elif command -v dnf &> /dev/null; then
        PKG_INSTALL_CMD="sudo dnf install -y"
    elif command -v yum &> /dev/null; then
        PKG_INSTALL_CMD="sudo yum install -y"
    elif command -v pacman &> /dev/null; then
        PKG_INSTALL_CMD="sudo pacman -S --noconfirm"
    elif command -v zypper &> /dev/null; then
        PKG_INSTALL_CMD="sudo zypper install -y"
    elif command -v apk &> /dev/null; then
        PKG_INSTALL_CMD="sudo apk add"
    elif command -v brew &> /dev/null; then
        PKG_INSTALL_CMD="brew install"
    fi
}

# Maps a logical dependency name to the package name for the detected manager
pkg_name_for() {
    local dep="$1"
    case "$PKG_INSTALL_CMD" in
        *apt-get*) case "$dep" in dig) echo "dnsutils";; ping) echo "iputils-ping";; *) echo "$dep";; esac ;;
        *dnf*|*yum*|*zypper*) case "$dep" in dig) echo "bind-utils";; ping) echo "iputils";; *) echo "$dep";; esac ;;
        *pacman*) case "$dep" in dig) echo "bind-tools";; ping) echo "iputils";; *) echo "$dep";; esac ;;
        *apk*) case "$dep" in dig) echo "bind-tools";; ping) echo "iputils";; *) echo "$dep";; esac ;;
        *brew*) case "$dep" in dig) echo "bind";; *) echo "$dep";; esac ;;
        *) echo "$dep" ;;
    esac
}

ensure_dep() {
    local cmd="$1" dep="$2"
    if command -v "$cmd" &> /dev/null; then
        return 0
    fi
    if [ "$NO_AUTO_INSTALL" = true ]; then
        err "Error: required dependency '$cmd' not found and --no-auto-install was set."
        exit 1
    fi
    if [ -z "$PKG_INSTALL_CMD" ]; then
        err "Error: '$cmd' not found and no supported package manager was detected."
        err "Please install '$cmd' manually."
        exit 1
    fi
    local pkg
    pkg=$(pkg_name_for "$dep")
    [ "$QUIET" = false ] && err "$cmd not found. Installing $pkg..."
    $PKG_INSTALL_CMD "$pkg" || {
        err "Error: failed to install '$pkg'. Please install it manually."
        exit 1
    }
}

detect_pkg_manager
ensure_dep python3 python3
ensure_dep dig dig
ensure_dep curl curl
ensure_dep jq jq
if $PING_ENABLED; then
    ensure_dep ping ping
fi

VENV_DIR="$HOME/.local/share/mcprobe_venv"
mkdir -p "$(dirname "$VENV_DIR")"
if [ ! -d "$VENV_DIR" ]; then
    [ "$QUIET" = false ] && err "Creating virtual environment..."
    python3 -m venv "$VENV_DIR"
fi
# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"
if ! python -c "import mcstatus" &> /dev/null; then
    [ "$QUIET" = false ] && err "Installing mcstatus..."
    pip install --upgrade pip > /dev/null 2>&1 || true
    pip install mcstatus > /dev/null
fi

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

hr() {
    [ "$JSON_OUTPUT" = false ] && echo "============================================================"
}

add_field() {
    local fields="$1" name="$2" value="$3" inline="$4"
    echo "$fields" | jq --arg n "$name" --arg v "$value" --argjson i "$inline" \
        '. + [{"name": $n, "value": $v, "inline": $i}]'
}

send_discord_embed() {
    if [ -z "$DISCORD_WEBHOOK" ] || ! command -v curl &> /dev/null || ! command -v jq &> /dev/null; then
        return
    fi
    local online="$1" version="$2" protocol="$3" motd="$4" players="$5" latency="$6"
    local software="$7" plugins="$8" player_list="$9"
    local dns_a="${10}" dns_cname="${11}" dns_srv="${12}"
    local geo_country="${13}" geo_city="${14}" geo_region="${15}" geo_isp="${16}"
    local error_msg="${17}" ping_stats="${18}" warning_msg="${19}"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local color title description
    if [ "$online" = "true" ]; then
        if [ -n "$DISCORD_COLOR" ]; then
            # Validate it looks like a hex/decimal number before doing arithmetic,
            # so a bad value can't abort the whole run under `set -e`.
            if [[ "$DISCORD_COLOR" =~ ^(0x)?[0-9A-Fa-f]+$ ]]; then
                color=$((DISCORD_COLOR))
            else
                err "Warning: invalid --discord-color '$DISCORD_COLOR', using default."
                color=5763719
            fi
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
            if [ -n "$protocol" ]; then
                fields=$(add_field "$fields" "Protocol" "$protocol" true)
            fi
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
        local dns_value=""
        [ -n "$dns_a" ] && dns_value="${dns_value}A: ${dns_a}"$'\n'
        [ -n "$dns_cname" ] && dns_value="${dns_value}CNAME: ${dns_cname}"$'\n'
        [ -n "$dns_srv" ] && dns_value="${dns_value}SRV: ${dns_srv}"$'\n'
        [ -z "$dns_value" ] && dns_value="No records found"
        dns_value="${dns_value%$'\n'}"
        fields=$(add_field "$fields" "DNS Records" "$dns_value" false)
    fi

    if [ "$SHORT_OUTPUT" = false ] && [ "$NO_GEO" = false ]; then
        if [ -n "$dns_a" ] || [ -n "$geo_country" ]; then
            local geo_value=""
            [ -n "$dns_a" ] && geo_value="${geo_value}IP: ${dns_a}"$'\n'
            [ -n "$geo_country" ] && geo_value="${geo_value}Country: ${geo_country}"$'\n'
            [ -n "$geo_city" ] && geo_value="${geo_value}City/Region: ${geo_city}, ${geo_region}"$'\n'
            [ -n "$geo_isp" ] && geo_value="${geo_value}ISP: ${geo_isp}"$'\n'
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
        --arg footer "mcprobe • $SERVER:$PORT" \
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

    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" -d "$payload" "$DISCORD_WEBHOOK")
    if [[ "$http_code" != 2* ]]; then
        err "Warning: Discord webhook returned HTTP $http_code"
    fi
}

run_query() {
    local dns_a="" dns_cname="" dns_srv=""
    local geo_country="" geo_city="" geo_region="" geo_isp=""
    local ping_stats=""

    if ! $JSON_OUTPUT && [ "$SHORT_OUTPUT" = false ]; then
        hr
        echo "MINECRAFT SERVER INFORMATION for $SERVER"
        hr
    fi

    if [ "$SHORT_OUTPUT" = false ] && [ "$NO_DNS" = false ]; then
        if command -v dig &> /dev/null; then
            if ! $JSON_OUTPUT; then
                echo ""
                echo "DNS RECORDS:"
            fi
            dns_a=$(dig +short "$SERVER" A | head -1)
            [ -n "$dns_a" ] && { [ "$JSON_OUTPUT" = false ] && echo "  A record: $dns_a"; }

            local dns_aaaa
            dns_aaaa=$(dig +short "$SERVER" AAAA | head -1)
            [ -n "$dns_aaaa" ] && { [ "$JSON_OUTPUT" = false ] && echo "  AAAA record: $dns_aaaa"; }

            dns_cname=$(dig +short "$SERVER" CNAME | head -1)
            [ -n "$dns_cname" ] && { [ "$JSON_OUTPUT" = false ] && echo "  CNAME: $dns_cname"; }

            if ! $BEDROCK; then
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
                    if [ "$PORT_SET" = false ] && [ "$srv_port" != "25565" ]; then
                        PORT="$srv_port"
                        [ "$JSON_OUTPUT" = false ] && echo "  Using SRV port $PORT"
                    fi
                else
                    [ "$JSON_OUTPUT" = false ] && echo "  No Minecraft SRV record"
                fi
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
            geo=$(curl -s --max-time 8 "http://ip-api.com/json/$dns_a?fields=status,country,city,regionName,isp")
            if echo "$geo" | grep -q '"status":"success"'; then
                geo_country=$(echo "$geo" | jq -r '.country // empty')
                geo_city=$(echo "$geo" | jq -r '.city // empty')
                geo_region=$(echo "$geo" | jq -r '.regionName // empty')
                geo_isp=$(echo "$geo" | jq -r '.isp // empty')
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
        ping_output=$(ping -c 3 -W 1 "$dns_a" 2>/dev/null || true)

        local packet_loss
        packet_loss=$(echo "$ping_output" | sed -n 's/.* \([0-9]\{1,3\}\)% packet loss.*/\1/p' | head -1)
        if [ -n "$packet_loss" ] && [ "$packet_loss" -eq 100 ] 2>/dev/null; then
            ping_stats="100% packet loss (host unreachable)"
            if ! $JSON_OUTPUT; then
                echo "  $ping_stats"
            fi
        else
            local rtt_line
            rtt_line=$(echo "$ping_output" | grep "rtt min/avg/max" || echo "$ping_output" | grep "round-trip min/avg/max" || true)
            local rtt_min rtt_avg rtt_max
            rtt_min=$(echo "$rtt_line" | awk -F'/' '{print $4}')
            rtt_avg=$(echo "$rtt_line" | awk -F'/' '{print $5}')
            rtt_max=$(echo "$rtt_line" | awk -F'/' '{print $6}')
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
    local retry_delay_arg="${RETRY_DELAY:-1}"

    # IMPORTANT: SERVER/PORT are passed through environment variables (not
    # interpolated into the Python source string) so that special characters
    # such as quotes in a malicious/unexpected hostname cannot break out of
    # the string literal and inject arbitrary Python code.
    local status_output
    status_output=$(MCPROBE_SERVER="$SERVER" MCPROBE_PORT="$PORT" \
        MCPROBE_TIMEOUT="$timeout_arg" MCPROBE_RETRY="$retry_arg" \
        MCPROBE_RETRY_DELAY="$retry_delay_arg" MCPROBE_SHORT="$SHORT_OUTPUT" \
        MCPROBE_BEDROCK="$BEDROCK" python3 - <<'PYEOF'
import os, sys, re, time

server = os.environ["MCPROBE_SERVER"]
port = os.environ["MCPROBE_PORT"]
timeout = float(os.environ["MCPROBE_TIMEOUT"])
retry_count = int(os.environ["MCPROBE_RETRY"])
retry_delay = float(os.environ["MCPROBE_RETRY_DELAY"])
short = os.environ.get("MCPROBE_SHORT", "false") == "true"
bedrock = os.environ.get("MCPROBE_BEDROCK", "false") == "true"

def clean_text(text):
    if not isinstance(text, str):
        return str(text)
    text = re.sub(r'§[0-9a-fklmnor]', '', text)
    text = re.sub(r'<[^>]+>', '', text)
    text = re.sub(r'[\x00-\x1f\x7f]', '', text)
    text = re.sub(r'\s+', ' ', text)
    return text.strip()

def query_bedrock():
    from mcstatus import BedrockServer
    bserver = BedrockServer.lookup(f"{server}:{port}")
    status = bserver.status(tries=1)
    print('Status: ONLINE')
    print('Version:', clean_text(getattr(status.version, 'version', 'unknown')))
    print('MOTD:', clean_text(status.motd))
    print('Players:', f'{status.players_online}/{status.players_max}')
    print('Latency (ms):', round(status.latency, 1))

def query_java():
    from mcstatus import JavaServer
    jserver = JavaServer.lookup(f"{server}:{port}")
    status = jserver.status(timeout=timeout)
    query = None
    if not short:
        try:
            query = jserver.query(timeout=timeout)
        except Exception:
            pass

    print('Status: ONLINE')
    print('Version:', clean_text(status.version.name))
    if not short:
        print('Protocol:', status.version.protocol)
    print('MOTD:', clean_text(status.description))
    print('Players:', f'{status.players.online}/{status.players.max}')
    print('Latency (ms):', round(status.latency, 1))
    if getattr(status, 'favicon', None):
        print('FAVICON:', status.favicon)

    if not short:
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

def query_server():
    if bedrock:
        query_bedrock()
    else:
        query_java()

last_err = None
for attempt in range(retry_count):
    try:
        query_server()
        break
    except Exception as e:
        last_err = e
        if attempt == retry_count - 1:
            print('Status: OFFLINE')
            print('ERROR:', str(e))
            sys.exit(1)
        time.sleep(retry_delay)
PYEOF
)

    if ! $JSON_OUTPUT; then
        echo "$status_output"
        hr
    fi

    if [ -n "$FAVICON_PATH" ]; then
        local favicon_b64
        favicon_b64=$(echo "$status_output" | grep "^FAVICON:" | sed 's/^FAVICON: //')
        if [ -n "$favicon_b64" ]; then
            if echo "$favicon_b64" | sed 's/^data:image\/png;base64,//' | base64 -d > "$FAVICON_PATH" 2>/dev/null; then
                [ "$QUIET" = false ] && err "Favicon saved to $FAVICON_PATH"
            else
                err "Failed to decode favicon"
            fi
        else
            [ "$QUIET" = false ] && err "No favicon available for this server"
        fi
    fi

    local current_status="OFFLINE"
    echo "$status_output" | grep -q "^Status: ONLINE" && current_status="ONLINE"

    local online_players="" max_players="" latency_value="" version_value=""
    if [ "$current_status" = "ONLINE" ]; then
        local players_line
        players_line=$(echo "$status_output" | grep "^Players:" | head -1)
        if [ -n "$players_line" ]; then
            online_players=$(echo "$players_line" | sed -E 's/.* ([0-9]+)\/([0-9]+)$/\1/')
            max_players=$(echo "$players_line" | sed -E 's/.* ([0-9]+)\/([0-9]+)$/\2/')
        fi
        local latency_line
        latency_line=$(echo "$status_output" | grep "^Latency (ms):" | head -1)
        [ -n "$latency_line" ] && latency_value=$(echo "$latency_line" | sed 's/^Latency (ms): //')
        local version_line
        version_line=$(echo "$status_output" | grep "^Version:" | head -1)
        [ -n "$version_line" ] && version_value=$(echo "$version_line" | sed 's/^Version: //')
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
            [ -n "$warning_msg" ] && log_line="$log_line | alert: $warning_msg"
        else
            local error_msg
            error_msg=$(echo "$status_output" | grep "^ERROR:" | sed 's/^ERROR: //' | head -1)
            log_line="$log_line | error: $error_msg"
        fi
        echo "$log_line" >> "$LOG_FILE" 2>/dev/null || err "Warning: Could not write to log file $LOG_FILE"
    fi

    if [ -n "$CSV_FILE" ]; then
        local csv_timestamp
        csv_timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        if [ ! -f "$CSV_FILE" ]; then
            echo "timestamp,server,port,status,players,max_players,latency_ms,version,alert" > "$CSV_FILE"
        fi
        local csv_alert="${warning_msg:-}"
        echo "$csv_timestamp,$SERVER,$PORT,$current_status,${online_players:-},${max_players:-},${latency_value:-},${version_value:-},\"$csv_alert\"" >> "$CSV_FILE" 2>/dev/null || err "Warning: Could not write to CSV file $CSV_FILE"
    fi

    local should_send=true
    if [ "$ALERT_ENABLED" = true ] && [ -n "$DISCORD_WEBHOOK" ]; then
        local status_key
        status_key=$(echo -n "${SERVER}:${PORT}" | md5sum | cut -d' ' -f1)
        local status_file="${TMPDIR:-/tmp}/mcprobe_status_${status_key}"
        local last_status=""
        [ -f "$status_file" ] && last_status=$(cat "$status_file")
        if [ "$current_status" = "$last_status" ]; then
            should_send=false
        else
            echo "$current_status" > "$status_file"
        fi
    fi

    if [ -n "$DISCORD_WEBHOOK" ] && [ "$should_send" = true ]; then
        local s_version s_protocol s_motd s_players s_latency s_software s_plugins s_player_list s_error
        s_version=$(echo "$status_output" | grep "^Version:" | sed 's/^Version: //')
        s_protocol=$(echo "$status_output" | grep "^Protocol:" | sed 's/^Protocol: //')
        s_motd=$(echo "$status_output" | grep "^MOTD:" | sed 's/^MOTD: //')
        s_players=$(echo "$status_output" | grep "^Players:" | sed 's/^Players: //')
        s_latency=$(echo "$status_output" | grep "^Latency (ms):" | sed 's/^Latency (ms): //')
        s_software=$(echo "$status_output" | grep "^Software:" | sed 's/^Software: //')
        s_plugins=$(echo "$status_output" | grep "^Plugins" | sed 's/^Plugins[^:]*: //')
        s_player_list=$(echo "$status_output" | grep "^Online players sample:" | sed 's/^Online players sample: //')
        s_error=$(echo "$status_output" | grep "^ERROR:" | sed 's/^ERROR: //')

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
        local status_line version_line motd_line players_line latency_line favicon_line
        status_line=$(echo "$status_output" | grep "^Status:" | sed 's/^Status: //')
        version_line=$(echo "$status_output" | grep "^Version:" | sed 's/^Version: //')
        motd_line=$(echo "$status_output" | grep "^MOTD:" | sed 's/^MOTD: //')
        players_line=$(echo "$status_output" | grep "^Players:" | sed 's/^Players: //')
        latency_line=$(echo "$status_output" | grep "^Latency (ms):" | sed 's/^Latency (ms): //')
        favicon_line=$(echo "$status_output" | grep "^FAVICON:" | sed 's/^FAVICON: //')

        if [ "$SHORT_OUTPUT" = false ]; then
            local protocol_line software_line plugins_line player_sample_line error_line
            protocol_line=$(echo "$status_output" | grep "^Protocol:" | sed 's/^Protocol: //')
            software_line=$(echo "$status_output" | grep "^Software:" | sed 's/^Software: //')
            plugins_line=$(echo "$status_output" | grep "^Plugins" | sed 's/^Plugins[^:]*: //')
            player_sample_line=$(echo "$status_output" | grep "^Online players sample:" | sed 's/^Online players sample: //')
            error_line=$(echo "$status_output" | grep "^ERROR:" | sed 's/^ERROR: //')
            jq -n \
                --arg server "$SERVER" --arg port "$PORT" --arg status "$status_line" \
                --arg version "$version_line" --arg protocol "$protocol_line" --arg motd "$motd_line" \
                --arg players "$players_line" --arg latency "$latency_line" --arg software "$software_line" \
                --arg plugins "$plugins_line" --arg player_sample "$player_sample_line" --arg error "$error_line" \
                --arg dns_a "$dns_a" --arg dns_cname "$dns_cname" --arg dns_srv "$dns_srv" \
                --arg geo_country "$geo_country" --arg geo_city "$geo_city" --arg geo_region "$geo_region" --arg geo_isp "$geo_isp" \
                --arg ping "$ping_stats" --arg favicon "$favicon_line" --arg alert "$warning_msg" \
                --arg checked_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
                '{
                    "server": $server, "port": $port, "status": $status, "checked_at": $checked_at,
                    "version": $version, "protocol": $protocol, "motd": $motd, "players": $players,
                    "latency_ms": ($latency | tonumber? // null), "software": $software, "plugins": $plugins,
                    "player_sample": $player_sample, "error": $error, "favicon_base64": $favicon, "alert": $alert,
                    "dns": {"a": $dns_a, "cname": $dns_cname, "srv": $dns_srv},
                    "geolocation": {"country": $geo_country, "city": $geo_city, "region": $geo_region, "isp": $geo_isp},
                    "ping_stats": $ping
                }'
        else
            local error_line
            error_line=$(echo "$status_output" | grep "^ERROR:" | sed 's/^ERROR: //')
            jq -n \
                --arg server "$SERVER" --arg port "$PORT" --arg status "$status_line" \
                --arg version "$version_line" --arg motd "$motd_line" --arg players "$players_line" \
                --arg latency "$latency_line" --arg error "$error_line" --arg ping "$ping_stats" \
                --arg favicon "$favicon_line" --arg alert "$warning_msg" \
                --arg checked_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
                '{
                    "server": $server, "port": $port, "status": $status, "checked_at": $checked_at,
                    "version": $version, "motd": $motd, "players": $players,
                    "latency_ms": ($latency | tonumber? // null), "error": $error,
                    "favicon_base64": $favicon, "alert": $alert, "ping_stats": $ping
                }'
        fi
    fi
}

cleanup() {
    deactivate 2>/dev/null || true
    exit 0
}
trap cleanup SIGINT SIGTERM

if [ -n "$OUTPUT_FILE" ]; then
    exec > "$OUTPUT_FILE"
fi

if [ "$JSON_OUTPUT" = true ] && [ "$WATCH_SECONDS" -gt 0 ]; then
    while true; do
        run_query
        sleep "$WATCH_SECONDS"
    done
elif [ "$WATCH_SECONDS" -gt 0 ]; then
    while true; do
        [ "$NO_CLEAR" = false ] && clear
        run_query
        sleep "$WATCH_SECONDS"
    done
else
    run_query
    deactivate 2>/dev/null || true
fi