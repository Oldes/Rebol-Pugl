Rebol [
	Title:   "Rebol/Pugl - bitmap font test"
	Needs:   3.22.10
	Purpose: {
		Loads the Pixelzone 16 font, makes a font of it with `make-font`,
		and shows text with `add-text`: one node per text, its glyphs drawn
		from the font's atlas in one go, coloured with `tint`. Several
		lines, aligned; characters the font has no glyph for, drawn as its
		fallback; a button whose label counts its clicks. Escape or the
		close button ends it.

		Usage:
			r3 font-test.r3
	}
]

print ["Running test on Rebol build:" mold to-block system/build]

try [system/modules/pugl: none]
if modules-dir: get-env 'REBOL_MODULES_DIR [
	system/options/modules: dirize to-rebol-file modules-dir
]
pugl: import 'pugl

;;=============================================================================
print as-yellow "^/== The font file"
;;=============================================================================

;; The atlas is embedded compressed: loading it needs `decompress` and
;; nothing else - no image codec.
spec: do %pixelzone-16.reb
print ["name:            " spec/name spec/size "px"]
print ["atlas:           " spec/atlas/size "(expected 256x55)"]
print ["glyphs:          " length? spec/glyphs "(expected 318)"]
print ["a map:           " map? spec/glyphs "(expected true)"]
;; Every ink pixel opaque - 255 - and nothing else: the alpha came through.
ink: 0  other: 0
foreach a spec/atlas/alpha [case [a = 255 [ink: ink + 1]  a <> 0 [other: other + 1]]]
print ["ink pixels:      " ink "(expected 4932)"]
print ["half-opaque:     " other "(expected 0 - crisp)"]
print ["white:           " spec/atlas/rgb/1 spec/atlas/rgb/2 spec/atlas/rgb/3 "(expected 255 255 255)"]
print ["A is not a:      " not equal? select/case spec/glyphs #"A" select/case spec/glyphs #"a" "(expected true)"]
print ["a space:         " mold select/case spec/glyphs #" " "(expected size 0x0 - no pixels)"]
print ["fallback:        " mold spec/fallback "(a hollow box)"]

;;=============================================================================
print as-yellow "^/== make-font"
;;=============================================================================

;; The glyphs are read once into a table of the extension's; the handle
;; keeps the atlas.
font: make-font spec
print ["font:            " mold font]
print ["line height:     " font/line-height "(expected 16)"]
print ["glyphs:          " font/glyphs "(expected 318)"]
print ["the same atlas:  " same? font/atlas spec/atlas "(expected true)"]
print ["fallback?:       " font/fallback? "(expected true)"]
print ["read-only:       " error? try [font/line-height: 20]]
print ["not an object:   " error? try [make-font 42]]
print ["a bad glyph:     " error? try [make-font make spec [glyphs: #[#"a" [0x0 999x999 0x0 4]]]] "(expected true - outside the atlas)"]

;; Without a fallback, a character it has no glyph for is skipped; with a
;; char as the fallback, that char's glyph stands in.
bare: make-font make spec [fallback: none]
print ["no fallback:     " bare/fallback? "(expected false)"]
quest: make-font make spec [fallback: #"?"]
print ["a char's glyph:  " quest/fallback? "(expected true)"]

;; Measured: the widest line, by the lines times the line height.
print ["text-size:       " text-size font "Cancel" "(expected 22x16)"]
print ["two lines:       " text-size font "Cancel^/OK" "(expected 22x32 - the widest)"]
print ["empty:           " text-size font "" "(expected 0x16 - one empty line)"]
print ["trailing newline:" text-size font "OK^/" "(expected 8x32 - and an empty last line)"]
print ["missing, boxed:  " text-size font "a漢b" "vs skipped" text-size bare "a漢b" "(the box's 4 more)"]

;;=============================================================================
print as-yellow "^/== Text in a window"
;;=============================================================================

window: open-window/title 460x300 "Pixelzone 16"
print ["scale:           " window/scale "(device pixels per unit - a font pixel is that many)"]

czech: "Příliš žluťoučký kůň úpěl ďábelské ódy."
line1: add-text window font czech 12x12
print ["text handle:     " mold line1]
print ["the handle type: " line1/type "(expected pugl-text)"]
print ["its text:        " mold line1/text]
;; Every character back as it was given - case and diacritics included.
print ["round trip:      " line1/text == czech "(expected true)"]
line1/text: "Ěščřžýáíé ĚŠČŘŽÝÁÍÉ"
print ["set and read:    " line1/text == "Ěščřžýáíé ĚŠČŘŽÝÁÍÉ" "(expected true)"]
line1/text: czech
print ["its size:        " line1/size "=" text-size font line1/text]
print ["its font:        " line1/font == font "(expected true)"]
print ["align:           " line1/align "(expected left)"]
print ["one texture:     " window/textures "(expected 1 - the atlas)"]
print ["size is read-only:" error? try [line1/size: 10x10]]
print ["not an image:    " error? try [line1/image]]
print ["image-at finds it:" (image-at window 20x16) == line1 "(expected true)"]

;; Twice as big, still crisp: scaled with the default `nearest`.
big: add-text window font "Hello, Pugl!" 12x36
big/scale: 2
big/tint: 255.200.0

;; Several lines, centred and right-aligned within the widest.
lines: "Left, centre^/and right^/aligned lines"
centred: add-text window font lines 12x80
centred/align: 'center
righted: add-text window font lines 170x80
righted/align: 'right
print ["three lines:     " centred/size "(expected" text-size font lines ")"]
print ["a bad align:     " error? try [centred/align: 'justify]]

;; Characters it has no glyph for: boxed with the fallback; skipped without.
boxed: add-text window font "Boxed: → ★ 漢" 12x140
boxed/tint: 255.150.150
skipped: add-text window font "Skipped: → ★ 漢" 12x160
skipped/font: bare
skipped/tint: 150.150.150
print ["another font:    " skipped/font == bare]

;; Another font: Home Video, 20 px, monospaced - every character 12 wide -
;; and capitals only: its lowercase is drawn the same, and stored once.
video: make-font do %homevideo-20.reb
print ["Home Video:      " mold video]
print ["line height:     " video/line-height "(expected 18)"]
print ["glyphs:          " video/glyphs "(expected 307)"]
print ["monospaced:      " text-size video "OK" text-size video "WW" "(expected 24x18 both)"]
caps: add-text window video "Home Video: OK" 200x186
caps/tint: 150.255.150
print ["textures:        " window/textures "(expected 2 - each font's atlas)"]

;; Faded and in colour.
soft: add-text window font "tinted, at 60%" 12x190
soft/tint: 120.200.255
soft/opacity: 60%

;; A button: a frame, nine-scaled, with its label centred - measured with
;; `text-size`; the label's text is replaced on every click.
frame: make image! [24x24 70.70.90]
repeat y 24 [
	repeat x 24 [
		if any [x <= 2  x > 22  y <= 2  y > 22][
			frame/(as-pair x y): 160.160.200
		]
	]
]
button: add-group window 12x230
face:   add-image/size button frame 0x0 140x32
face/nine-scale: [3x3 18x18]
label:  add-text button font "Click me" 0x0
center-label: does [
	label/offset: as-pair (140 - label/size/x) / 2  (32 - label/size/y) / 2
]
center-label
button/track?: true
button/cursor: 'hand
print ["textures:        " window/textures "(expected 3 - the two atlases and the frame)"]

print {
WATCH: a Czech line; a big orange "Hello, Pugl!"; the same three lines
centred and right-aligned; a pink line with arrows, a star and a Chinese
character drawn as hollow boxes, and a grey one where they are skipped; a
faded light blue line; a green "HOME VIDEO: OK" in the wider, capitals-only
Home Video font; a button. Hover the button - it lights up - and
click it: its label counts the clicks.
Escape or the close button ends the test.
}

clicks: 0
pressed?: false
do-events window func [event][
	if event/source == button [
		switch event/type [
			enter    [face/tint: 200.220.255]
			leave    [face/tint: none]
			down     [pressed?: true   face/tint: 140.160.220]
			up       [
				;; A click only when released over it again.
				if all [pressed?  button/hover?][
					clicks: clicks + 1
					label/text: ajoin ["Clicked " clicks either clicks = 1 [" time"][" times"]]
					center-label
				]
				pressed?: false
				face/tint: either button/hover? [200.220.255][none]
			]
		]
	]
	if all [event/type = 'named-key  event/key = 'escape][close-window window]
]

print ["^/window closed - open?:" window/open? "(expected false)"]
print ["label after close:" mold label/text "(expected none)"]
print "done"
