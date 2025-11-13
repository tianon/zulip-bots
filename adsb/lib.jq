include "geo";
include "uri";

# input: "aircraft.json" file from a readsb instace
#   arg: locations - { "place": [ <lat (in degrees)>, <lon (in degrees)> ], "place2": [ ... ], ... }
#   arg: tar1090s - { "lol": "https://adsb.lol", "exchange": "https://globe.adsbexchange.com", ... }
# output: an upgraded (and lightly filtered) stream of "aircraft" objects with various "now" fields, "locations" with distance (in meters) and bearing (in degrees) from each location, "urls" for each tar1090 instance, and "text" for some fun/simple textual representations of various aspects of the data
def aircraft(locations; tar1090s):
	.now as $now

	| .aircraft[]

	| select(
		.hex
		and .lat and .lon
	)

	| map_values(
		if type == "string" then
			# trim any dead space ("flight": "XXXXXX " for example)
			gsub("^[[:space:]]+|[[:space:]]+$"; "")
		else . end
	)

	| . * {
		$now,
		now_seen: ($now + .seen),
		now_seen_pos: ($now + .seen_pos),
	}

	| .locations = (
		[ .lat, .lon ] as $other
		| locations
		| map_values(
			{ self: ., $other }
			| { pos: .self, dist: haversine_distance, bear: bearing }
		)
	)

	| .urls = (
		uriencode({
			# https://github.com/wiedehopf/tar1090/blob/abbc708f719b5c5e3b1ecd786baf8bdbf28f137b/README-query.md
			icao: .hex,
			showTrace: (.now_seen_pos | strftime("%Y-%m-%d")),
			timestamp: .now_seen_pos,
			zoom: "15",
		}) as $query
		| tar1090s
		| map_values(rtrimstr("/") + "/?" + $query)
	)

	| (.alt_baro // .alt_geo // .altitude // "") as $alt
	| (.flight // .r // .hex // "") as $flight
	| .text = {
		flight: $flight,
		type: (
			# https://github.com/wiedehopf/tar1090/blob/abbc708f719b5c5e3b1ecd786baf8bdbf28f137b/html/markers.js#L1324-L1325
			if $alt == "ground" and IN(.type; "adsb_icao_nt", "tisb_other", "tisb_trackfile") then "▪️"

			# TODO consider adjusting the config to allow a different "radius" per category?  that way balloon and glider could have a wider radius, for example (because they're interesting/unique even further out)
			# technically this is already possible, as the "config" functions receive the airplane object itself as input

			else
				{
					# https://github.com/wiedehopf/tar1090/blob/abbc708f719b5c5e3b1ecd786baf8bdbf28f137b/html/markers.js#L1217-L1247
					# https://www.adsbexchange.com/emitter-category-ads-b-do-260b-2-2-3-2-5-2/
					"A7": "🚁", # "helicopter"
					"B1": "🪂", # "glider"
					"B2": "🎈", # "balloon"
					"B3": "🪂", # parachutist / skydiver
					"B4": "🪂", # ultralight / hang-glider / paraglider
					"B6": "🎮", # unmanned aerial vehicle
					"B7": "🛰", # space / trans-atmospheric vehicle
					"C1": "🚑", # surface vehicle – emergency vehicle
					"C2": "🧳", # "ground_service"
				}[.category // ""]

				// "🛩" # if we don't know, just assume it's a plane
			end

			+ if $flight | startswith("JANET") then
				"🛸"

			elif (.ownOp // "") | contains("POLICE") then
				"🚓"

			else "" end

		),
		locations: (
			.locations
			| [ "⬆️", "↗️", "➡️", "↘️", "⬇️", "↙️", "⬅️", "↖️" ] as $bearings # 8 points on a compass, in "[0-360)" order
			| map_values({
				dist: "\(.dist | round)m",
				bear: $bearings[.bear / (360 / 8) | round],
				# TODO perhaps the "near" values I've got in "targets" right now actually belong here as a "near: [true|false]" (because if you're using the same location in several targets, you probably want the same "nearness" value for all of them 🤔)
			})
		),
		altitude: (
			# https://github.com/wiedehopf/tar1090/blob/abbc708f719b5c5e3b1ecd786baf8bdbf28f137b/html/script.js#L9070-L9083
			if IN($alt; "", "ground") then
				$alt
			else
				"\($alt | round) ft"
			end + (
				(.baro_rate // .vert_rate // 0) as $rate
				# https://github.com/wiedehopf/tar1090/blob/abbc708f719b5c5e3b1ecd786baf8bdbf28f137b/html/formatter.js#L106-L114
				| if $rate > 245 then
					" 🛫"
				elif $rate < -245 then
					" 🛬"
				else "" end
			)
			| ltrimstr(" ")
		),
		speed: (
			# https://github.com/wiedehopf/tar1090/blob/abbc708f719b5c5e3b1ecd786baf8bdbf28f137b/html/formatter.js#L199-L209
			if .gs then
				"\(.gs * 1.15078 | round) mph"
			else "" end
		),
	}
;

# input: upgraded "aircraft" objects
#   arg: targets - { channel: "foo", topic: "bar", near: { "place": 100, "place2": 200 }, url: "lol" }
# output: those same objects, filtered to only aircraft near one of the specified places with a list of targets and which place they're nearest
def filter_targets(targets):
	.targets = [
		.locations as $locs
		| targets
		| .near = (
			.near
			| to_entries
			| map(
				select($locs[.key] and $locs[.key].dist <= (env.ADSB_NEAR_METERS_OVERRIDE // .value | tonumber))
				| .key
			)
			| select(length > 0)
			| min_by($locs[.].dist)
		)
		| { channel, topic, near, url }
	]
	| select(.targets | length > 0)
;

# input: "aircraft.json" file from a readsb instace
#   arg: locations - as in "aircraft" above
#   arg: tar1090s - as in "aircraft" above
#   arg: targets - as in "filter_targets" above
# output: [ { channel: "...", topic: "...", message: "..." } ]
def zulip_targets(locations; tar1090s; targets):
	(env.ADSB_NEAR_SECONDS_OVERRIDE | tonumber? // 60) as $nearSeconds # how many seconds a position is allowed to be "stale" before we consider it dead
	| now as $now
	| [
		aircraft(locations; tar1090s)
		| select($now - .now_seen_pos <= $nearSeconds)
		| filter_targets(targets)
		| .targets[] as $target
		| $target * { message: (
			def sanitize($join; bits):
				[ bits | select((. // "") != "") ] | join($join)
			;
			sanitize("\n";
				(
					.urls[$target.url] as $url
					| sanitize(" ";
						.text.type,
						.text.flight,
						if .r and .text.flight != .r then "(\(.r))" else empty end,
						empty
					)
					| "# " + if $url then "[\(.)](\($url))" else . end
				),

				sanitize(" ";
					(.text.locations[$target.near] | .bear, "**\(.dist)** from \($target.near)"),
					"--",
					sanitize("; ";
						.text.altitude,
						.text.speed,
						empty
					)
				),

				sanitize("; ";
					.desc,
					.year,
					.ownOp,
					empty
				),

				empty
			)
		) }
	]
	| group_by(.channel, .topic)
	| map({
		channel: .[0].channel,
		topic: .[0].topic,
		message: (map(.message) | join("\n\n")),
	})
;
