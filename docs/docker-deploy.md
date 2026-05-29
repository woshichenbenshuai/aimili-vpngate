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

The Web UI listens on `127.0.0.1:6379` by default. Use an SSH tunnel from your computer:

```bash
ssh -N -L 6379:127.0.0.1:6379 root@YOUR_SERVER_IP
```

Open:

```text
http://127.0.0.1:6379/SECRET_PATH/
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

## Strict Residential Mode

Edit `docker-compose.yml` if you only want residential or mobile exits:

```yaml
ACCEPTED_EXIT_IP_TYPES: residential,mobile
```

Apply changes:

```bash
docker compose up -d --build
```

Strict mode can take longer to find usable nodes because VPNGate availability changes often.
