FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    VPNGATE_DATA_DIR=/data \
    LOCAL_PROXY_HOST=0.0.0.0 \
    LOCAL_PROXY_PORT=8317 \
    UI_HOST=0.0.0.0 \
    UI_PORT=17002 \
    PUBLICVPNLIST_URL=https://publicvpnlist.com/ \
    PUBLICVPNLIST_LIMIT=0 \
    PUBLICVPNLIST_FILTER_CANDIDATES=0 \
    PUBLICVPNLIST_MAX_CONFIG_BYTES=262144 \
    MAX_NODE_LIST=0 \
    MAX_TEST_NODES=20 \
    MAX_TEST_WORKERS=10 \
    MAINTENANCE_PROBE_NODES=20 \
    MAX_SCAN_ROWS=1000 \
    ACCEPTED_EXIT_IP_TYPES=residential,mobile \
    MIN_PURITY_SCORE=70 \
    PROBE_RECHECK_INTERVAL_SECONDS=21600 \
    SOURCE_PROBE_ORDER=AutoOVPN,VPNGate,IPSpeed,RiseupVPN,CoopVPN,CynegeirusOVPN,ZoultOVPN,publicvpnlist \
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
