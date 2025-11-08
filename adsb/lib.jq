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
			if $flight | startswith("JANET") then "🛸"

			elif (.ownOp // "") | contains("POLICE") then "🚔"

			elif $alt == "ground" and IN(.type; "adsb_icao_nt", "tisb_other", "tisb_trackfile") then "▪️"

			else ({
				# https://github.com/wiedehopf/tar1090/blob/abbc708f719b5c5e3b1ecd786baf8bdbf28f137b/html/markers.js#L734

				"🎈": [ "BALL" ],

				"🚁": [ "H60", "S92", "NH90", "AS32", "AS3B", "PUMA", "TIGR", "MI24", "AS65", "S76", "GAZL", "AS50", "AS55", "ALO2", "ALO3", "R22", "R44", "R66", "EC55", "A169", "H160", "A139", "EC75", "A189", "A149", "S61", "S61R", "EC25", "EH10", "H53", "H53S", "U2", "C2", "E2", "H47", "H46", "HAWK", "GYRO" ],

				"🪂": [ "GLID", "S6", "S10S", "S12", "S12S", "ARCE", "ARCP", "DISC", "DUOD", "JANU", "NIMB", "QINT", "VENT", "VNTE", "A20J", "A32E", "A32P", "A33E", "A33P", "A34E", "AS14", "AS16", "AS20", "AS21", "AS22", "AS24", "AS25", "AS26", "AS28", "AS29", "AS30", "AS31", "DG80", "DG1T", "LS10", "LS9", "LS8", "TS1J", "PK20", "LK17", "LK19", "LK20" ],

			} | with_entries({ key: .value[], value: .key }))[.t // ""]

			// {
				# https://github.com/wiedehopf/tar1090/blob/abbc708f719b5c5e3b1ecd786baf8bdbf28f137b/html/markers.js#L1217-L1247
				"A7": "🚁", # "helicopter"
				"B1": "🪂", # "glider"
				"B2": "🎈", # "balloon"
				"C2": "🧳", # "ground_service"
				# TODO do all the ".t" values above have these categories set appropriately? ie, could I rely just on category for all these instead of maintaining those lists?
			}[.category // ""]

			// "🛩" # if we don't know, just assume it's a plane
		end),
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
