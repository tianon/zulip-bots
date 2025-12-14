#!/usr/bin/env bash
set -Eeuo pipefail

# run this on a daily cron job at the time you'd like your announcements to show up

[ -s 'your-day.jq' ] # make sure we're in the right directory

: "${ZULIP_SITE:?missing; set to the base url of your Zulip instance, such as https://foobar.zulipchat.com}"
: "${ZULIP_BOT:?missing; set to the username:token of your bot user, such as foobar-bot@foobar.zulipchat.com:ABCDEFGHIJKLMNOPQRSTUVWXYZ}"

: "${ZULIP_TARGET_CHANNEL:?missing; set to the channel the message should be delivered to, such as foobar}"
: "${ZULIP_TARGET_TOPIC:=}" # optional, assuming "general chat" is enabled on your instance 😄

message="$(jq --null-input --raw-output -L. '
	include "your-day";
	include "config";
	now as $date # TODO some way to override this for testing
	| yourDay(yourDayData($date); $date)
	| if . == "" then
		empty
	else . end
	| yourDayText(.)
')"

if [ -z "$message" ]; then
	# if it's not someone's day, no notification / do nothing!
	exit
fi

# TODO some way to dry-run for testing
curl -fsSX POST "$ZULIP_SITE/api/v1/messages" \
	-u "$ZULIP_BOT" \
	--data-urlencode 'type=channel' \
	--data-urlencode "to=$ZULIP_TARGET_CHANNEL" \
	--data-urlencode "topic=$ZULIP_TARGET_TOPIC" \
	--data-urlencode "content=$message" \
| jq '.'
