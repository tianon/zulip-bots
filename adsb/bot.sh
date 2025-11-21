#!/usr/bin/env bash
set -Eeuo pipefail

[ -s config.jq ]
[ -s lib.jq ]

# TODO config.jq is already housing some pretty sensitive data (lat, lon) -- maybe the Zulip login info can/should live in there too, and aircraft.json could be passed as an argument to this script or something?  then we could notify to more than one Zulip instance from a single bot instance (by making the site/login details part of a "target", or at least by making the site part of it and perhaps still storing the actual login tokens elsewhere in an even less heavily cross-imported file? so they don't end up in our "munged" data?)

set -o allexport
source secret.sh
set +o allexport

[ -n "$ZULIP_SITE" ] # "https://foobar.zulipchat.com"
[ -n "$ZULIP_BOT_EMAIL" ] # "barbaz-bot@foobar.zulipchat.com"
[ -n "${ZULIP_BOT:+secret}" ] # "$ZULIP_BOT_EMAIL:xxxxxtokenxxxxx"

[ -s "$READSB_AIRCRAFT_JSON" ] # /path/to/aircraft.json (https://github.com/wiedehopf/readsb/blob/7b78f77f08747aa50d61c0ffd83f02e3278de5ca/README-json.md#aircraftjson-and---json-port)

while true; do
	# easy ways to test:
	#  ADSB_NEAR_METERS_OVERRIDE=1000000 jq 'include "./lib"; include "./config"; aircraft(locations; tar1090s) | filter_targets(targets)' /path/to/aircraft.json
	#  ADSB_NEAR_METERS_OVERRIDE=1000000 jq 'include "./lib"; include "./config"; zulip_targets(locations; tar1090s; targets)' /path/to/aircraft.json
	targets="$(jq --raw-output '
		include "./lib";
		include "./config";
		zulip_targets(locations; tar1090s; targets)
		| map(@json | @sh)
		| join(" ")
	' "$READSB_AIRCRAFT_JSON")"
	eval "targets=( $targets )"

	# TODO save "hex" above so we can query planespotters for all of them and drop a bunch of "[📷](.photos[0].thumbnail_large)" in a row together at the end (which Zulip will then render all in a row)
	# https://api.planespotters.net/pub/photos/hex/<icao>

	for target in "${targets[@]}"; do
		jq <<<"$target" --raw-output '
			"",
			"⇉ #\(.channel) > \(.topic)",
			"",
			.message,
			""
		'

		search="$(jq <<<"$target" --raw-output 'include "./uri"; uriencode({
			# https://zulip.com/api/get-messages
			narrow: [
				# https://zulip.com/api/construct-narrow
				{ operator: "channel", operand: .channel },
				{ operator: "topic",   operand: .topic },
				{ operator: "sender",  operand: env.ZULIP_BOT_EMAIL },
				empty
			],
			anchor: "newest",
			num_before: "1",
			num_after: "1",
			apply_markdown: "false",
		})')"
		unset url method data
		if id="$(
			curl -fsSX GET -G "$ZULIP_SITE/api/v1/messages" \
				-u "$ZULIP_BOT" \
				--data-raw "$search" \
			| jq --raw-output 'if .result == "success" and .messages[-1] and .messages[-1].timestamp + 60 >= now then .messages[-1].id // "" else "" end' # TODO ask the server how long we can edit messages
		)" && [ -n "$id" ]; then
			url="$ZULIP_SITE/api/v1/messages/$id"
			method='PATCH'
			data="$(jq <<<"$target" --raw-output 'include "./uri"; uriencode({
				content: .message,
			})')"
		else
			url="$ZULIP_SITE/api/v1/messages"
			method='POST'
			data="$(jq <<<"$target" --raw-output 'include "./uri"; uriencode({
				type: "channel",
				to: .channel,
				topic: .topic,
				content: .message,
			})')"
		fi
		curl -fsSX "$method" "$url" \
			-u "$ZULIP_BOT" \
			--data-raw "$data" \
		| jq '.'
	done

	# TODO make this "refresh interval" configurable?
	sleep 5
done
