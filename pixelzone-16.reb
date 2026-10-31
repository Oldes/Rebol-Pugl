REBOL [
	Title:   "Pixelzone 16 - bitmap font atlas"
	Name:    pixelzone-16
	Version: 1.1.0
	Purpose: {
		The Pixelzone pixel font (by GGBotNet) rendered at its native 16
		pixels, crisp - one font pixel is one image pixel - as a texture
		atlas for Rebol-Pugl. Drawn twice as big with `scale: 2` and the
		default `nearest` filter, it stays crisp.

		Generated from Pixelzone.ttf; the atlas is embedded compressed, so
		no image codec is needed.

		    font: make-font do %pixelzone-16.reb
	}
	Note: "Check the font's licence before redistributing it"
]

make object! [
	name:        "Pixelzone"
	size:        16     ;; pixels per em - its native size
	line-height: 16     ;; every glyph fits between the line's top and this
	ascent:      12     ;; from the line's top to the baseline
	descent:     3

	;; White glyphs on transparent - colour them with `tint`. 1 pixel apart,
	;; so even `filter: 'linear` does not bleed between them.
	atlas: make image! 256x58   ;; white by default
	atlas/alpha: decompress #{
		78DAED5B89B2DB4008D3FFFFB43A6D5FBC20045EDB991EF392347D89E36331971084F8F9E0EBDFA5F7BFFFE3AFE7FA3E
		3FD7575F4FAE6DAFED799F70DAF5369CE1B8DCCF5375975E5F20BE09573BBEFAB30FAE9B68BF63FC8875BFD99CEAC60A
		C8AC00AB872BEFCFB6E5E3A2ACDE66982DCC5DF96C395C5AF696886844575EEE59F6C3703CC279F0E50FD9C2B3FCC737
		E1ACEB14C3128377A65D9382CC7DCF5E63F5B3F3F457D07D92960927BF3B8ED05B56CD49AE1F1DBF8B574FE4D7BBEA3E
		57BB512BA7B8CA247FB3EC939D820DFC6DF98D975FD1FF3DF9D1E7ABE0445BF273907F8A173179DD94DF0485D7B2557E
		E6F89782E323FD9B351BFD4FF76C969FDCD23F1A972EABACD6881A9BAFCADF4655B185E0EF254897E455CE65E10DB12D
		7F5C21DFA97F6CC4FF7C47F231297907E0C302730CBC3B8DFF7995025AABFC17B100DA44BC9BFFE598ACA18257D295EB
		C6B424E6401777F93C140DBFD45202842A17ED6726BF5275C4BF30211B53386FA01DD77579B9740BEF53148A3B500A13
		0E458DD9450F6073A42B6972BEF28B389C9D4FCA3889114CF25BC755073F620DC560C61344FD9A8800944C61F609F2DF
		2FDD6A16EE4AF982B034156C22C35A253AB4562AC864035CC2CFA11BE1651DA956044D6A9BE4575D39D9494D3DBDFCE4
		987DABFC538A9E4E54E4EFCBC313FD9FEB1EDBF203FBF2CF6BBE2CFFA87F72B27F87741521F2B9FCA446F119A26CC95F
		9D7F28D8FD79B8A3FF5DFFE7B83D91497C4063E4685BE437E0AD39938BF7CEFF697140EFFFADEE673D6DDB7F1FFC9BDB
		DE1176254AAB770977575F9A8F9C5F886B2C2CCC7BAF23031FB1B4A72B50537CB20B41F76A40CEA0222713405DB59BB4
		DC60B59FC77342BEF0413EF3692702E7DD0864B72534644532F3E5EEECCD6C0439F538249E1966CFBE2AAA209982D077
		BA11E4D4A96065E86FB3CD36C3085E187084F0109554A9FB9888D6762328A4135682616A47D1E4CA115B777CEB15F93D
		70A8C444261D4B37026D3742640B61539B395BF2E3DDF24F80F60489B250342D414A8B83151EC0FB748CFC0B6D347C33
		4B456B3B56950B866F9BEDF0805D461FD076A77F022D03EAB9E2EBFE0FB5FF223F0DDCDA91BF61E395917C61066A2ED9
		905F7B884FE5EFFC47B8694E3DFEC42A4D5DF9C4048FF11F1DB13B82FEAE377126FF9EFF77A43360EACF13F925FF2FF8
		9910232AB15B406F459F968D126B6F43B625B04D983345A69EA442607C98E87F8EFF6E7362A296B508065CA8736618FF
		D4422EF19D3C0A32BA73819528B7E61829D4D44D4429E586A803A5D6D9387B88CFF4642681661C86A92F0605431E61B3
		1F2F427434193C92AD23A5696AD6884E7C3F5BE93044760493FEABFC1D810ECFC287F0695A5F0B6E1FCD1E6EC9DF8C96
		0C8D476B62C2D446DB62AE26DA6208C3C85469F6532C916AA1D93D6C67BB93F94C7EFA590493FE83D219F29D71D853F9
		CB020A9C484908CDEC414DFC8DFCC45DFD47451797A9FA37D07E1E4749ABD655F4F2C348843AED90F774BD70A4D1AE68
		F805530BDDC87C4CDF181BEDDF32CDB4F2F392FC68D1681456F39646B6603EA1B4D69DD919E0CE488EC7B14EFEDA9D8E
		9799A61D44FED49514C89AF27F567C4612E8F2BF63181A4295919FD002BA74E83FF4A7997C62549D9F46089AB6D37343
		D33513A33926071C11D340A89258A6D80A17AA3539ECE406D42BB44FE1E3250A0F3AF3735B9C5DC383300D25D8A60E69
		675A01F1692ACCF433B1525D8A55341DCE744FAECC0267B82669CA3044B52AE96AD16118D2CC9AAD24517B6E68BBF18E
		91F173006EAB996FD00875D87FC01BF4FAD72A0546EDDD004E6613F55E0368E6595D4FA39B2B6F27190D5CAF4660D0D5
		C45F0FBFB1E8E40F8D40AFE5A61BB9E7FF3D726E6ABB60B0F5CA6F8EFFC308F560FF2CDAF6BF9290C42D04738AFF129C
		53FC4F05DC9B7F8F634606EC2452430BBE5D277FF8F74802AF56BB9050C866BBD91F14F57F03C005BC7372FD2EF8F75B
		3F7E0004CE23F6
	} 'zlib

	;; Drawn for a character it has no glyph for: a hollow box at capital
	;; height. none would skip such characters.
	fallback: [64x46 5x9 0x3 6]

	;; char [offset size bearing advance], for 318 characters:
	;;   offset size - its part of the atlas: the block can be given to
	;;                 `add-image/part` as it is, which uses only these two;
	;;                 a size of 0x0 has no pixels (a space)
	;;   bearing     - where its top-left goes, from the pen at the top-left
	;;                 of the line
	;;   advance     - how far the pen moves on
	;; A map, char to its block - looked up with `select/case`, so that A is
	;; not a.
	glyphs: #[
		#" " [0x0 0x0 0x0 2]  #"!" [124x25 1x9 0x3 2]  #"^"" [233x46 3x3 0x3 4]  #"#" [126x25 5x9 0x3 6]
		#"$" [242x0 3x11 0x2 4]  #"%" [132x25 3x9 0x3 4]  #"&" [136x25 4x9 0x3 5]  #"'" [237x46 1x3 0x3 2]
		#"(" [246x0 2x11 0x2 3]  #")" [249x0 2x11 0x2 3]  #"*" [220x46 3x4 0x3 4]  #"+" [180x46 3x5 0x5 4]
		#"," [247x46 1x2 0x11 2]  #"-" [3x56 3x1 0x7 4]  #"." [7x56 1x1 0x11 2]  #"/" [252x0 3x11 0x2 4]
		#"0" [141x25 3x9 0x3 4]  #"1" [145x25 2x9 0x3 3]  #"2" [148x25 3x9 0x3 4]  #"3" [152x25 3x9 0x3 4]
		#"4" [156x25 3x9 0x3 4]  #"5" [160x25 3x9 0x3 4]  #"6" [164x25 3x9 0x3 4]  #"7" [168x25 3x9 0x3 4]
		#"8" [172x25 3x9 0x3 4]  #"9" [176x25 3x9 0x3 4]  #":" [72x46 1x7 0x5 2]  #";" [70x46 1x8 0x5 2]
		#"<" [184x46 3x5 0x5 4]  #"=" [239x46 3x3 0x6 4]  #">" [188x46 3x5 0x5 4]  #"?" [180x25 3x9 0x3 4]
		#"@" [189x13 4x10 0x3 5]  #"A" [184x25 3x9 0x3 4]  #"B" [188x25 3x9 0x3 4]  #"C" [192x25 3x9 0x3 4]
		#"D" [196x25 3x9 0x3 4]  #"E" [200x25 3x9 0x3 4]  #"F" [204x25 3x9 0x3 4]  #"G" [208x25 3x9 0x3 4]
		#"H" [212x25 3x9 0x3 4]  #"I" [216x25 3x9 0x3 4]  #"J" [220x25 3x9 0x3 4]  #"K" [224x25 3x9 0x3 4]
		#"L" [228x25 3x9 0x3 4]  #"M" [232x25 5x9 0x3 6]  #"N" [238x25 3x9 0x3 4]  #"O" [242x25 3x9 0x3 4]
		#"P" [246x25 3x9 0x3 4]  #"Q" [0x13 3x11 0x3 4]  #"R" [250x25 3x9 0x3 4]  #"S" [0x36 3x9 0x3 4]
		#"T" [4x36 3x9 0x3 4]  #"U" [8x36 3x9 0x3 4]  #"V" [12x36 3x9 0x3 4]  #"W" [16x36 5x9 0x3 6]
		#"X" [22x36 3x9 0x3 4]  #"Y" [26x36 3x9 0x3 4]  #"Z" [30x36 3x9 0x3 4]  #"[" [4x13 2x11 0x2 3]
		#"\" [7x13 3x11 0x2 4]  #"]" [11x13 2x11 0x2 3]  #"^^" [224x46 3x4 0x3 4]  #"_" [9x56 3x1 0x12 4]
		#"`" [249x46 2x2 0x1 3]  #"a" [74x46 3x7 0x5 4]  #"b" [34x36 3x9 0x3 4]  #"c" [78x46 3x7 0x5 4]
		#"d" [38x36 3x9 0x3 4]  #"e" [82x46 3x7 0x5 4]  #"f" [42x36 3x9 0x3 4]  #"g" [46x36 3x9 0x5 4]
		#"h" [50x36 3x9 0x3 4]  #"i" [54x36 3x9 0x3 4]  #"j" [14x13 2x11 0x3 3]  #"k" [58x36 3x9 0x3 4]
		#"l" [62x36 1x9 0x3 2]  #"m" [86x46 5x7 0x5 6]  #"n" [92x46 3x7 0x5 4]  #"o" [96x46 3x7 0x5 4]
		#"p" [64x36 3x9 0x5 4]  #"q" [68x36 3x9 0x5 4]  #"r" [100x46 3x7 0x5 4]  #"s" [104x46 3x7 0x5 4]
		#"t" [72x36 3x9 0x3 4]  #"u" [108x46 3x7 0x5 4]  #"v" [112x46 3x7 0x5 4]  #"w" [116x46 5x7 0x5 6]
		#"x" [122x46 3x7 0x5 4]  #"y" [76x36 3x9 0x5 4]  #"z" [126x46 3x7 0x5 4]  #"{" [17x13 3x11 0x2 4]
		#"|" [21x13 1x11 0x2 2]  #"}" [23x13 3x11 0x2 4]  #"~" [228x46 4x4 0x5 5]  #"^(A0)" [0x0 0x0 0x0 2]
		#"¡" [80x36 1x9 0x5 2]  #"¢" [82x36 3x9 0x4 4]  #"£" [86x36 4x9 0x3 5]  #"¤" [192x46 3x5 0x5 4]
		#"¥" [91x36 3x9 0x3 4]  #"¦" [27x13 1x11 0x2 2]  #"§" [95x36 3x9 0x3 4]  #"¨" [13x56 3x1 0x1 4]
		#"©" [99x36 6x9 0x3 7]  #"ª" [130x46 3x7 0x3 4]  #"«" [134x46 5x7 0x5 6]  #"¬" [243x46 3x3 0x7 4]
		#"®" [106x36 6x9 0x3 7]  #"¯" [17x56 3x1 0x1 4]  #"°" [196x46 3x5 0x3 4]  #"±" [140x46 3x7 0x5 4]
		#"²" [200x46 3x5 0x3 4]  #"³" [204x46 3x5 0x3 4]  #"´" [252x46 2x2 0x1 3]  #"µ" [113x36 3x9 0x5 4]
		#"¶" [194x13 4x10 0x3 5]  #"·" [21x56 1x1 0x7 2]  #"¸" [0x56 2x2 0x12 3]  #"¹" [208x46 3x5 0x3 4]
		#"º" [144x46 3x7 0x3 4]  #"»" [148x46 5x7 0x5 6]  #"¼" [117x36 6x9 0x3 7]  #"½" [124x36 6x9 0x3 7]
		#"¾" [131x36 6x9 0x3 7]  #"¿" [138x36 3x9 0x5 4]  #"À" [0x0 3x12 0x0 4]  #"Á" [4x0 3x12 0x0 4]
		#"Â" [8x0 3x12 0x0 4]  #"Ã" [29x13 3x11 0x1 4]  #"Ä" [33x13 3x11 0x1 4]  #"Å" [37x13 3x11 0x1 4]
		#"Æ" [142x36 5x9 0x3 6]  #"Ç" [41x13 3x11 0x3 4]  #"È" [12x0 3x12 0x0 4]  #"É" [16x0 3x12 0x0 4]
		#"Ê" [20x0 3x12 0x0 4]  #"Ë" [45x13 3x11 0x1 4]  #"Ì" [24x0 3x12 0x0 4]  #"Í" [28x0 3x12 0x0 4]
		#"Î" [32x0 3x12 0x0 4]  #"Ï" [49x13 3x11 0x1 4]  #"Ð" [148x36 4x9 0x3 5]  #"Ñ" [53x13 3x11 0x1 4]
		#"Ò" [36x0 3x12 0x0 4]  #"Ó" [40x0 3x12 0x0 4]  #"Ô" [44x0 3x12 0x0 4]  #"Õ" [57x13 3x11 0x1 4]
		#"Ö" [61x13 3x11 0x1 4]  #"×" [212x46 3x5 0x5 4]  #"Ø" [153x36 5x9 0x3 6]  #"Ù" [48x0 3x12 0x0 4]
		#"Ú" [52x0 3x12 0x0 4]  #"Û" [56x0 3x12 0x0 4]  #"Ü" [65x13 3x11 0x1 4]  #"Ý" [60x0 3x12 0x0 4]
		#"Þ" [159x36 3x9 0x3 4]  #"ß" [69x13 4x11 0x3 5]  #"à" [199x13 3x10 0x2 4]  #"á" [203x13 3x10 0x2 4]
		#"â" [207x13 3x10 0x2 4]  #"ã" [163x36 3x9 0x3 4]  #"ä" [167x36 3x9 0x3 4]  #"å" [74x13 3x11 0x1 4]
		#"æ" [154x46 5x7 0x5 6]  #"ç" [171x36 3x9 0x5 4]  #"è" [211x13 3x10 0x2 4]  #"é" [215x13 3x10 0x2 4]
		#"ê" [219x13 3x10 0x2 4]  #"ë" [175x36 3x9 0x3 4]  #"ì" [223x13 3x10 0x2 4]  #"í" [227x13 3x10 0x2 4]
		#"î" [231x13 3x10 0x2 4]  #"ï" [179x36 3x9 0x3 4]  #"ð" [183x36 3x9 0x3 4]  #"ñ" [187x36 3x9 0x3 4]
		#"ò" [235x13 3x10 0x2 4]  #"ó" [239x13 3x10 0x2 4]  #"ô" [243x13 3x10 0x2 4]  #"õ" [191x36 3x9 0x3 4]
		#"ö" [195x36 3x9 0x3 4]  #"÷" [216x46 3x5 0x5 4]  #"ø" [160x46 5x7 0x5 6]  #"ù" [247x13 3x10 0x2 4]
		#"ú" [251x13 3x10 0x2 4]  #"û" [0x25 3x10 0x2 4]  #"ü" [199x36 3x9 0x3 4]  #"ý" [64x0 3x12 0x2 4]
		#"þ" [78x13 3x11 0x3 4]  #"ÿ" [82x13 3x11 0x3 4]  #"Ā" [86x13 3x11 0x1 4]  #"ā" [203x36 3x9 0x3 4]
		#"Ă" [68x0 3x12 0x0 4]  #"ă" [4x25 3x10 0x2 4]  #"Ą" [90x13 3x11 0x3 4]  #"ą" [207x36 3x9 0x5 4]
		#"Ć" [72x0 3x12 0x0 4]  #"ć" [8x25 3x10 0x2 4]  #"Ĉ" [76x0 3x12 0x0 4]  #"ĉ" [12x25 3x10 0x2 4]
		#"Ċ" [94x13 3x11 0x1 4]  #"ċ" [211x36 3x9 0x3 4]  #"Č" [80x0 3x12 0x0 4]  #"č" [16x25 3x10 0x2 4]
		#"Ď" [84x0 3x12 0x0 4]  #"ď" [20x25 4x10 0x2 5]  #"Đ" [215x36 4x9 0x3 5]  #"đ" [220x36 4x9 0x3 5]
		#"Ē" [98x13 3x11 0x1 4]  #"ē" [225x36 3x9 0x3 4]  #"Ĕ" [88x0 3x12 0x0 4]  #"ĕ" [25x25 3x10 0x2 4]
		#"Ė" [102x13 3x11 0x1 4]  #"ė" [229x36 3x9 0x3 4]  #"Ę" [106x13 3x11 0x3 4]  #"ę" [233x36 3x9 0x5 4]
		#"Ě" [92x0 3x12 0x0 4]  #"ě" [29x25 3x10 0x2 4]  #"Ĝ" [96x0 3x12 0x0 4]  #"ĝ" [100x0 3x12 0x2 4]
		#"Ğ" [104x0 3x12 0x0 4]  #"ğ" [108x0 3x12 0x2 4]  #"Ġ" [110x13 3x11 0x1 4]  #"ġ" [114x13 3x11 0x3 4]
		#"Ģ" [112x0 3x12 0x3 4]  #"ģ" [116x0 3x12 0x2 4]  #"Ĥ" [120x0 3x12 0x0 4]  #"ĥ" [124x0 3x12 0x0 4]
		#"Ħ" [237x36 5x9 0x3 6]  #"ħ" [243x36 4x9 0x3 5]  #"Ĩ" [118x13 3x11 0x1 4]  #"ĩ" [248x36 3x9 0x3 4]
		#"Ī" [122x13 3x11 0x1 4]  #"ī" [252x36 3x9 0x3 4]  #"Ĭ" [128x0 3x12 0x0 4]  #"ĭ" [33x25 3x10 0x2 4]
		#"Į" [126x13 3x11 0x3 4]  #"į" [130x13 3x11 0x3 4]  #"İ" [134x13 3x11 0x1 4]  #"ı" [166x46 3x7 0x5 4]
		#"Ĳ" [0x46 5x9 0x3 6]  #"ĳ" [138x13 3x11 0x3 4]  #"Ĵ" [132x0 3x12 0x0 4]  #"ĵ" [136x0 3x12 0x2 4]
		#"Ķ" [140x0 3x12 0x3 4]  #"ķ" [144x0 3x12 0x3 4]  #"ĸ" [170x46 3x7 0x5 4]  #"Ĺ" [148x0 3x12 0x0 4]
		#"ĺ" [152x0 2x12 0x0 3]  #"Ļ" [155x0 3x12 0x3 4]  #"ļ" [159x0 2x12 -1x3 2]  #"Ľ" [37x25 3x10 0x2 4]
		#"ľ" [41x25 2x10 0x2 3]  #"Ŀ" [6x46 3x9 0x3 4]  #"ŀ" [10x46 2x9 0x3 3]  #"Ł" [13x46 4x9 0x3 5]
		#"ł" [18x46 3x9 0x3 4]  #"Ń" [162x0 3x12 0x0 4]  #"ń" [44x25 3x10 0x2 4]  #"Ņ" [166x0 3x12 0x3 4]
		#"ņ" [48x25 3x10 0x5 4]  #"Ň" [170x0 3x12 0x0 4]  #"ň" [52x25 3x10 0x2 4]  #"ŉ" [56x25 3x10 0x2 4]
		#"Ŋ" [142x13 3x11 0x3 4]  #"ŋ" [22x46 3x9 0x5 4]  #"Ō" [146x13 3x11 0x1 4]  #"ō" [26x46 3x9 0x3 4]
		#"Ŏ" [174x0 3x12 0x0 4]  #"ŏ" [60x25 3x10 0x2 4]  #"Ő" [178x0 4x12 0x0 5]  #"ő" [64x25 4x10 0x2 5]
		#"Œ" [30x46 5x9 0x3 6]  #"œ" [174x46 5x7 0x5 6]  #"Ŕ" [183x0 3x12 0x0 4]  #"ŕ" [69x25 3x10 0x2 4]
		#"Ŗ" [187x0 3x12 0x3 4]  #"ŗ" [73x25 3x10 0x5 4]  #"Ř" [191x0 3x12 0x0 4]  #"ř" [77x25 3x10 0x2 4]
		#"Ś" [195x0 3x12 0x0 4]  #"ś" [81x25 3x10 0x2 4]  #"Ŝ" [199x0 3x12 0x0 4]  #"ŝ" [85x25 3x10 0x2 4]
		#"Ş" [150x13 3x11 0x3 4]  #"ş" [36x46 3x9 0x5 4]  #"Š" [203x0 3x12 0x0 4]  #"š" [89x25 3x10 0x2 4]
		#"Ţ" [154x13 3x11 0x3 4]  #"ţ" [158x13 3x11 0x3 4]  #"Ť" [207x0 3x12 0x0 4]  #"ť" [93x25 3x10 0x2 4]
		#"Ŧ" [40x46 3x9 0x3 4]  #"ŧ" [44x46 3x9 0x3 4]  #"Ũ" [162x13 3x11 0x1 4]  #"ũ" [48x46 3x9 0x3 4]
		#"Ū" [166x13 3x11 0x1 4]  #"ū" [52x46 3x9 0x3 4]  #"Ŭ" [211x0 3x12 0x0 4]  #"ŭ" [97x25 3x10 0x2 4]
		#"Ů" [170x13 3x11 0x1 4]  #"ů" [101x25 3x10 0x2 4]  #"Ű" [215x0 4x12 0x0 5]  #"ű" [105x25 4x10 0x2 5]
		#"Ų" [174x13 3x11 0x3 4]  #"ų" [56x46 3x9 0x5 4]  #"Ŵ" [220x0 5x12 0x0 6]  #"ŵ" [110x25 5x10 0x2 6]
		#"Ŷ" [226x0 3x12 0x0 4]  #"ŷ" [230x0 3x12 0x2 4]  #"Ÿ" [178x13 3x11 0x1 4]  #"Ź" [234x0 3x12 0x0 4]
		#"ź" [116x25 3x10 0x2 4]  #"Ż" [182x13 3x11 0x1 4]  #"ż" [60x46 3x9 0x3 4]  #"Ž" [238x0 3x12 0x0 4]
		#"ž" [120x25 3x10 0x2 4]  #"ſ" [186x13 2x11 0x3 3]
	]
]
