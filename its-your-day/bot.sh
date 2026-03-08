#!/usr/bin/env bash
set -Eeuo pipefail

# run this on a daily cron job at the time you'd like your announcements to show up

[ -s 'your-day.jq' ] # make sure we're in the right directory

message="$(jq --null-input --raw-output -L. '
	include "config";
	include "your-day";
	(env.SOURCE_DATE_EPOCH // now | tonumber) as $date
	| yourDay(yourDayData($date); $date)
	| if . != "" then
		yourDayText(.)
	else
		# when it is not an assigned day, show a compressed preview including the next 7 days beyond today
		# | Su | Mo | Tu | We | Th | Fr | Sa | Su |
		# |:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
		# | | 1 | 2 | 3 | 4 | 5 | 1 | |
		reduce ($date + range(8) * 24 * 60 * 60) as $future ([ "|", "|", "|" ];
			map(. += " ")
			| .[0] += ($future | strftime("%a")[0:2])
			| .[1] += ":-:"
			| .[2] += yourDay(yourDayData($future); $future)
			| map(. += " |")
		)
		| join("\n")
	end
')"

if [ -z "$message" ]; then
	# if there's no message, do nothing!
	exit
fi

# SOURCE_DATE_EPOCH="$(date --date '2026-03-01' +%s)" DRY_RUN=1 ./bot.sh
if [ -n "${DRY_RUN:-}" ]; then
	echo "$message"
	exit
fi

: "${ZULIP_SITE:?missing; set to the base url of your Zulip instance, such as https://foobar.zulipchat.com}"
: "${ZULIP_BOT:?missing; set to the username:token of your bot user, such as foobar-bot@foobar.zulipchat.com:ABCDEFGHIJKLMNOPQRSTUVWXYZ}"

: "${ZULIP_TARGET_CHANNEL:?missing; set to the channel the message should be delivered to, such as foobar}"
: "${ZULIP_TARGET_TOPIC:=}" # optional, assuming "general chat" is enabled on your instance 😄

curl -fsSX POST "$ZULIP_SITE/api/v1/messages" \
	-u "$ZULIP_BOT" \
	--data-urlencode 'type=channel' \
	--data-urlencode "to=$ZULIP_TARGET_CHANNEL" \
	--data-urlencode "topic=$ZULIP_TARGET_TOPIC" \
	--data-urlencode "content=$message" \
| jq '.'
