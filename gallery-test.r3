Rebol [
	Title:   "Rebol/Pugl - gallery test"
	Needs:   3.22.10
	Purpose: {
		A gallery: 40 images of 250x114 in a grid, in a scroller which
		fills the window. The grid takes as many columns as fit, centred,
		and is laid out again when the window is resized.

		The images are made here - each a 2x2 image of four colours,
		stretched with the linear filter into a smooth gradient - so no
		files are needed; any image! would do.

		Hover a card: a ring around it. Click: it is selected, and named in
		the title. The wheel - over a card too - and the bars scroll.

		Usage:
			r3 gallery-test.r3
	}
]

try [system/modules/pugl: none]
if modules-dir: get-env 'REBOL_MODULES_DIR [
	system/options/modules: dirize to-rebol-file modules-dir
]
pugl: import 'pugl

ui: do %widgets.reb

card-size: 250x114
gap:       10
count:     40

;;=============================================================================
print as-yellow "^/== The window and the scroller"
;;=============================================================================

window: open-window/title 1064x626 "Gallery"
print ["window scale:    " window/scale]
ui/init window

bg: add-image/size window make image! [1x1 30.30.38] 0x0 window/size
;; The scroller fills the window; its content is laid out below.
sc: ui/make-scroller window 0x0 window/size window/size

;;=============================================================================
print as-yellow "^/== The images"
;;=============================================================================

;; A colour of a hue, 0 to 1 round the colour wheel, at a lightness.
hue: func [h [number!] light [number!] /local f r g b][
	h: 6 * (h - round/floor h)
	f: h - round/floor h
	set [r g b] switch to integer! h [
		0 [reduce [1 f 0]]
		1 [reduce [1 - f 1 0]]
		2 [reduce [0 1 f]]
		3 [reduce [0 1 - f 1]]
		4 [reduce [f 0 1]]
		5 [reduce [1 0 1 - f]]
	]
	as-color
		round 255 * light * (0.35 + (0.65 * r))
		round 255 * light * (0.35 + (0.65 * g))
		round 255 * light * (0.35 + (0.65 * b))
]

;; Four corners, stretched smooth: one card's picture.
gradient: func [n [integer!] /local h img][
	h: n / count
	img: make image! 2x2
	img/(1x1): hue h 0.95
	img/(2x1): hue h + 0.12 0.75
	img/(1x2): hue h + 0.25 0.55
	img/(2x2): hue h + 0.40 0.35
	img
]

;; A card: a tracked group with the picture, its name, and a ring - shown
;; while hovered or selected.
cards: copy []
selected: none

repeat i count [
	c: make object! [
		group: picture: name: ring: none
		index: i
		hover?: false
	]
	c/group:   add-group sc/content 0x0
	c/ring:    add-image/size/part c/group ui/atlas -2x-2 card-size + 4x4 ui/part-of 2
	c/ring/nine-scale: ui/nine
	c/ring/visible?: false
	c/picture: add-image/size c/group gradient i 0x0 card-size
	c/picture/filter: 'linear
	c/name:    ui/add-label c/group ajoin ["Image " i] as-pair 10 card-size/y - 24
	c/group/track?: true
	c/group/cursor: 'hand
	append cards c
]

show-card: func [c][
	c/ring/visible?: did any [c/hover?  same? c selected]
	c/ring/tint: either same? c selected [255.210.120][none]
	c/name/tint: either same? c selected [255.210.120][none]
]

select-card: func [c /local old][
	old: selected
	selected: c
	if old [show-card old]
	show-card c
	window/title: ajoin ["Gallery - Image " c/index]
]

find-card: func [source][
	foreach c cards [if c/group == source [return c]]
	none
]

;;=============================================================================
;; The grid: as many columns as fit beside the vertical bar, centred; the
;; content as wide as the view, so there is no horizontal bar while one
;; column fits.
;;=============================================================================

columns: rows: 0

layout: function [][
	size: window/size
	step: card-size + gap
	cols: max 1 to integer! (size/x - ui/bar - gap) / step/x
	set 'rows to integer! round/ceiling count / cols
	set 'columns cols
	grid: as-pair (cols * step/x) + gap  (rows * step/y) + gap
	;; Without the vertical bar when it all fits under each other.
	view-w: size/x - either grid/y > size/y [ui/bar][0]
	left: max 0 to integer! (view-w - grid/x) / 2
	repeat i count [
		c: cards/:i
		col: remainder i - 1 cols
		row: to integer! (i - 1) / cols
		c/group/offset: as-pair left + gap + (col * step/x)  gap + (row * step/y)
	]
	ui/resize-scroller sc size as-pair max view-w grid/x grid/y
	bg/size: size
]

layout

print ["cards:           " length? cards "(expected 40)"]
print ["columns:         " columns "rows:" rows "(expected 4 10 at 1064 wide)"]
print ["content:         " sc/csize "(expected 1054x1250 - the view's width, 10 rows)"]
print ["view:            " sc/vsize "(expected 1054x626 - beside the vertical bar)"]
print ["no horizontal:   " none? sc/hthumb "(expected true)"]
print ["first card at:   " cards/1/group/offset "(expected 12x10 - centred: 2 to spare each side, and the gap)"]
print ["fifth card at:   " cards/5/group/offset "(expected 12x134 - the second row)"]
print ["image at it:     " (image-at window cards/1/group/offset + 20x20) == cards/1/picture "(expected true)"]
print ["below, clipped:  " none? image-at window 20x630 "(expected true - outside the window)"]
print ["textures:        " window/textures "(expected 43 - the atlas, the font, the background, 40 pictures)"]

;; Narrower: fewer columns, the content taller.
window/size: 600x400
layout
print ["at 600 wide:     " columns "columns" sc/csize "(expected 2 columns 590x2490)"]
window/size: 1064x626
layout

print {
WATCH: four columns of gradient cards, named, centred in the window; a
vertical bar on the right. Scroll with the wheel - over a card too - or the
bar; the keys scroll it once it has the focus (click between the cards).
Hover a card: a blue ring. Click one: a yellow ring and name, and the title
names it. Resize the window: as many columns as fit, centred again, the bar
only while it does not all fit. Escape or the close button ends the test.
}

do-events window func [event /local c][
	if c: find-card event/source [
		switch event/type [
			enter [c/hover?: true   show-card c]
			leave [c/hover?: false  show-card c]
			;; a click only when released over it again
			up    [if c/group/hover? [select-card c]]
		]
	]
	;; The scroller - and the wheel over a card, which goes to it.
	ui/handle event
	switch event/type [
		named-key [if event/key = 'escape [close-window window]]
		resize    [layout]
	]
]

print ["^/selected:" either selected [selected/index]["none"]]
print "done"
