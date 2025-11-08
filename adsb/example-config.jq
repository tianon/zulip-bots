def locations:
	{
		disneyland: [ 33.812511, -117.918976 ], # Disneyland Park, Anaheim, CA, USA
		legoland: [ 33.126194, -117.310623 ], # Legoland California, CA, USA
	}
;

def tar1090s:
	{
		lol: "https://adsb.lol",
		fi: "https://globe.adsb.fi",
		globe: "https://globe.adsbexchange.com",
	}
;

def targets:
	1000 as $nearDisneyland # meters (this should cover all the way to the bottom of California Adventure)
	| 500 as $nearLegoland # meters (this radius covers the hotel and most of the rest of the park)

	{
		channel: "disneyland-lovers",
		topic: "🛩 Airplanes",
		near: { disneyland: $nearDisneyland },
		url: "globe",
	},

	{
		channel: "my-lego-freaks",
		topic: "DO YOU KNOW WHAT KIND OF PLANE THIS IS?",
		near: { legoland: $nearLegoland },
		url: "fi",
	},

	{
		channel: "theme-park-lovers",
		topic: "🛫 🫶 🎡🛩🎢 🫶 🛬",
		near: {
			disneyland: $nearDisneyland,
			legoland: $nearLegoland,
		},
		url: "lol",
	},

	empty
;
