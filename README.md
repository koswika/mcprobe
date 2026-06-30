![version](https://img.shields.io/badge/version-2.0.0-blue)
![bash](https://img.shields.io/badge/bash-5.0%2B-1f425f)
![license](https://img.shields.io/badge/license-MIT-green)
![shell](https://img.shields.io/badge/shell-100%25-89e051)
![platform](https://img.shields.io/badge/platform-linux%20%7C%20macos-lightgrey)
![GitHub stars](https://img.shields.io/github/stars/koswika/mcprobe?style=flat)
![GitHub issues](https://img.shields.io/github/issues/koswika/mcprobe)
![GitHub last commit](https://img.shields.io/github/last-commit/koswika/mcprobe)

# mcprobe

Query Minecraft servers from the command line. Shows DNS records, version, player count, MOTD, latency, software, plugins, and online players, for both Java and Bedrock edition servers.

Started this because I got tired of alt-tabbing into the game just to see if a server was up. It's grown a bit since then.

## Features

- Java and Bedrock edition support
- DNS (A / CNAME / SRV) lookups and IP geolocation for the resolved server IP
- ICMP ping stats alongside the Minecraft protocol latency
- Watch mode (`--watch N`) for polling on an interval, with a `--diff` mode that only prints when something actually changes
- Discord and Slack webhook notifications, with `--alert` to only fire on status changes instead of every poll
- Player watch: get notified when a specific player joins or leaves
- JSON output for piping into other tools, plus CSV and plain log file output for tracking uptime over time
- Batch mode: point it at a file of servers and it'll check all of them
- Favicon extraction (`--favicon`)
- Min/max player alerting

## Requirements

- bash
- python3 (the script will try to install it if missing)
- `dig`, `curl`, `jq`, also auto-installed if not found
- one of: apt, dnf, yum, pacman, zypper, brew, or apk, for the auto-install step to work. If you're on something else, just install python3/dig/curl/jq yourself first and it'll skip straight past that.

The script sets up a local Python venv at `~/.local/share/mcprobe_venv` on first run and installs `mcstatus` into it, so it won't touch your system Python packages.

## Install

```bash
git clone https://github.com/koswika/mcprobe.git
cd mcprobe
chmod +x mcprobe.sh
./mcprobe.sh --install
```

`--install` just copies the script to `/usr/local/bin/mcprobe` (needs sudo) so you can run `mcprobe` from anywhere afterward. You can also skip that and just run `./mcprobe.sh` directly out of the repo.

## Usage

```
mcprobe <server_address> [port] [options]
```

Basic check:

```bash
mcprobe play.hypixel.net
```

Bedrock server on a non-default port:

```bash
mcprobe --bedrock play.example.net 19133
```

Watch a server every 10 seconds, only printing when something changes:

```bash
mcprobe play.hypixel.net --watch 10 --diff
```

Post to Discord only when the server goes up/down:

```bash
mcprobe play.hypixel.net --watch 30 --discord https://discord.com/api/webhooks/xxx --alert
```

Get pinged (well, Discord-pinged) when a specific player logs on:

```bash
mcprobe mc.example.com --watch 15 --player-watch Notch,jeb_
```

Check a whole list of servers at once:

```bash
mcprobe --list servers.txt --json
```

where `servers.txt` is just one `host[:port]` per line, `#` comments allowed.

## Options

| Flag | Description |
|---|---|
| `--watch N` | Refresh every N seconds |
| `--diff` | With `--watch`, only print full output when status/players/version changes |
| `--bedrock` | Query a Bedrock edition server instead of Java |
| `--player-watch NAMES` | Comma-separated player names, alerts on join/leave (needs query protocol enabled on the server) |
| `--list FILE` | Query every server listed in FILE |
| `--discord WEBHOOK_URL` | Send Discord embeds to the given webhook |
| `--discord-name NAME` | Custom name for the Discord webhook |
| `--discord-avatar URL` | Custom avatar for the Discord webhook |
| `--discord-color HEX` | Custom embed color, e.g. `0x00FF00` |
| `--slack WEBHOOK_URL` | Send Slack messages to the given webhook |
| `--json` | Output raw JSON instead of human-readable text |
| `--ping` | Ping the resolved IP (3 packets) and show stats |
| `--alert` | With `--watch` and a webhook, only send on status change |
| `--short` | Minimal output, server, players, latency, MOTD only |
| `--favicon [FILE]` | Save the server favicon as a PNG (default: `server_icon.png`) |
| `--no-geo` | Skip geolocation lookup |
| `--no-dns` | Skip DNS and SRV lookups |
| `--no-color` | Disable colored terminal output |
| `--no-clear` | In watch mode, don't clear the screen between polls |
| `--min-players N` | Alert when player count drops below N |
| `--max-players N` | Alert when player count exceeds N |
| `--log FILE` | Append a log line per check to FILE |
| `--csv FILE` | Append a CSV row per check to FILE |
| `--timeout N` | mcstatus query timeout in seconds (default: 10) |
| `--retry N` | Retry N times on connection failure (default: 1) |
| `--output FILE` | Write output to FILE instead of stdout |
| `--install` | Install to `/usr/local/bin` |
| `--version` | Print version and exit |
| `--help`, `-h` | Show usage |

## Notes / known limitations

- `--player-watch` relies on the GameSpot query protocol being enabled on the server (the same thing that powers the plugin/software list). A lot of servers have this off by default, in which case you just won't get a player sample to diff against.
- `--diff` currently only does anything for single-server mode, not `--list`. Might wire that up later.
- Geolocation uses the free ip-api.com endpoint, which is rate-limited (45 req/min) and HTTP only. Fine for occasional checks, not great if you're hammering a `--watch` loop with a 1-second interval.
- The `--install` step assumes `/usr/local/bin` is on your `PATH`. On most distros it is.

## License

MIT
