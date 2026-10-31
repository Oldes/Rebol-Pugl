Rebol [
	Title:   "Rebol/Pugl - nine-scale test, one case at a time"
	Needs:   3.22.10
	Purpose: {
		Shows one nine-scale case at a time, until a key is pressed:
		Right or Space - the next case, Left - the previous one, Escape or
		the close button - the end. Each case prints what it shows and
		what to look for.

		The test image makes every piece tell itself apart: four corners
		of four colours, edges striped ACROSS their length (stretching
		only spreads the stripes, never turns them), and a checkered
		middle (any shear or seam shows at once). Top-left, the image
		itself, four times bigger, for reference.

		Usage:
			r3 nine-test.r3
	}
]

try [system/modules/pugl: none]
if modules-dir: get-env 'REBOL_MODULES_DIR [
	system/options/modules: dirize to-rebol-file modules-dir
]
pugl: import 'pugl

;; 24x24: corners 8x8, edges 8 wide, the middle 8x8 - `nine-scale: [8x8 8x8]`.
frame: make image! 24x24
repeat y 24 [
	repeat x 24 [
		on-left: x <= 8   on-right:  x > 16
		on-top:  y <= 8   on-bottom: y > 16
		frame/(as-pair x y): case [
			all [on-left  on-top]    [220.60.60]    ;; red
			all [on-right on-top]    [60.200.60]    ;; green
			all [on-left  on-bottom] [60.100.230]   ;; blue
			all [on-right on-bottom] [230.200.40]   ;; yellow
			;; top and bottom edges: stripes across - vertical lines
			any [on-top on-bottom]   [either odd? x [240.240.240][130.130.130]]
			;; left and right edges: stripes across - horizontal lines
			any [on-left on-right]   [either odd? y [240.240.240][130.130.130]]
			;; the middle: a checkerboard
			true               [either odd? x + y [70.70.110][40.40.60]]
		]
	]
]

;; The same, twice, side by side in a 48x24 atlas - for `part`.
atlas: make image! [48x24 255.0.255]
repeat y 24 [repeat x 24 [atlas/(as-pair x + 24 y): frame/(as-pair x y)]]

window: open-window/title 640x480 "nine-scale"
reference: add-image window frame 8x8
reference/scale: 4
content: add-group window 120x8   ;; the case, right of the reference

nine: function [
	"A nine-scaled frame in the case"
	offset [pair!] size [pair!]
][
	img: add-image/size content frame offset size
	img/nine-scale: [8x8 8x8]
	img
]

cases: [
	"At its own size, 24x24 - nothing stretched"
	"Exactly the reference, at 1:1 here and scaled 4x - left"
	[nine 0x0 24x24  plain: add-image content frame 40x0  plain/scale: 4]

	"Stretched wide, 300x60"
	"Corners 8x8 and square; the top and bottom edges' vertical lines spread apart; the left and right edges unchanged"
	[nine 0x0 300x60]

	"Stretched tall, 60x300"
	"The left and right edges' horizontal lines spread apart; the top and bottom ones unchanged"
	[nine 0x0 60x300]

	"Big, 400x300"
	"Corners 8x8; the checkerboard stretched evenly - its squares rectangles, all the same, no diagonal"
	[nine 0x0 400x300]

	"Odd sizes - 101x37, 37x101, 53x53"
	"No seams between the pieces; nothing shifted by a pixel"
	[nine 0x0 101x37  nine 120x0 37x101  nine 180x0 53x53]

	"Squeezed below its corners - 12x12, 20x8, 8x20, 4x4"
	"The corners shrink alike, keep their colours in their places, and no middle or edge is drawn"
	[nine 0x0 12x12  nine 30x0 20x8  nine 70x0 8x20  nine 100x0 4x4]

	"Tiled - fill: 'tile, 300x100"
	"The edges and the middle repeat at their own size, the last ones cut; corners untouched"
	[img: nine 0x0 300x100  img/fill: 'tile]

	"Rounded - fill: 'round, 300x100 and 290x95"
	"Whole repeats only, each a little stretched or squeezed; no cut stripe or square"
	[img: nine 0x0 300x100  img/fill: 'round  img: nine 0x120 290x95  img/fill: 'round]

	"Turned 30 degrees around its middle"
	"Turned as one, with no shear - every corner still a square, the checkerboard squares still rectangles"
	[img: nine 100x50 240x120  img/pivot: 120x60  img/rotation: 30]

	"Scaled 2 with `scale`, at size 100x50"
	"Twice the frame next to it at size 200x100: corners 16x16 here - scale grows all, size only stretches"
	[img: nine 0x0 100x50  img/scale: 2  nine 0x120 200x100]

	"Scaled 2x1 AND turned - a shear, as the maths says"
	"EXPECTED to look sheared: scaling one axis of something turned is a shear"
	[img: nine 100x50 200x100  img/pivot: 100x50  img/rotation: 30  img/scale: 2x1]

	"In a group which is turned 20 degrees"
	"The same as turning it itself: no shear"
	[g: add-group content 100x50  g/rotation: 20
	 img: add-image/size g frame 0x0 240x120  img/nine-scale: [8x8 8x8]]

	"In a group scaled 1.5 - fractional sizes on the screen"
	"Pieces meet without gaps or overlaps, even off whole pixels"
	[g: add-group content 0x0  g/scale: 1.5
	 img: add-image/size g frame 0x0 151x77  img/nine-scale: [8x8 8x8]]

	"From an atlas frame - part [24x0 24x24], the second copy"
	"The same as from the image itself; nothing of the magenta around it"
	[img: add-image/size/part content atlas 0x0 300x100 [24x0 24x24]  img/nine-scale: [8x8 8x8]]

	"Linear filter, 300x100"
	"Smooth, no shear; the edges between pieces may soften a little"
	[img: nine 0x0 300x100  img/filter: 'linear]

	"Window scale 1.5 - zoomed"
	"Everything 1.5 times bigger, the reference too; pixels uneven with nearest, but no shear"
	[nine 0x0 200x100  window/scale: 1.5]

	"Window scale 2 - zoomed"
	"Everything twice as big, crisp"
	[nine 0x0 200x100  window/scale: 2]
]

current: 1
total: (length? cases) / 3
screen-scale: window/scale   ;; nothing set yet: the screen's

show-case: function [n [integer!]][
	;; A fresh case: the old one removed with all in it, the zoom undone.
	remove-image content
	set 'content add-group window 120x8
	window/scale: none
	set [title note code] skip cases n - 1 * 3
	window/title: ajoin ["nine-scale " n "/" total ": " title]
	print rejoin ["^/" as-yellow ajoin ["Case " n "/" total ": " title]]
	print ["  look for:" note]
	do code
	;; After the case: two of them set their own.
	print ["  window scale:" window/scale "- the screen's is" screen-scale]
	window/title: ajoin ["nine-scale " n "/" total ": " title " (scale " window/scale ")"]
]

print {
Right or Space - the next case, Left - the previous one, Escape - the end.
Tell which case, by its number, looks wrong.}
show-case current

;; A `func`, not a `function`: `current` is the script's, not a local.
do-events window func [event][
	if event/type = 'named-key [
		switch event/key [
			right  [if current < total [current: current + 1  show-case current]]
			left   [if current > 1     [current: current - 1  show-case current]]
			escape [close-window window]
		]
	]
	if all [event/type = 'key  event/key = #" "][
		current: either current < total [current + 1][1]
		show-case current
	]
]
print "done"
