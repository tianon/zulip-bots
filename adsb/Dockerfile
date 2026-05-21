FROM debian:trixie-slim

RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		ca-certificates \
		jq \
		curl \
	; \
	apt-get dist-clean

WORKDIR /opt/zulip-bots/adsb

# see .dockerignore
COPY . .

CMD ["/opt/zulip-bots/adsb/bot.sh"]
