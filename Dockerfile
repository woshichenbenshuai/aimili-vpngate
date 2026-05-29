FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    VPNGATE_DATA_DIR=/data \
    LOCAL_PROXY_HOST=127.0.0.1 \
    LOCAL_PROXY_PORT=8317 \
    UI_HOST=0.0.0.0 \
    UI_PORT=6379 \
    PUBLICVPNLIST_URL=https://publicvpnlist.com/ \
    PUBLICVPNLIST_LIMIT=40 \
    MAX_SCAN_ROWS=1000 \
    ACCEPTED_EXIT_IP_TYPES=residential,mobile \
    MAX_NODE_SESSIONS=30 \
    MAX_NODE_PING=350 \
    MIN_NODE_SPEED=1000000 \
    DENY_NODE_IP_PREFIXES=219.100.37.,219.100.36. \
    BLACKLIST_TTL_SECONDS=21600

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        iproute2 \
        iputils-ping \
        openvpn \
        procps \
        psmisc \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY proxy_server.py vpn_utils.py vpngate_manager.py ./

RUN mkdir -p /data

VOLUME ["/data"]

CMD ["python", "/app/vpngate_manager.py"]
