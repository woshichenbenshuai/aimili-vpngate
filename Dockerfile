FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    VPNGATE_DATA_DIR=/data \
    LOCAL_PROXY_HOST=127.0.0.1 \
    LOCAL_PROXY_PORT=8317 \
    UI_HOST=0.0.0.0 \
    UI_PORT=6379 \
    ACCEPTED_EXIT_IP_TYPES=residential,mobile,normal \
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
