# given a unix timestamp as input, return that same unix timestamp but pinned to local timezone's today
# ie, even if "now" is technically tomorrow UTC, this will return "today at midnight UTC"
#
# given a string as input, parse that string as "YYYY-MM-DDTHH:MM:SSZ" (UTC) and adjust it to midnight
def localday:
	if type == "string" then
		# The fromdateiso8601 builtin parses datetimes in the ISO 8601 format to a number of seconds since the Unix epoch (1970-01-01T00:00:00Z). The todateiso8601 builtin does the inverse.
		fromdateiso8601
		# The gmtime() function converts the calendar time timep to broken-down time representation, expressed in Coordinated Universal Time (UTC).
		| gmtime
	else
		# The localtime() function converts the calendar time timep to broken-down time representation, expressed relative to the user's specified timezone.
		localtime
	end
	| [ .[range(3)], 0, 0, 0, 0, 0 ]
	# The mktime builtin consumes "broken down time" representations of time output by gmtime and strptime.
	| mktime
;
