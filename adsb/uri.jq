# input: { foo: "bar", baz: [ "buzz" ] }
# output: "foo=bar&bazz=%5B%22buzz%22%5D"
def uriencode:
	to_entries
	| map(@uri "\(.key)=\(.value)")
	| join("&")
;
def uriencode(val):
	val
	| uriencode
;

# TODO find a better/cleaner way to manage, maintain, and include tiny libraries like this
