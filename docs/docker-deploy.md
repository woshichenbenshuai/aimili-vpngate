# Docker Deployment

AimiliVPN needs Linux networking permissions because OpenVPN creates `tun0` and the manager configures policy routing. Use host networking so services on the VPS, such as Xray or 3x-ui, can access the local proxy at `127.0.0.1:8317`.

## Install Docker

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl git
curl -fsSL https://get.docker.com | sudo sh
sudo systemctl enable --now docker
```

## Deploy

```bash
git clone https://github.com/woshichenbenshuai/aimili-vpngate.git /opt/aimilivpn
cd /opt/aimilivpn
docker compose up -d --build
```

Check logs:

```bash
docker logs -f aimilivpn
```

Read the generated Web credentials:

```bash
docker exec aimilivpn python -c "import json;print(json.dumps(json.load(open('/data/ui_auth.json')), ensure_ascii=False, indent=2))"
```

## Access Web UI

The Web UI listens on `0.0.0.0:6379` by default in Docker, so you can open it from your browser with the server IP:

```text
http://YOUR_SERVER_IP:6379/SECRET_PATH/
```

If an existing `vpngate_data/ui_auth.json` was created before this change, update its `host` value to `0.0.0.0` and restart the container:

```bash
docker exec aimilivpn python -c "import json;p='/data/ui_auth.json';d=json.load(open(p));d['host']='0.0.0.0';open(p,'w').write(json.dumps(d,ensure_ascii=False,indent=2))"
docker restart aimilivpn
```

## Use The Proxy

Services on the same VPS can use:

```text
HTTP proxy:   http://127.0.0.1:8317
SOCKS5 proxy: socks5h://127.0.0.1:8317
```

Verify the original VPS IP and the AimiliVPN egress IP:

```bash
curl https://api.ipify.org
curl -x socks5h://127.0.0.1:8317 http://api.ipify.org --max-time 10
```

## Clean Public Node Mode

Docker defaults to a cleaner public-node profile:

```yaml
PUBLICVPNLIST_URL: https://publicvpnlist.com/
PUBLICVPNLIST_LIMIT: "40"
ACCEPTED_EXIT_IP_TYPES: residential,mobile
MAX_SCAN_ROWS: "1000"
MAX_NODE_SESSIONS: "30"
MAX_NODE_PING: "350"
MIN_NODE_SPEED: "1000000"
DENY_NODE_IP_PREFIXES: 219.100.37.,219.100.36.
```

Apply changes:

```bash
docker compose up -d --build
```

This skips busy public nodes, slow entries, and common VPNGate shared prefixes before testing. Lower `MAX_NODE_SESSIONS` for fewer users, or set it to `0` to disable the session limit.
