def yourDayData($date):
	{
		anchor: {
			date:  "2025-10-27T00:00:00Z", # this is assumed to be a Monday and should be midnight UTC so it is cleanly mathable
			order: "1234", # Monday person 1, Tuesday person 2, Wednesday person 3, Thursday person 4, Friday person 1, Monday person 2, etc (see illustration below)
		},
		days: 5, # how many days from Monday should be included (likely should be 5, 6, or 7 depending on whether you want to include the weekend in the rotation)
	}
;
def yourDayData: yourDayData(now);

# given a person from the order above, this should return the desired announcement message
def yourDayText($person):
	{
		"1": "@**|1234**", # syntax like this (with just the "User ID" in the mention) will auto-fill the user's chosen display name
		"2": "@**|2345**",
		"3": "@**|3456**",
		"4": "Person 4", # we use this syntax for people who are in the rotation, but aren't in Zulip (so that we know / can tell them when it's their day)
	}[$person] // $person
	| "\(.): it's your day! 🥳✨🫶"
;
