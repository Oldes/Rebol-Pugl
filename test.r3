Rebol [
	Title:   "Rebol/Pugl extension test"
	Needs:   3.22.10
	Purpose: {
		Opens a window and prints the events it produces. Meant to be run
		by a human - close the window (or press Escape) to end it.

		Usage:
			r3 test.r3
	}
]


print ["Running test on Rebol build:" mold to-block system/build]

;; make sure that we load a fresh extension
try [system/modules/pugl: none]

;; a locally built library can be pointed at without installing it
if modules-dir: get-env 'REBOL_MODULES_DIR [
	system/options/modules: dirize to-rebol-file modules-dir
]

pugl: import 'pugl
? pugl

;;=============================================================================
print as-yellow "^/== Opening a window"
;;=============================================================================

;; /hidden, so the accessors are read before anything is on screen.
window: open-window/title/at/hidden 480x320 "Rebol Pugl extension" 200x120

print ["window:   " window]
print ["id:       " window/id]
print ["open?:    " window/open? "(expected true)"]
print ["visible?: " window/visible? "(expected false)"]
print ["title:    " mold window/title {(expected "Rebol Pugl extension")}]
print ["size:     " window/size "(expected 480x320)"]
print ["offset:   " window/offset]
print ["scale:    " window/scale "(sizes and offsets are in device pixels)"]

;; every accessor which can be read can also be written, except
;; scale, id, visible? and open?
window/title: "Rebol Pugl extension - move the mouse"
print ["title:    " mold window/title]
window/size: 500x340
print ["size:     " window/size "(expected 500x340)"]
print ["a bad size is refused:   " error? try [window/size: 0x10]]
print ["a bad type is refused:   " error? try [window/title: 42]]
print ["read-only scale:         " error? try [window/scale: 2.0]]
print ["an unknown word:         " error? try [window/foo]]
print ["the handle type:         " window/type]

;;=============================================================================
print as-yellow "^/== Closing a window"
;;=============================================================================

;; A closed window keeps its handle: it reports `open?` false and none for
;; everything else, rather than pointing at freed memory.
spare: open-window/hidden 200x100
spare-img: add-image spare make image! 8x8 0x0
print ["spare:           " spare]
print ["open?:           " spare/open? "(expected true)"]
print ["close-window:    " close-window spare "(expected true)"]
print ["open? after:     " spare/open? "(expected false)"]
print ["size after:      " mold spare/size "(expected none)"]
print ["title after:     " mold spare/title "(expected none)"]
print ["id after:        " spare/id "(expected 0)"]
print ["molded:          " spare "(expected closed)"]
print ["closing twice:   " close-window spare "(expected true)"]
print ["show refused:    " error? try [show-window spare]]
print ["redraw refused:  " error? try [redraw spare]]
print ["images after:    " mold spare/images "(expected none)"]
print ["add-image refused:" error? try [add-image spare make image! 8x8 0x0]]
;; Closing a window removes its images; their handles stay, and say so.
print ["its image:       " spare-img "(expected 0#... removed)"]
print ["image's window:  " mold spare-img/window "(expected none)"]
release spare-img
print ["icon after:      " mold spare/icon "(expected none)"]
print ["icon refused:    " error? try [spare/icon: make image! 16x16]]
print ["set refused:     " error? try [spare/title: "x"]]
release spare

;;=============================================================================
print as-yellow "^/== Bad arguments"
;;=============================================================================

print ["zero size:       " error? try [open-window 0x10]]
print ["too big:         " error? try [open-window 20000x10]]
print ["not a window:    " error? try [show-window 42]]

;;=============================================================================
print as-yellow "^/== Polling"
;;=============================================================================

;; Always a block, empty when nothing happened, so it can be iterated
;; without a test.
print ["poll-events:     " mold type? poll-events]
print ["drained:         " length? poll-events "events"]

;; Opening reports nothing: the initial frame is the starting point.
fresh: open-window/hidden 100x100
print ["after opening:   " length? poll-events "events (expected 0)"]
close-window fresh
release fresh

;; Pugl reports a move and a resize as one event; the extension reports
;; only what changed - `resize`, `offset` or both.
window/size: 480x320
wait 0.1
print ["after resizing:  " mold collect [foreach evt poll-events [keep evt/type]]]
print "  (expected [resize] - an `offset` too where the system moves the frame)"

;;=============================================================================
print as-yellow "^/== Showing the window"
;;=============================================================================

show-window window
wait 0.1  ;; on X11 a window is mapped asynchronously
print ["visible?:        " window/visible? "(expected true)"]
hide-window window
wait 0.1
print ["hidden again:    " not window/visible?]
show-window window

;;=============================================================================
print as-yellow "^/== Images"
;;=============================================================================

;; `add-image` puts an image in the window and returns a handle of its own.
;; The window keeps a REFERENCE to the image, not a copy - so drawing into
;; it and calling `redraw` is all it takes to change what is on screen.
;; Images are drawn in the order they were added: the first at the bottom.
;; Offsets and sizes are in device pixels, from the window's top-left.
;;
;; Everything here is put on one group, the `stage`, which is kept in the
;; middle of the window: after anything is added or removed, and whenever
;; the window is resized. The offsets below are on the stage.
paint: function [
	"Fills the image with a red/green gradient, turned and tinted blue by the shift"
	img   [image!]
	shift [integer!] "0 to 255 - from not turned to turned upside down"
][
	;; A blue tint alone is hard to tell on a small image, so the gradient
	;; is turned around the middle too: red grows along one direction and
	;; green across it, both clipped to 0..255 in the corners.
	size:  img/size
	shift: shift % 256
	angle: shift * 180 / 255
	c: cosine angle
	s: sine angle
	repeat y size/y [
		repeat x size/x [
			dx: (x - (size/x / 2)) / size/x   ;; -0.5 .. 0.5 from the middle
			dy: (y - (size/y / 2)) / size/y
			u: dx * c - (dy * s) + 0.5
			v: dx * s + (dy * c) + 0.5
			img/(as-pair x y): to tuple! reduce [
				max 0 min 255 to integer! 255 * u
				max 0 min 255 to integer! 255 * v
				shift
			]
		]
	]
]
pic:   make image! 256x256  paint pic 0
small: make image! 64x64    paint small 255

;; A point of a node's own units in its parent's - its transform: moved to
;; its offset, turned clockwise and scaled around its pivot. What the
;; extension does, so that the test can check it.
from-local: function [node point [pair!]][
	scale: node/scale
	if number? scale [scale: as-pair scale scale]
	d: (point - node/pivot) * scale
	c: cosine node/rotation  s: sine node/rotation
	node/offset + node/pivot + as-pair (c * d/x - (s * d/y)) (s * d/x + (c * d/y))
]
;; ... and back: a point of its parent's in its own units; none when it is
;; scaled to nothing.
to-local: function [node point [pair!]][
	scale: node/scale
	if number? scale [scale: as-pair scale scale]
	if any [scale/x = 0  scale/y = 0][return none]
	d: point - node/offset - node/pivot
	c: cosine node/rotation  s: sine node/rotation
	node/pivot + as-pair (c * d/x + (s * d/y)) / scale/x  (c * d/y - (s * d/x)) / scale/y
]
;; The box a box of a node's own units takes in its parent's: the box
;; around its four corners, as turned.
box-through: function [node box [block!]][
	lo: hi: none
	foreach corner reduce [
		box/1  box/2  as-pair box/1/x box/2/y  as-pair box/2/x box/1/y
	][
		corner: from-local node corner
		lo: either lo [min lo corner][corner]
		hi: either hi [max hi corner][corner]
	]
	reduce [lo hi]
]

bounds-of: function [
	"The box a list's content takes, from the list's origin - [top-left bottom-right], or none"
	list [block!]
][
	;; Hidden ones count too, so hiding something does not move the rest.
	box: none
	foreach node list [
		part: either node/type = 'pugl-group [
			inner: bounds-of node/images
			;; A clipping group takes its own size, whatever is in it.
			clip: node/size
			if all [clip/x > 0  clip/y > 0][inner: reduce [0x0 clip]]
			if inner [box-through node inner]
		][
			box-through node reduce [0x0 node/size]
		]
		if part [
			box: either box [reduce [min box/1 part/1  max box/2 part/2]][part]
		]
	]
	box
]
center-content: function ["Moves the stage so that what is on it is in the middle of the window"][
	unless box: bounds-of stage/images [exit]
	origin: (window/size - (box/2 - box/1)) / 2 - box/1
	stage/offset: as-pair to integer! origin/x  to integer! origin/y
]
centered?: function ["Whether the stage's content is in the middle of the window, to a pixel"][
	unless box: bounds-of stage/images [return true]
	before: box/1 + stage/offset                 ;; the margin top-left
	after:  window/size - (box/2 + stage/offset) ;; and bottom-right
	all [1 >= abs before/x - after/x  1 >= abs before/y - after/y]
]

print ["images before:   " mold window/images "(expected [])"]
stage: add-group window 0x0
print ["the stage:       " all [1 = length? window/images  window/images/1 == stage] "(expected true)"]
print ["nothing to move: " centered? "(expected true - empty)"]
img1: add-image stage pic 20x20
print ["image handle:    " mold img1 "(expected 0#... 256x256 at 20x20)"]
print ["the handle type: " img1/type]
print ["the same series: " same? img1/image pic "(expected true)"]
print ["offset:          " img1/offset "(expected 20x20)"]
print ["size:            " img1/size "(expected 256x256 - its own)"]
print ["visible?:        " img1/visible? "(expected true)"]
print ["its window:      " img1/window == window "(expected true)"]
print ["on the stage:    " img1/parent == stage "(expected true)"]
center-content
print ["centered:        " centered? "(expected true)"  "stage at" stage/offset]
print ["track?:          " img1/track? "(expected false - off by default)"]
print ["hover?:          " img1/hover? "(expected false)"]
img1/track?: true
print ["track? set:      " img1/track? "(expected true)"]
img1/track?: false
print ["track? cleared:  " img1/track? "(expected false)"]
print ["track? a string: " error? try [img1/track?: "x"]]
print ["read-only hover?:" error? try [img1/hover?: true]]

;; The same image twice: scaled to twice its size, and at its own over pic.
img2: add-image/size stage small 300x40 128x128
img3: add-image stage small 200x200
center-content
print ["centered:        " centered? "(expected true)"  "stage at" stage/offset]
print ["scaled:          " img2/size "(expected 128x128)"]
print ["in order:        " all [
	3 = length? stage/images
	stage/images/1 == img1  stage/images/2 == img2  stage/images/3 == img3
] "(expected true)"]

print ["not an image:    " error? try [add-image window "x" 0x0]]
print ["an empty image:  " error? try [add-image window make image! 0x0 0x0]]
print ["a negative size: " error? try [add-image/size window small 0x0 -1x10]]
print ["not a window:    " error? try [add-image img1 small 0x0]]
print ["set a string:    " error? try [img1/image: "x"]]
print ["an unknown word: " error? try [img1/foo]]
print ["redraw an image: " redraw img1 "(expected true)"]
print ["redraw a window: " redraw window "(expected true)"]

;; A path going on PAST a handle field: the handle's answer is in the
;; path's scratch cell, and the image getter used to overwrite its own
;; input there - this crashed the interpreter.
print ["image/size:      " img1/image/size "(expected 256x256)"]
print ["image/width:     " img1/image/width "(expected 256)"]
print ["image/height:    " img1/image/height "(expected 256)"]

;; WATCH: a big gradient at the top-left, the small one twice its size to
;; its right, and once at its own size over the bottom-right corner of the
;; big one - on TOP of it, as it was added later.
wait 0.5

;; WATCH: the small one on top slides right and back.
repeat i 20 [img3/offset: img3/offset + 5x0  wait 0.02]
repeat i 20 [img3/offset: img3/offset - 5x0  wait 0.02]
print ["moved back:      " img3/offset "(expected 200x200)"]

;; WATCH: the scaled one blinks, then shrinks to its own size and back.
img2/visible?: false  wait 0.3
img2/visible?: true   wait 0.3
img2/size: 0x0
print ["own size again:  " img2/size "(expected 64x64)"]
wait 0.3
img2/size: 128x128

;; WATCH: drawing into `small` changes BOTH images showing it - one redraw
;; of the window uploads it for each: the gradient was upside down (and
;; blue), now it is the right way up, red to the right and green down.
paint small 0
redraw window
wait 0.3

;; Another image in place of the one shown, of another size.
img3/image: make image! [32x32 255.200.0]
print ["swapped:         " img3/size "(expected 32x32)"]
center-content
wait 0.3

;; Removed: the handle stays, and answers none for everything.
;; The pointer part of the mold is the handle's own: two differ, and one
;; keeps it once removed.
pointer-of: func [handle][pick split mold handle #" " 3]
before: pointer-of img3
print ["pointer part:    " before "(different from img1's:" (before <> pointer-of img1) ")"]
print ["remove-image:    " remove-image img3 "(expected true)"]
print ["the same after:  " before = pointer-of img3 "(expected true)"]
print ["images:          " length? stage/images "(expected 2)"]
center-content
print ["centered:        " centered? "(expected true)"]
print ["removed:         " img3 "(expected 0#... removed)"]
print ["offset after:    " mold img3/offset "(expected none)"]
print ["hover? after:    " mold img3/hover? "(expected none)"]
print ["removing twice:  " remove-image img3 "(expected true)"]
print ["set refused:     " error? try [img3/offset: 0x0]]
print ["redraw refused:  " error? try [redraw img3]]
release img3

;;=============================================================================
print as-yellow "^/== Groups"
;;=============================================================================

;; A group places what is in it relative to itself, and moves, hides and is
;; entered and left as a whole. Groups nest.
dot: make image! [24x24 255.255.255]
grp: add-group stage 300x200
print ["group handle:    " mold grp "(expected 0#... 0 at 300x200)"]
print ["the handle type: " grp/type]
print ["offset:          " grp/offset "(expected 300x200)"]
print ["visible?:        " grp/visible? "(expected true)"]
print ["track?:          " grp/track? "(expected false)"]
print ["hover?:          " grp/hover? "(expected false)"]
print ["size:            " grp/size "(expected 0x0 - not clipped)"]
print ["its window:      " grp/window == window "(expected true)"]
print ["parent:          " grp/parent == stage "(expected true)"]
print ["images:          " mold grp/images "(expected [])"]
print ["on top:          " (last stage/images) == grp "(expected true)"]

g1: add-image grp dot 0x0
g2: add-image grp dot 30x0
inner: add-group grp 0x30
g3: add-image inner dot 15x0
center-content
print ["centered:        " centered? "(expected true)"  "stage at" stage/offset]
print ["group molded:    " mold grp "(expected 0#... 3 at 300x200)"]
print ["in order:        " all [
	3 = length? grp/images
	grp/images/1 == g1  grp/images/2 == g2  grp/images/3 == inner
] "(expected true)"]
print ["image's parent:  " g1/parent == grp "(expected true)"]
print ["inner's parent:  " inner/parent == grp "(expected true)"]
print ["nested parent:   " g3/parent == inner "(expected true)"]
print ["nested window:   " g3/window == window "(expected true)"]
print ["relative offset: " g3/offset "(expected 15x0)"]
print ["top level parent:" mold stage/parent "(expected none)"]

print ["no image:        " error? try [grp/image]]
print ["images of image: " error? try [g1/images]]
print ["a bad clip:      " error? try [grp/size: -1x10]]
print ["bad /size:       " error? try [add-group/size grp 0x0 0x-1]]
print ["read-only images:" error? try [grp/images: []]]
print ["add to an image: " error? try [add-image g1 dot 0x0]]
print ["group in image:  " error? try [add-group g1 0x0]]
print ["redraw a group:  " redraw grp "(expected true)"]

;; WATCH: three white squares - two in a row, one below between them - go
;; down and back up as one; then the lower one blinks, then all three.
wait 0.3
repeat i 20 [grp/offset: grp/offset + 0x5  wait 0.02]
repeat i 20 [grp/offset: grp/offset - 0x5  wait 0.02]
print ["moved back:      " grp/offset "(expected 300x200)"]
inner/visible?: false  wait 0.3
inner/visible?: true   wait 0.3
grp/visible?: false    wait 0.3
grp/visible?: true

;; Removing a group removes all that is in it.
tmp: add-group grp 0x60
tmp-img: add-image tmp dot 0x0
center-content
print ["remove a group:  " remove-image tmp "(expected true)"]
print ["group removed:   " tmp "(expected 0#... removed)"]
print ["its image too:   " tmp-img "(expected 0#... removed)"]
print ["images after:    " mold tmp/images "(expected none)"]
print ["rotation after:  " mold tmp/rotation "(expected none)"]
print ["add to removed:  " error? try [add-image tmp dot 0x0]]
print ["left in group:   " length? grp/images "(expected 3)"]
center-content
print ["centered:        " centered? "(expected true)"  "stage at" stage/offset]
release tmp-img
release tmp

;;=============================================================================
print as-yellow "^/== Clipping"
;;=============================================================================

;; A group with a size shows what is in it only inside that box from its
;; origin - a viewport onto a big image, scrolled by moving the image. The
;; clipped away part is not there for the pointer either. Clips nest: what
;; is in a clipping group in a clipping group is inside both.
big: make image! 256x256  paint big 128
viewport: add-group/size stage 360x200 64x64
print ["viewport:        " mold viewport "(expected 0#... 0 at 360x200 clip 64x64)"]
;; The whole of it - the mold is built in parts, and once came out cut
;; after the pointer part.
print ["mold ends:       " did find/tail mold viewport "0 at 360x200 clip 64x64)" "(expected true)"]
print ["unclipped:       " none? find mold grp "clip" "(expected true)"]
print ["image mold ends: " did find/tail mold img1 "256x256 at 20x20)" "(expected true)"]
print ["size:            " viewport/size "(expected 64x64)"]
scroll: add-image viewport big 0x0
print ["image's size:    " scroll/size "(expected 256x256 - not clipped itself)"]
nested: add-group/size viewport 40x40 64x64
corner: add-image nested dot 12x12
center-content
print ["counts its clip: " (second bounds-of reduce [viewport]) - (first bounds-of reduce [viewport]) "(expected 64x64)"]
print ["centered:        " centered? "(expected true)"  "stage at" stage/offset]

;; WATCH: a 64x64 piece of a big gradient, right of the white squares, with
;; a white 12x12 square in its bottom-right corner - the rest of that
;; 24x24 one is outside the viewport.
wait 0.5
;; WATCH: the gradient scrolls up and left, to its bottom-right corner.
repeat i 24 [scroll/offset: scroll/offset - 8x8  wait 0.02]
print ["scrolled:        " scroll/offset "(expected -192x-192)"]
;; WATCH: the whole big image, over the other ones - then cut back.
viewport/size: 0x0
center-content
print ["not clipped:     " mold viewport "(expected 0#... 2 at 360x200)"]
wait 0.5
viewport/size: 64x64
center-content
print ["clipped again:   " viewport/size "(expected 64x64)"]
print ["centered:        " centered? "(expected true)"  "stage at" stage/offset]
;; One axis only: clipped horizontally, the whole height shows.
viewport/size: 64x0
wait 0.3
viewport/size: 64x64
scroll/offset: -96x-96   ;; the middle of the big image

;;=============================================================================
print as-yellow "^/== Transformations"
;;=============================================================================

;; Images and groups turn and scale around their pivot - their top-left,
;; 0x0, unless it is set - and fade; a group does it to all in it. `size`
;; stays what it was: the box before it is turned and scaled.
print ["rotation:        " img2/rotation "(expected 0.0)"]
print ["scale:           " img2/scale "(expected 1.0)"]
print ["pivot:           " img2/pivot "(expected 0x0)"]
print ["opacity:         " img2/opacity "(expected 100%)"]
print ["of a group:      " grp/rotation grp/scale grp/pivot grp/opacity "(expected 0.0 1.0 0x0 100%)"]
img2/rotation: 90
print ["an integer:      " mold img2/rotation "(expected 90.0)"]
img2/rotation: 0
img2/scale: 2
print ["scale 2:         " mold img2/scale "(expected 2.0)"]
print ["size unchanged:  " img2/size "(expected 128x128)"]
img2/scale: 2x1
print ["scale 2x1:       " img2/scale "(expected 2x1)"]
img2/scale: 1x1
print ["the same again:  " mold img2/scale "(expected 1.0 - a decimal! while both are the same)"]
img2/opacity: 50%
print ["opacity 50%:     " img2/opacity "(expected 50%)"]
img2/opacity: 0.25
print ["a decimal:       " img2/opacity "(expected 25%)"]
img2/opacity: 0
print ["integer 0:       " img2/opacity "(expected 0%)"]
img2/opacity: 1
print ["integer 1:       " img2/opacity "(expected 100%)"]
print ["integer 2:       " error? try [img2/opacity: 2] "(expected true - out of range)"]
img2/opacity: 100%
print ["too much:        " error? try [img2/opacity: 150%]]
print ["below zero:      " error? try [img2/opacity: -0.1]]
print ["a bad rotation:  " error? try [img2/rotation: "x"]]
print ["a bad scale:     " error? try [img2/scale: "x"]]
print ["a bad pivot:     " error? try [img2/pivot: 1.0]]

;; The test's own sums agree with the extension's: a point taken into a
;; node's units and back is where it was.
img2/pivot: 64x64  img2/rotation: 30  img2/scale: 1.5
there: from-local img2 to-local img2 310x50
print ["there and back:  " 1 > ((abs there/x - 310) + (abs there/y - 50)) "(expected true)"]
img2/pivot: 0x0  img2/rotation: 0  img2/scale: 1

;; WATCH: the scaled small one spins once around its middle, grows and
;; shrinks back, and turns upside down by being mirrored.
img2/pivot: img2/size / 2
repeat i 36 [img2/rotation: i * 10  wait 0.02]
repeat i 10 [img2/scale: 1 + (i / 20)  wait 0.02]
repeat i 10 [img2/scale: 1.5 - (i / 20)  wait 0.02]
img2/scale: 1x-1  wait 0.3
img2/scale: 1
print ["full turn:       " img2/rotation "(expected 360.0)"]

;; WATCH: the white squares fade out and back in - all three, as a group.
repeat i 10 [grp/opacity: 1 - (i / 10)  wait 0.02]
print ["faded out:       " grp/opacity "(expected 0%)"]
repeat i 10 [grp/opacity: i / 10  wait 0.02]

;; WATCH: the viewport turns a quarter around its middle - the big image
;; stays clipped to the turned square, and so does the corner square in
;; it, inside both clips.
viewport/pivot: viewport/size / 2
repeat i 18 [viewport/rotation: i * 5  wait 0.02]
wait 0.3

;; Left like this for the events: the scaled small one tilted, the
;; viewport turned by a third of a right angle.
img2/rotation: 20
viewport/rotation: 30
center-content
print ["centered:        " centered? "(expected true)"  "stage at" stage/offset]

;;=============================================================================
print as-yellow "^/== Blending"
;;=============================================================================

;; How an image is drawn over what is below. A group's `blend` is for all
;; in it which do not set their own; none - the default - is the group's,
;; and `normal` at the top.
print ["blend:           " mold img1/blend "(expected none - its group's)"]
print ["of a group:      " mold grp/blend "(expected none)"]
print ["a bad word:      " error? try [img1/blend: 'darken]]
print ["a bad type:      " error? try [img1/blend: 1]]

;; Three squares, red, green and blue, overlapping over the big gradient.
mix: add-group stage 60x170
sq-red:   add-image mix make image! [48x48 255.0.0] 0x0
sq-green: add-image mix make image! [48x48 0.255.0] 24x0
sq-blue:  add-image mix make image! [48x48 0.0.255] 12x20
center-content
mix/blend: 'add
print ["set:             " mold mix/blend "(expected add)"]
print ["its squares:     " mold sq-red/blend "(expected none - they go by the group)"]

;; WATCH: three overlapping squares on the gradient, ADDED - yellow, cyan
;; and magenta where two overlap and white where all three do; then
;; MULTIPLIED - the gradient through coloured filters, black where they
;; overlap; then SCREENED - lighter, like add but softer; then NORMAL -
;; plain squares, the last one on top.
wait 0.5
mix/blend: 'multiply  wait 0.5
mix/blend: 'screen    wait 0.5
mix/blend: 'normal    wait 0.5

;; Its own wins over the group's: the blue one stays normal while the
;; group adds.
mix/blend: 'add
sq-blue/blend: 'normal
print ["its own:         " mold sq-blue/blend "(expected normal)"]
wait 0.5
sq-blue/blend: none
print ["back to group's: " mold sq-blue/blend "(expected none)"]

;; WATCH: added squares fade - with premultiplied colour, a faded square
;; adds less, rather than adding all its colour at no alpha.
repeat i 10 [mix/opacity: 1 - (i / 10)  wait 0.03]
repeat i 10 [mix/opacity: i / 10  wait 0.03]
;; Left adding for the events.

;;=============================================================================
print as-yellow "^/== An icon"
;;=============================================================================

;; The platform gets a COPY of the pixels when the icon is set, so drawing
;; into the image afterwards changes nothing until it is set again. On
;; macOS it is the application's Dock icon, which the last window set wins.
;; Any size: Windows scales it down to its two icon sizes itself.
ico: make image! 64x64
paint ico 200

print ["icon before:     " mold window/icon "(expected none)"]
window/icon: ico
print ["the same series: " same? window/icon ico "(expected true)"]
shown: window/icon
print ["icon is:         " type? shown "size:" shown/size "(expected 64x64)"]
shown: none
print ["a string refused:" error? try [window/icon: "x"]]
print ["an empty image:  " error? try [window/icon: make image! 0x0]]

;; WATCH: the title bar and the taskbar (on macOS the Dock) show a red
;; and green gradient with a blue tint, turned by most of a half turn. It
;; goes away and comes back.
wait 0.5
window/icon: none
print ["removed:         " mold window/icon "(expected none)"]
wait 0.5
;; Drawn into AFTER being set - the copy keeps the old colours until the
;; icon is set again, which is what the second line does.
window/icon: ico
paint ico 0
print ["redrawn image:   " same? window/icon ico "(still the same series)"]
wait 0.5
window/icon: ico   ;; WATCH: now the right way up, without the blue tint

;; A big one, scaled down - 256x256, as an application icon usually is.
window/icon: pic
print ["a bigger icon:   " window/icon/size "(expected 256x256)"]

;;=============================================================================
print as-yellow "^/== Events"
;;=============================================================================

print {
Move the mouse over the window, click (left, right, middle), use the wheel,
type, resize and move it, switch to another window and back.
A left click on an image repaints it - the topmost one under the pointer -
with its gradient turned another way and a new tint, and reports where on
it the click was.
The two big images, the group of white squares, its lower square's group
and the top-left square report `enter` and `leave` themselves (as the event
source); the window reports its own when the pointer crosses its edge.
Moving between the squares of the group does not leave the group.
The viewport and the big image in it are tracked too: over its clipped
away part there is nothing to enter. The scaled small image and the
viewport are turned - they are entered and left by their turned shape.
Resize the window by dragging its edge - the images are not stretched, and
are moved back to the middle as soon as the resize is reported (on Windows
when the drag ends: its modal resize loop does not let the script run).
ESCAPE or the close button ends the test.
}

;; `move` events are collapsed by the extension, but there are still plenty
;; of them - only report a move once it has travelled a bit.
last-move: 0x0
pressed: none   ;; the button between its `down` and its `up`
over:    []     ;; tracked images and groups between `enter` and `leave`

;; On demand: only these report `enter` and `leave`.
img1/track?:  true
img2/track?:  true
grp/track?:   true
inner/track?: true
g1/track?:    true
viewport/track?: true
scroll/track?:   true

;; Handles compare by type only with `=`, so blocks of them are searched
;; with `==`.
has?: function [list [block!] value][
	foreach v list [if v == value [return true]]
	false
]
;; The image or group and every group it is in, innermost first.
chain-of: function [node][
	chain: copy []
	while [node][append chain node  node: node/parent]
	chain
]
;; A point of the window in a node's own units - through every group it is
;; in, outermost first.
local-of: function [node point [pair!]][
	foreach n reverse chain-of node [
		unless point: to-local n point [return none]
	]
	point
]

;; The topmost image under a point, or none - the last one added is on top,
;; and each takes the point back through its transform, so a turned image
;; is hit by its real shape.
image-at: function [point [pair!]][top-at window/images point]
top-at: function [list [block!] point [pair!]][
	hit: none
	foreach node list [
		unless node/visible? [continue]
		unless inside: to-local node point [continue]
		either node/type = 'pugl-group [
			clip: node/size
			;; What a group clips away is not there to be hit.
			unless any [
				all [clip/x > 0  any [inside/x < 0  inside/x >= clip/x]]
				all [clip/y > 0  any [inside/y < 0  inside/y >= clip/y]]
			][
				if found: top-at node/images inside [hit: found]
			]
		][
			if all [
				inside/x >= 0  inside/y >= 0
				inside/x < node/size/x  inside/y < node/size/y
			][hit: node]
		]
	]
	hit
]

report: func [event /local type position d hit src][
	type:     event/type
	position: event/offset

	if type = 'move [
		d: position - last-move
		if 10 > ((abs d/x) + (abs d/y)) [exit]
		last-move: position
	]

	;; Every event names the window it came from - or, for `enter` and
	;; `leave` of a tracked image or group, that one.
	src: event/source
	either find [pugl-image pugl-group] src/type [
		unless find [enter leave] type [print as-red ["!!" type "from" src/type]]
		unless src/track? [print as-red "!! not tracked"]
		unless src/window == window [print as-red "!! of another window"]
		either type = 'enter [
			;; Entered once, while it has the top image under the pointer,
			;; and after the tracked groups around it.
			if has? over src [print as-red "!! entered twice"]
			unless has? chain-of image-at position src [
				print as-red ["!! entered what is not on top at" position]
			]
			foreach up next chain-of src [
				if all [up/track?  not has? over up] [
					print as-red ["!! entered before its group" up]
				]
			]
			append over src
		][
			;; Left once for each enter, before the groups around it.
			unless has? over src [print as-red "!! left what was not entered"]
			foreach node over [
				if all [not node == src  has? chain-of node src] [
					print as-red ["!! left before" node "in it"]
				]
			]
			remove-each node over [node == src]
		]
		print [
			as-green pad form type 12
			pad mold position 12 select [pugl-image "image:" pugl-group "group:"] src/type src
		]
		exit
	][
		unless event/source == window [print as-red "!! event from another window"]
	]
	;; The window's own leave comes after those of what is in it.
	if all [type = 'leave  not empty? over] [print as-red ["!! left the window while in" length? over]]

	;; Each press must be answered by exactly one release of the same kind.
	switch type [
		down alt-down aux-down [
			if pressed [print as-red ["!!" type "while" pressed "is still open"]]
			pressed: type
		]
		up [unless pressed = 'down [print as-red "!! up without down"]  pressed: none]
		alt-up [unless pressed = 'alt-down [print as-red "!! alt-up without alt-down"]  pressed: none]
		aux-up [unless pressed = 'aux-down [print as-red "!! aux-up without aux-down"]  pressed: none]
	]

	;; With no button held, a move comes from inside the window.
	if all [type = 'move  not pressed] [
		unless all [
			position/x >= 0  position/y >= 0
			position/x < window/size/x  position/y < window/size/y
		][
			print as-red ["!! move outside the window:" position]
		]
	]

	;; A resize carries the new size, which the window reports back - and
	;; the content goes back to the middle.
	if type = 'resize [
		if position <> window/size [
			print as-red ["!! resize to" position "but size is" window/size]
		]
		center-content
		unless centered? [print as-red ["!! not centered, stage at" stage/offset]]
	]

	;; Escape ends it; `do-events` sees the window closed and returns.
	if all [type = 'key  event/key = #"^["] [
		print "Escape - closing the window"
		close-window window
	]

	;; Drawing into the very image the window shows, then asking for it to
	;; be shown again. Nothing is copied. A scaled image is drawn at a size
	;; other than its own, so where on its pixels is worked out from both.
	if type = 'down [
		either hit: image-at position [
			print ["  on" hit "at pixel"
				(local-of hit position) * hit/image/size / hit/size]
			paint hit/image random 256
			redraw hit
		][
			print "  on no image"
		]
	]

	if type = 'close [print ["Closing window:" event/source]]

	print [
		as-green pad form type 12
		case [
			type = 'scroll-line   [ajoin ["lines: " event/code]]
			find [key key-up] type [ajoin [mold event/key " " mold event/flags]]
			find [close active inactive] type [""]
			true [ajoin [pad mold position 12 mold event/flags]]
		]
	]
]

;; Pumps the window, hands every event! to `report`, and returns once the window
;; has been closed - by `close` or by the handler.
do-events window :report

print ["^/window closed - open?:" window/open? "(expected false)"]
print ["molded:" window "(expected closed)"]
print ["images after close:" mold window/images "(expected none)"]
print ["img1 after close:" img1 "(expected 0#... removed)"]
print ["the image survives:" type? pic pic/size]
release window
print ["released:" window]

print "done"
