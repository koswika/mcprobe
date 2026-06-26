# mcprobe

Query Minecraft servers from the command line. Shows DNS records, version, player count, MOTD, latency, software, plugins, and online players.

---

## Install

### Linux / macOS

```bash
curl -fsSL https://raw.githubusercontent.com/koswika/mcprobe/main/mcprobe.sh | bash
```

You'll be asked if you want to install system-wide. Hit Enter to confirm.

### Windows (PowerShell)

```powershell
irm https://raw.githubusercontent.com/koswika/mcprobe/main/install.ps1 | iex
```

Requires [Git Bash](https://gitforwindows.org/) or WSL to run the script.

---

## Usage

```
mcprobe <server> [port] [options]
```

```bash
mcprobe play.hypixel.net
mcprobe mc.example.com 19132
mcprobe play.hypixel.net --watch 10
mcprobe play.hypixel.net --json
```

---

## Options

| Flag | Description |
|------|-------------|
| `--watch N` | Refresh every N seconds |
| `--json` | Output raw JSON |
| `--ping` | ICMP ping the server IP (3 packets) |
| `--short` | Minimal output: server, players, latency, MOTD |
| `--alert` | With `--watch` + `--discord`, only send on status change |
| `--discord URL` | Send results as a Discord embed to a webhook URL |
| `--discord-name NAME` | Custom webhook display name |
| `--discord-avatar URL` | Custom webhook avatar URL |
| `--discord-color HEX` | Custom embed color (e.g. `0x00FF00`) |
| `--favicon [FILE]` | Save server favicon as PNG (default: `server_icon.png`) |
| `--no-geo` | Skip geolocation lookup |
| `--no-dns` | Skip DNS and SRV lookups |
| `--no-clear` | In watch mode, scroll output instead of clearing screen |
| `--min-players N` | Alert when online players drop below N |
| `--max-players N` | Alert when online players exceed N |
| `--log FILE` | Append a log line to FILE on each query |
| `--csv FILE` | Append CSV data to FILE on each query |
| `--timeout N` | Query timeout in seconds (default: 10) |
| `--retry N` | Retry N times on connection failure (default: 1) |
| `--output FILE` | Save output to FILE instead of stdout |
| `--version` | Show version and exit |
| `--help` | Show help message |

---

## Examples

**Basic query**
```bash
mcprobe play.hypixel.net
```

**Watch mode, refresh every 30 seconds**
```bash
mcprobe play.hypixel.net --watch 30
```

**JSON output**
```bash
mcprobe play.hypixel.net --json
```

**Send to Discord on every status change**
```bash
mcprobe play.hypixel.net --watch 60 --discord https://discord.com/api/webhooks/... --alert
```

**Alert when player count drops below 10**
```bash
mcprobe play.hypixel.net --watch 30 --min-players 10 --discord https://discord.com/api/webhooks/...
```

**Save favicon, log to CSV**
```bash
mcprobe play.hypixel.net --favicon icon.png --csv log.csv
```

---

## What It Shows

- Server status (online/offline)
- MOTD
- Version and protocol number
- Player count (online/max) and sample player list
- Latency (ms)
- Software and plugins (when query protocol is enabled)
- DNS A, CNAME, and SRV records
- Server IP geolocation (country, city, ISP)
- ICMP ping stats (optional)

---

## Dependencies

Installed automatically on first run:

- `python3`
- `mcstatus` (via pip, in a virtualenv at `~/.local/share/mcprobe_venv`)
- `dig` (bind-tools / dnsutils)
- `curl`
- `jq`

---

## Requirements

- bash 4+
- Linux, macOS, or Windows (via Git Bash / WSL)

---

## License

MIT