include "date"; # "def localday"

# $data: {
# 	anchor: {
# 		date:  "2025-10-27T00:00:00Z", # this is assumed to be a Monday and should be midnight UTC so it is cleanly mathable
# 		order: "1234", # Monday person 1, Tuesday person 2, Wednesday person 3, Thursday person 4, Friday person 1, Monday person 2, etc (see illustration below)
# 	},
# 	days: 5, # how many days from Monday should be included (likely should be 5, 6, or 7 depending on whether you want to include the weekend in the rotation)
# }
# $date: unix timestamp (now)
# yourDay({ ... }; now + range(30) * 24 * 60 * 60) - returns a stream of the next 30 days of "it's your day" including today
def yourDay($data; $date):
	# using the example data above,
	# on our "anchor week", the order was "1 2 3 4 1 _ _"
	# which means the next week, it is    "2 3 4 1 2 _ _"
	#                                     "3 4 1 2 3 _ _"
	#                                     "4 1 2 3 4 _ _"
	#                                     "1 2 3 4 1 _ _"
	# ie, we can "simply" left shift our anchor week pattern by the number of weeks we are away from it
	# or put another way, we can pre-step into the pattern the number of weeks past our anchor we are times the number of days per week (that's addition)
	# in the above pattern it looks like that's just "+ 1" when it's *really* "+ 5" but when you do "% 4" that is essentially just "+ 1" ✨

	($data.anchor.date | if type == "string" then fromdate else localday end) as $anchor
	| ($date | localday) as $today # $date, but the local timezone's today, as a unix timestamp at midnight UTC

	| ($anchor / (24 * 60 * 60) | floor) as $anchorDays
	| ($today / (24 * 60 * 60) | floor) as $todayDays

	| ($todayDays - $anchorDays) as $deltaDays

	| ($deltaDays / 7 | floor) as $weeksSinceAnchor

	| ($anchor | strftime("%u") | tonumber - 1) as $anchorDay # Monday is 0, Sunday is 7
	| if $anchorDay != 0 then error("math isn't math; \($anchorDay) should be 0") else . end
	| ($today | strftime("%u") | tonumber - 1) as $todayDay

	| if $todayDay >= $data.days then "" else
		$data.anchor.order
		| split("")
		| .[ ( $todayDay + ($data.days * $weeksSinceAnchor) ) % length ]
	end
;
def yourDay($data): yourDay($data; now);
