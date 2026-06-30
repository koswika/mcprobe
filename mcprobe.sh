#!/bin/bash
set -uo pipefail

VERSION="2.0.0"

WATCH_SECONDS=0
SERVER=""
PORT=""
PORT_EXPLICIT=false
DISCORD_WEBHOOK=""
DISCORD_NAME=""
DISCORD_AVATAR=""
DISCORD_COLOR=""
SLACK_WEBHOOK=""
JSON_OUTPUT=false
PING_ENABLED=false
ALERT_ENABLED=false
SHORT_OUTPUT=false
FAVICON_PATH=""
NO_GEO=false
NO_DNS=false
NO_COLOR=false
MIN_PLAYERS=""
MAX_PLAYERS=""
LOG_FILE=""
TIMEOUT=""
RETRY=""
OUTPUT_FILE=""
CSV_FILE=""
NO_CLEAR=false
BEDROCK=false
LIST_FILE=""
DIFF_ONLY=false
LAST_DIFF_KEY=""

is_int() {
  [[ "$1" =~ ^-?[0-9]+$ ]]
}

die() {
  echo "Error: $1" >&2
  exit 1
}

if [ -t 1 ] && [ "${NO_COLOR:-false}" = false ] && [ -z "${NO_COLOR_ENV:-}" ]; then
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
  C_CYAN=$'\033[36m'; C_BOLD=$'\033[1m'; C_RESET=$'\033[0m'
else
  C_RED=""; C_GREEN=""; C_YELLOW=""; C_CYAN=""; C_BOLD=""; C_RESET=""
fi

while [[ $# -gt 0 ]]; do
case $1 in
  --help|-h)
    echo "Usage: $0 <server_address> [port] [options]"
    echo ""
    echo "Options:"
    echo "  --watch N               Refresh every N seconds"
    echo "  --diff                  With --watch, only print full output when status/players/version changes"
    echo "  --bedrock               Query a Bedrock edition server"
    echo "  --list FILE             Query every server listed in FILE (host[:port] per line)"
    echo "  --discord WEBHOOK_URL   Send Discord embeds to the given webhook"
    echo "  --discord-name NAME     Custom name for Discord webhook"
    echo "  --discord-avatar URL    Custom avatar URL for Discord webhook"
    echo "  --discord-color HEX     Custom embed color (e.g., 0x00FF00)"
    echo "  --slack WEBHOOK_URL     Send Slack messages to the given webhook"
    echo "  --json                  Output raw JSON instead of human-readable text"
    echo "  --ping                  Ping the resolved IP address (3 packets) and show stats"
    echo "  --alert                 With --watch and a webhook, send only on status change"
    echo "  --short                 Minimal output: only server, players, latency, MOTD"
    echo "  --favicon [FILE]        Save server favicon as PNG (default: server_icon.png)"
    echo "  --no-geo                Skip geolocation lookup"
    echo "  --no-dns                Skip DNS and SRV lookups"
    echo "  --no-color              Disable colored terminal output"
    echo "  --no-clear              In watch mode, do not clear screen (scroll output)"
    echo "  --min-players N         Alert when online players drop below N"
    echo "  --max-players N         Alert when online players exceed N"
    echo "  --log FILE              Append minimal log line to FILE"
    echo "  --csv FILE              Append CSV data to FILE"
    echo "  --timeout N             Set timeout in seconds for mcstatus query (default: 10)"
    echo "  --retry N               Retry N times if connection fails (default: 1)"
    echo "  --output FILE           Save output to FILE instead of stdout"
    echo "  --version               Show version information and exit"
    echo "  --install               Install this script system-wide (to /usr/local/bin)"
    echo "  --help, -h              Show this help message"
    echo ""
    echo "Example:"
    echo "  $0 play.hypixel.net --watch 10 --no-clear"
    echo "  $0 --bedrock play.example.net 19132"
    echo "  $0 --list servers.txt --json"
    exit 0
    ;;
  --version)
    echo "mcprobe version $VERSION"
    exit 0
    ;;
  --watch)
    is_int "$2" || die "--watch requires an integer"
    WATCH_SECONDS="$2"
    shift 2
    ;;
  --bedrock)
    BEDROCK=true
    shift
    ;;
  --diff)
    DIFF_ONLY=true
    shift
    ;;
  --list)
    LIST_FILE="$2"
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
  --slack)
    SLACK_WEBHOOK="$2"
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
    if [[ -n "${2:-}" && "$2" != --* ]]; then
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
  --no-color)
    NO_COLOR=true
    C_RED=""; C_GREEN=""; C_YELLOW=""; C_CYAN=""; C_BOLD=""; C_RESET=""
    shift
    ;;
  --no-clear)
    NO_CLEAR=true
    shift
    ;;
  --min-players)
    is_int "$2" || die "--min-players requires an integer"
    MIN_PLAYERS="$2"
    shift 2
    ;;
  --max-players)
    is_int "$2" || die "--max-players requires an integer"
    MAX_PLAYERS="$2"
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
    is_int "$2" || die "--timeout requires an integer"
    TIMEOUT="$2"
    shift 2
    ;;
  --retry)
    is_int "$2" || die "--retry requires an integer"
    RETRY="$2"
    shift 2
    ;;
  --output)
    OUTPUT_FILE="$2"
    shift 2
    ;;
  --install)
    SCRIPT_PATH="$(realpath "$0")"
    sudo cp "$SCRIPT_PATH" /usr/local/bin/mcprobe
    sudo chmod +x /usr/local/bin/mcprobe
    echo "Installed to /usr/local/bin/mcprobe"
    exit 0
    ;;
  *)
    if [ -z "$SERVER" ]; then
      SERVER="$1"
    elif [ "$PORT_EXPLICIT" = false ]; then
      is_int "$1" || die "port must be numeric"
      PORT="$1"
      PORT_EXPLICIT=true
    fi
    shift
    ;;
esac
done

if [ -z "$PORT" ]; then
  if [ "$BEDROCK" = true ]; then
    PORT="19132"
  else
    PORT="25565"
  fi
fi

if [ -z "$SERVER" ] && [ -z "$LIST_FILE" ]; then
  echo "Error: No server address provided." >&2
  echo "Run '$0 --help' for usage." >&2
  exit 1
fi

PKG_MGR=""
if command -v apt-get &> /dev/null; then PKG_MGR="apt"
elif command -v dnf &> /dev/null; then PKG_MGR="dnf"
elif command -v yum &> /dev/null; then PKG_MGR="yum"
elif command -v pacman &> /dev/null; then PKG_MGR="pacman"
elif command -v zypper &> /dev/null; then PKG_MGR="zypper"
elif command -v brew &> /dev/null; then PKG_MGR="brew"
elif command -v apk &> /dev/null; then PKG_MGR="apk"
fi

install_pkg() {
  local pkgname_apt="$1" pkgname_dnf="$2" pkgname_pacman="$3" pkgname_brew="$4" pkgname_apk="$5"
  case "$PKG_MGR" in
    apt) sudo apt-get install -y "$pkgname_apt" ;;
    dnf) sudo dnf install -y "$pkgname_dnf" ;;
    yum) sudo yum install -y "$pkgname_dnf" ;;
    pacman) sudo pacman -S --noconfirm "$pkgname_pacman" ;;
    zypper) sudo zypper install -y "$pkgname_dnf" ;;
    brew) brew install "$pkgname_brew" ;;
    apk) sudo apk add "$pkgname_apk" ;;
    *) echo "No supported package manager found; install '$pkgname_apt' manually." >&2; return 1 ;;
  esac
}

if ! command -v python3 &> /dev/null; then
  echo "python3 not found. Installing..."
  install_pkg python3 python3 python3 python3 python3
fi

if [ "$NO_DNS" = false ] && ! command -v dig &> /dev/null; then
  echo "dig not found. Installing..."
  install_pkg dnsutils bind-utils bind bind dnsutils
fi

if ! command -v curl &> /dev/null; then
  echo "curl not found. Installing..."
  install_pkg curl curl curl curl curl
fi

if ! command -v jq &> /dev/null; then
  echo "jq not found. Installing..."
  install_pkg jq jq jq jq jq
fi

if [ "$PING_ENABLED" = true ] && ! command -v ping &> /dev/null; then
  echo "ping not found. Installing..."
  install_pkg iputils-ping iputils iputils-ping iputils iputils
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
  pip install --quiet mcstatus
fi

hr() {
  [ "$JSON_OUTPUT" = false ] && echo "============================================================"
}

safe_grep() {
  grep "$1" 2>/dev/null || true
}

add_field() {
  local fields="$1" name="$2" value="$3" inline="$4"
  echo "$fields" | jq --arg n "$name" --arg v "$value" --argjson i "$inline" \
    '. + [{"name": $n, "value": $v, "inline": $i}]'
}

sanitize_key() {
  echo "$1" | tr -c 'A-Za-z0-9._-' '_'
}

send_discord_embed() {
  if [ -z "$DISCORD_WEBHOOK" ] || ! command -v curl &> /dev/null || ! command -v jq &> /dev/null; then
    return
  fi
  local online="$1" version="$2" protocol="$3" motd="$4" players="$5" latency="$6"
  local software="$7" plugins="$8" player_list="$9" dns_a="${10}" dns_cname="${11}" dns_srv="${12}"
  local geo_country="${13}" geo_city="${14}" geo_region="${15}" geo_isp="${16}" error_msg="${17}"
  local ping_stats="${18}" warning_msg="${19}"
  local timestamp color title description
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  if [ "$online" = "true" ]; then
    if [ -n "$DISCORD_COLOR" ]; then
      color=$((DISCORD_COLOR)) 2>/dev/null || color=5763719
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
      fields=$(add_field "$fields" "Alert" "$warning_msg" false)
    fi
    if [ "$SHORT_OUTPUT" = false ]; then
      fields=$(add_field "$fields" "Version" "$version" true)
      fields=$(add_field "$fields" "Protocol" "$protocol" true)
      [ -n "$software" ] && fields=$(add_field "$fields" "Software" "$software" true)
      if [ -n "$plugins" ] && [ "$plugins" != "none" ]; then
        fields=$(add_field "$fields" "Plugins" "$plugins" false)
      fi
      [ -n "$player_list" ] && fields=$(add_field "$fields" "Online Players" "$player_list" false)
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

  if [ "$SHORT_OUTPUT" = false ] && [ "$NO_GEO" = false ] && { [ -n "$dns_a" ] || [ -n "$geo_country" ]; }; then
    local geo_value=""
    [ -n "$dns_a" ] && geo_value="${geo_value}IP: ${dns_a}"$'\n'
    [ -n "$geo_country" ] && geo_value="${geo_value}Country: ${geo_country}"$'\n'
    [ -n "$geo_city" ] && geo_value="${geo_value}City/Region: ${geo_city}, ${geo_region}"$'\n'
    [ -n "$geo_isp" ] && geo_value="${geo_value}ISP: ${geo_isp}"$'\n'
    geo_value="${geo_value%$'\n'}"
    fields=$(add_field "$fields" "Server Location" "$geo_value" false)
  fi

  local payload
  payload=$(jq -n \
    --arg title "$title" --arg description "$description" --argjson color "$color" \
    --argjson fields "$fields" --arg timestamp "$timestamp" \
    --arg footer "mcprobe • $SERVER:$PORT" --arg username "$DISCORD_NAME" --arg avatar_url "$DISCORD_AVATAR" \
    '{embeds: [{title: $title, description: $description, color: $color, fields: $fields, footer: {text: $footer}, timestamp: $timestamp}]}
     | if $username != "" then .username = $username else . end
     | if $avatar_url != "" then .avatar_url = $avatar_url else . end')

  curl -s -X POST -H "Content-Type: application/json" -d "$payload" "$DISCORD_WEBHOOK" > /dev/null
}

send_slack_message() {
  if [ -z "$SLACK_WEBHOOK" ] || ! command -v curl &> /dev/null || ! command -v jq &> /dev/null; then
    return
  fi
  local online="$1" players="$2" latency="$3" motd="$4" error_msg="$5" warning_msg="$6"
  local text
  if [ "$online" = "true" ]; then
    text="*$SERVER:$PORT* is *ONLINE*"
    [ -n "$players" ] && text="$text — players: $players"
    [ -n "$latency" ] && text="$text — latency: ${latency}ms"
    [ -n "$motd" ] && text="$text\nMOTD: $motd"
    [ -n "$warning_msg" ] && text="$text\n:warning: $warning_msg"
  else
    text="*$SERVER:$PORT* is *OFFLINE*"
    [ -n "$error_msg" ] && text="$text\nError: $error_msg"
  fi
  local payload
  payload=$(jq -n --arg text "$text" '{text: $text}')
  curl -s -X POST -H "Content-Type: application/json" -d "$payload" "$SLACK_WEBHOOK" > /dev/null
}

run_query() {
  local dns_a="" dns_cname="" dns_srv=""
  local geo_country="" geo_city="" geo_region="" geo_isp=""
  local ping_stats=""
  local srv_record_name="_minecraft._tcp.$SERVER"
  [ "$BEDROCK" = true ] && srv_record_name="_minecraft._udp.$SERVER"

  if [ "$JSON_OUTPUT" = false ] && [ "$SHORT_OUTPUT" = false ]; then
    hr
    echo "${C_BOLD}MINECRAFT SERVER INFORMATION for $SERVER${C_RESET}"
    hr
  fi

  if [ "$SHORT_OUTPUT" = false ] && [ "$NO_DNS" = false ]; then
    if command -v dig &> /dev/null; then
      [ "$JSON_OUTPUT" = false ] && { echo ""; echo "DNS RECORDS:"; }
      dns_a=$(dig +short "$SERVER" A 2>/dev/null | head -1)
      [ -n "$dns_a" ] && [ "$JSON_OUTPUT" = false ] && echo "  A record: $dns_a"
      dns_cname=$(dig +short "$SERVER" CNAME 2>/dev/null | head -1)
      [ -n "$dns_cname" ] && [ "$JSON_OUTPUT" = false ] && echo "  CNAME: $dns_cname"
      local srv_raw
      srv_raw=$(dig +short "$srv_record_name" SRV 2>/dev/null)
      if [ -n "$srv_raw" ]; then
        local srv_port srv_target
        srv_port=$(echo "$srv_raw" | awk '{print $3}')
        srv_target=$(echo "$srv_raw" | awk '{print $4}' | sed 's/\.$//')
        dns_srv="port $srv_port -> $srv_target"
        [ "$JSON_OUTPUT" = false ] && echo "  SRV: port $srv_port target $srv_target"
        if [ "$PORT_EXPLICIT" = false ] && [ "$srv_port" != "$PORT" ]; then
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

  if [ "$SHORT_OUTPUT" = false ] && [ "$NO_GEO" = false ] && [ -n "$dns_a" ] && command -v curl &> /dev/null; then
    [ "$JSON_OUTPUT" = false ] && { echo ""; echo "GEOLOCATION OF SERVER IP ($dns_a):"; }
    local geo
    geo=$(curl -s --max-time 5 "http://ip-api.com/json/$dns_a?fields=status,country,city,regionName,isp")
    if echo "$geo" | grep -q '"status":"success"'; then
      geo_country=$(echo "$geo" | sed -n 's/.*"country":"\([^"]*\)".*/\1/p')
      geo_city=$(echo "$geo" | sed -n 's/.*"city":"\([^"]*\)".*/\1/p')
      geo_region=$(echo "$geo" | sed -n 's/.*"regionName":"\([^"]*\)".*/\1/p')
      geo_isp=$(echo "$geo" | sed -n 's/.*"isp":"\([^"]*\)".*/\1/p')
      if [ "$JSON_OUTPUT" = false ]; then
        echo "  Country: ${geo_country:-unknown}"
        echo "  City/Region: ${geo_city:-unknown}, ${geo_region:-unknown}"
        echo "  ISP/Organization: ${geo_isp:-unknown}"
      fi
    else
      [ "$JSON_OUTPUT" = false ] && echo "  Geolocation query failed."
    fi
  fi

  if [ "$PING_ENABLED" = true ] && [ -n "$dns_a" ] && command -v ping &> /dev/null; then
    [ "$JSON_OUTPUT" = false ] && { echo ""; echo "PING TO SERVER IP ($dns_a):"; }
    local ping_output packet_loss
    ping_output=$(ping -c 3 -W 1 "$dns_a" 2>/dev/null || true)
    packet_loss=$(echo "$ping_output" | grep -Eo '[0-9]+(% packet loss| packets transmitted)' | grep -Eo '^[0-9]+' | head -1)
    if [ -n "$packet_loss" ] && [ "$packet_loss" -eq 100 ] 2>/dev/null; then
      ping_stats="100% packet loss (host unreachable)"
    else
      local rtt_line rtt_min rtt_avg rtt_max
      rtt_line=$(echo "$ping_output" | grep "min/avg/max" || true)
      if [ -n "$rtt_line" ]; then
        rtt_min=$(echo "$rtt_line" | awk -F'/' '{print $4}')
        rtt_avg=$(echo "$rtt_line" | awk -F'/' '{print $5}')
        rtt_max=$(echo "$rtt_line" | awk -F'/' '{print $6}')
        ping_stats="min=${rtt_min} ms, avg=${rtt_avg} ms, max=${rtt_max} ms"
      else
        ping_stats="ping completed but no RTT data"
      fi
    fi
    [ "$JSON_OUTPUT" = false ] && echo "  $ping_stats"
  fi

  if [ "$JSON_OUTPUT" = false ]; then
    echo ""
    echo "SERVER STATUS ($SERVER:$PORT)"
    echo "-----------------------------"
  fi

  local timeout_arg="${TIMEOUT:-10}"
  local retry_arg="${RETRY:-1}"
  local status_output

  if [ "$BEDROCK" = true ]; then
    status_output=$(python3 -c "
import sys, re, time
from mcstatus import BedrockServer

def clean_text(text):
    if not isinstance(text, str):
        return str(text)
    text = re.sub(r'§[0-9a-fklmnor]', '', text)
    text = re.sub(r'[\x00-\x1f\x7f]', '', text)
    text = re.sub(r'\s+', ' ', text)
    return text.strip()

def query_server():
    server = BedrockServer.lookup('$SERVER:$PORT')
    status = server.status(timeout=$timeout_arg)
    print('Status: ONLINE')
    print('Version:', clean_text(status.version.name))
    print('Protocol:', status.version.protocol)
    print('MOTD:', clean_text(status.motd))
    print('Players:', f'{status.players_online}/{status.players_max}')
    print('Latency (ms):', round(status.latency, 1))
    if getattr(status, 'gamemode', None):
        print('Gamemode:', clean_text(status.gamemode))
    if getattr(status, 'map_name', None):
        print('Map:', clean_text(status.map_name))

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
  elif [ "$SHORT_OUTPUT" = true ]; then
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
    query = None
    try:
        query = server.query(timeout=$timeout_arg)
    except Exception:
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

  if [ "$JSON_OUTPUT" = false ]; then
    if echo "$status_output" | grep -q "^Status: ONLINE"; then
      echo "${C_GREEN}${status_output}${C_RESET}"
    else
      echo "${C_RED}${status_output}${C_RESET}"
    fi
    hr
  fi

  if [ -n "$FAVICON_PATH" ]; then
    local favicon_raw favicon_b64
    favicon_raw=$(echo "$status_output" | safe_grep "^FAVICON:" | sed 's/^FAVICON: //')
    if [ -n "$favicon_raw" ]; then
      favicon_b64="${favicon_raw#data:image/png;base64,}"
      if echo "$favicon_b64" | base64 -d > "$FAVICON_PATH" 2>/dev/null; then
        echo "Favicon saved to $FAVICON_PATH" >&2
      else
        echo "Failed to decode favicon" >&2
      fi
    else
      echo "No favicon available for this server" >&2
    fi
  fi

  local current_status="OFFLINE"
  echo "$status_output" | grep -q "^Status: ONLINE" && current_status="ONLINE"

  local online_players="" max_players="" latency_value="" version_value=""
  if [ "$current_status" = "ONLINE" ]; then
    local players_line
    players_line=$(echo "$status_output" | safe_grep "^Players:" | head -1)
    if [ -n "$players_line" ]; then
      online_players=$(echo "$players_line" | sed -E 's/.* ([0-9]+)\/([0-9]+)$/\1/')
      max_players=$(echo "$players_line" | sed -E 's/.* ([0-9]+)\/([0-9]+)$/\2/')
    fi
    latency_value=$(echo "$status_output" | safe_grep "^Latency (ms):" | head -1 | sed 's/^Latency (ms): //')
    version_value=$(echo "$status_output" | safe_grep "^Version:" | head -1 | sed 's/^Version: //')
  fi

  local warning_msg=""
  if [ "$current_status" = "ONLINE" ] && [ -n "$online_players" ]; then
    if [ -n "$MIN_PLAYERS" ] && [ "$online_players" -lt "$MIN_PLAYERS" ]; then
      warning_msg="Player count ($online_players) is below minimum ($MIN_PLAYERS)"
    elif [ -n "$MAX_PLAYERS" ] && [ "$online_players" -gt "$MAX_PLAYERS" ]; then
      warning_msg="Player count ($online_players) exceeds maximum ($MAX_PLAYERS)"
    fi
    [ -n "$warning_msg" ] && [ "$JSON_OUTPUT" = false ] && echo "${C_YELLOW}WARNING: $warning_msg${C_RESET}" >&2
  fi

  if [ -n "$LOG_FILE" ]; then
    local timestamp log_line
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    log_line="$timestamp | $SERVER:$PORT | $current_status"
    if [ "$current_status" = "ONLINE" ]; then
      log_line="$log_line | players: $online_players | latency: ${latency_value}ms | version: $version_value"
      [ -n "$warning_msg" ] && log_line="$log_line | alert: $warning_msg"
    else
      local error_msg
      error_msg=$(echo "$status_output" | safe_grep "^ERROR:" | sed 's/^ERROR: //' | head -1)
      log_line="$log_line | error: $error_msg"
    fi
    echo "$log_line" >> "$LOG_FILE" 2>/dev/null || echo "Warning: Could not write to log file $LOG_FILE" >&2
  fi

  if [ -n "$CSV_FILE" ]; then
    local csv_timestamp csv_alert
    csv_timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    if [ ! -f "$CSV_FILE" ]; then
      echo "timestamp,server,port,status,players,max_players,latency_ms,version,alert" > "$CSV_FILE"
    fi
    csv_alert="${warning_msg:-}"
    echo "$csv_timestamp,$SERVER,$PORT,$current_status,${online_players:-},${max_players:-},${latency_value:-},${version_value:-},\"$csv_alert\"" >> "$CSV_FILE" 2>/dev/null || echo "Warning: Could not write to CSV file $CSV_FILE" >&2
  fi

  local should_send=true
  if [ "$ALERT_ENABLED" = true ] && { [ -n "$DISCORD_WEBHOOK" ] || [ -n "$SLACK_WEBHOOK" ]; }; then
    local status_key status_file last_status
    status_key=$(sanitize_key "${SERVER}_${PORT}")
    status_file="/tmp/mcprobe_status_${status_key}"
    last_status=""
    [ -f "$status_file" ] && last_status=$(cat "$status_file")
    if [ "$current_status" = "$last_status" ]; then
      should_send=false
    else
      echo "$current_status" > "$status_file"
    fi
  fi

  if [ "$should_send" = true ] && { [ -n "$DISCORD_WEBHOOK" ] || [ -n "$SLACK_WEBHOOK" ]; }; then
    local s_version s_protocol s_motd s_players s_latency s_software s_plugins s_player_list s_error
    s_version=$(echo "$status_output" | safe_grep "^Version:" | sed 's/^Version: //')
    s_protocol=$(echo "$status_output" | safe_grep "^Protocol:" | sed 's/^Protocol: //')
    s_motd=$(echo "$status_output" | safe_grep "^MOTD:" | sed 's/^MOTD: //')
    s_players=$(echo "$status_output" | safe_grep "^Players:" | sed 's/^Players: //')
    s_latency=$(echo "$status_output" | safe_grep "^Latency (ms):" | sed 's/^Latency (ms): //')
    s_software=$(echo "$status_output" | safe_grep "^Software:" | sed 's/^Software: //')
    s_plugins=$(echo "$status_output" | safe_grep "^Plugins" | sed 's/^Plugins[^:]*: //')
    s_player_list=$(echo "$status_output" | safe_grep "^Online players sample:" | sed 's/^Online players sample: //')
    s_error=$(echo "$status_output" | safe_grep "^ERROR:" | sed 's/^ERROR: //')

    if [ "$current_status" = "ONLINE" ]; then
      send_discord_embed "true" "$s_version" "$s_protocol" "$s_motd" "$s_players" "$s_latency" \
        "$s_software" "$s_plugins" "$s_player_list" "$dns_a" "$dns_cname" "$dns_srv" \
        "$geo_country" "$geo_city" "$geo_region" "$geo_isp" "" "$ping_stats" "$warning_msg"
      send_slack_message "true" "$s_players" "$s_latency" "$s_motd" "" "$warning_msg"
    else
      send_discord_embed "false" "" "" "" "" "" "" "" "" "$dns_a" "$dns_cname" "$dns_srv" \
        "$geo_country" "$geo_city" "$geo_region" "$geo_isp" "$s_error" "$ping_stats" ""
      send_slack_message "false" "" "" "" "$s_error" ""
    fi
  fi

  if [ "$JSON_OUTPUT" = true ]; then
    local status_line version_line motd_line players_line latency_line favicon_line error_line
    status_line=$(echo "$status_output" | safe_grep "^Status:" | sed 's/^Status: //')
    version_line=$(echo "$status_output" | safe_grep "^Version:" | sed 's/^Version: //')
    motd_line=$(echo "$status_output" | safe_grep "^MOTD:" | sed 's/^MOTD: //')
    players_line=$(echo "$status_output" | safe_grep "^Players:" | sed 's/^Players: //')
    latency_line=$(echo "$status_output" | safe_grep "^Latency (ms):" | sed 's/^Latency (ms): //')
    favicon_line=$(echo "$status_output" | safe_grep "^FAVICON:" | sed 's/^FAVICON: //')
    error_line=$(echo "$status_output" | safe_grep "^ERROR:" | sed 's/^ERROR: //')

    if [ "$SHORT_OUTPUT" = false ] && [ "$BEDROCK" = false ]; then
      local protocol_line software_line plugins_line player_sample_line
      protocol_line=$(echo "$status_output" | safe_grep "^Protocol:" | sed 's/^Protocol: //')
      software_line=$(echo "$status_output" | safe_grep "^Software:" | sed 's/^Software: //')
      plugins_line=$(echo "$status_output" | safe_grep "^Plugins" | sed 's/^Plugins[^:]*: //')
      player_sample_line=$(echo "$status_output" | safe_grep "^Online players sample:" | sed 's/^Online players sample: //')

      jq -n \
        --arg server "$SERVER" --arg port "$PORT" --arg status "$status_line" \
        --arg version "$version_line" --arg protocol "$protocol_line" --arg motd "$motd_line" \
        --arg players "$players_line" --arg latency "$latency_line" --arg software "$software_line" \
        --arg plugins "$plugins_line" --arg player_sample "$player_sample_line" --arg error "$error_line" \
        --arg dns_a "$dns_a" --arg dns_cname "$dns_cname" --arg dns_srv "$dns_srv" \
        --arg geo_country "$geo_country" --arg geo_city "$geo_city" --arg geo_region "$geo_region" --arg geo_isp "$geo_isp" \
        --arg ping "$ping_stats" --arg favicon "$favicon_line" --arg alert "$warning_msg" \
        '{server:$server, port:$port, status:$status, version:$version, protocol:$protocol, motd:$motd,
          players:$players, latency_ms:($latency|tonumber? // null), software:$software, plugins:$plugins,
          player_sample:$player_sample, error:$error, favicon_base64:$favicon, alert:$alert,
          dns:{a:$dns_a, cname:$dns_cname, srv:$dns_srv},
          geolocation:{country:$geo_country, city:$geo_city, region:$geo_region, isp:$geo_isp},
          ping_stats:$ping}'
    else
      jq -n \
        --arg server "$SERVER" --arg port "$PORT" --arg status "$status_line" \
        --arg version "$version_line" --arg motd "$motd_line" --arg players "$players_line" \
        --arg latency "$latency_line" --arg error "$error_line" --arg ping "$ping_stats" \
        --arg favicon "$favicon_line" --arg alert "$warning_msg" \
        '{server:$server, port:$port, status:$status, version:$version, motd:$motd, players:$players,
          latency_ms:($latency|tonumber? // null), error:$error, favicon_base64:$favicon, alert:$alert, ping_stats:$ping}'
    fi
  fi
}

run_batch() {
  [ -f "$LIST_FILE" ] || die "list file '$LIST_FILE' not found"
  local line host port
  local results="[]"
  while IFS= read -r line || [ -n "$line" ]; do
    line="$(echo "$line" | sed 's/#.*//' | xargs)"
    [ -z "$line" ] && continue
    if [[ "$line" == *:* ]]; then
      host="${line%%:*}"
      port="${line##*:}"
    else
      host="$line"
      port=""
    fi
    SERVER="$host"
    PORT_EXPLICIT=false
    if [ -n "$port" ]; then
      PORT="$port"
      PORT_EXPLICIT=true
    else
      PORT=""
      [ "$BEDROCK" = true ] && PORT="19132" || PORT="25565"
    fi
    if [ "$JSON_OUTPUT" = true ]; then
      results=$(echo "$results" | jq --argjson r "$(run_query)" '. + [$r]')
    else
      run_query
      echo ""
    fi
  done < "$LIST_FILE"
  [ "$JSON_OUTPUT" = true ] && echo "$results" | jq '.'
}

cleanup() {
  deactivate 2>/dev/null || true
  exit 0
}
trap cleanup SIGINT SIGTERM

if [ -n "$OUTPUT_FILE" ]; then
  exec > "$OUTPUT_FILE"
fi

run_target() {
  if [ -n "$LIST_FILE" ]; then
    run_batch
  else
    run_query
  fi
}

declare -A DIFF_KEYS

run_target_diffed() {
  local key captured sig
  key="${SERVER}:${PORT}"
  captured=$(run_target)
  sig=$(echo "$captured" | grep -E "^(Status:|Players:|Version:)" | tr '\n' '|')
  if [ "${DIFF_KEYS[$key]:-}" != "$sig" ]; then
    DIFF_KEYS[$key]="$sig"
    echo "$captured"
  else
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $key | no change"
  fi
}

if [ "$WATCH_SECONDS" -gt 0 ] 2>/dev/null; then
  while true; do
    if [ "$JSON_OUTPUT" = false ] && [ "$NO_CLEAR" = false ] && [ "$DIFF_ONLY" = false ]; then
      clear
    fi
    if [ "$DIFF_ONLY" = true ] && [ "$JSON_OUTPUT" = false ] && [ -z "$LIST_FILE" ]; then
      run_target_diffed
    else
      run_target
    fi
    sleep "$WATCH_SECONDS"
  done
else
  run_target
  deactivate 2>/dev/null || true
fi