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
print ["its image:       " spare-img "(expected removed)"]
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
paint: function ["Fills the image with a gradient" img [image!] shift [integer!]][
	size: img/size
	repeat y size/y [
		repeat x size/x [
			img/(as-pair x y): to tuple! reduce [
				to integer! 255 * x / size/x
				to integer! 255 * y / size/y
				shift % 256
			]
		]
	]
]
pic:   make image! 256x256  paint pic 0
small: make image! 64x64    paint small 255

print ["images before:   " mold window/images "(expected [])"]
img1: add-image window pic 20x20
print ["image handle:    " img1 "(expected 256x256 at 20x20)"]
print ["the handle type: " img1/type]
print ["the same series: " same? img1/image pic "(expected true)"]
print ["offset:          " img1/offset "(expected 20x20)"]
print ["size:            " img1/size "(expected 256x256 - its own)"]
print ["visible?:        " img1/visible? "(expected true)"]
print ["its window:      " img1/window == window "(expected true)"]
print ["track?:          " img1/track? "(expected false - off by default)"]
print ["hover?:          " img1/hover? "(expected false)"]
img1/track?: true
print ["track? set:      " img1/track? "(expected true)"]
img1/track?: false
print ["track? cleared:  " img1/track? "(expected false)"]
print ["track? a string: " error? try [img1/track?: "x"]]
print ["read-only hover?:" error? try [img1/hover?: true]]

;; The same image twice: scaled to twice its size, and at its own over pic.
img2: add-image/size window small 300x40 128x128
img3: add-image window small 200x200
print ["scaled:          " img2/size "(expected 128x128)"]
print ["in order:        " all [
	3 = length? window/images
	window/images/1 == img1  window/images/2 == img2  window/images/3 == img3
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
;; of the window uploads it for each.
paint small 0
redraw window
wait 0.3

;; Another image in place of the one shown, of another size.
img3/image: make image! [32x32 255.200.0]
print ["swapped:         " img3/size "(expected 32x32)"]
wait 0.3

;; Removed: the handle stays, and answers none for everything.
print ["remove-image:    " remove-image img3 "(expected true)"]
print ["images:          " length? window/images "(expected 2)"]
print ["removed:         " img3 "(expected removed)"]
print ["offset after:    " mold img3/offset "(expected none)"]
print ["hover? after:    " mold img3/hover? "(expected none)"]
print ["removing twice:  " remove-image img3 "(expected true)"]
print ["set refused:     " error? try [img3/offset: 0x0]]
print ["redraw refused:  " error? try [redraw img3]]
release img3

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
;; and green gradient with a blue tint. It goes away and comes back.
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
window/icon: ico   ;; WATCH: now without the blue tint

;; A big one, scaled down - 256x256, as an application icon usually is.
window/icon: pic
print ["a bigger icon:   " window/icon/size "(expected 256x256)"]

;;=============================================================================
print as-yellow "^/== Events"
;;=============================================================================

print {
Move the mouse over the window, click (left, right, middle), use the wheel,
type, resize and move it, switch to another window and back.
A left click on an image repaints it in a new colour - the topmost one
under the pointer - and reports where on it the click was.
Both images report `enter` and `leave` themselves (as the event source);
the window reports its own when the pointer crosses its edge.
Resize the window by dragging its edge - the images stay where they are,
unstretched, while dragging.
ESCAPE or the close button ends the test.
}

;; `move` events are collapsed by the extension, but there are still plenty
;; of them - only report a move once it has travelled a bit.
last-move: 0x0
pressed: none   ;; the button between its `down` and its `up`
over:    none   ;; the tracked image between its `enter` and its `leave`

;; Per image, on demand: only these two report `enter` and `leave`.
img1/track?: true
img2/track?: true

;; The topmost image under a point, or none - the last one added is on top.
image-at: function [point [pair!]][
	foreach img reverse copy window/images [
		if all [
			img/visible?
			point/x >= img/offset/x  point/y >= img/offset/y
			point/x <  (img/offset/x + img/size/x)
			point/y <  (img/offset/y + img/size/y)
		][return img]
	]
	none
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
	;; `leave` of a tracked image, that image.
	src: event/source
	either src/type = 'pugl-image [
		unless find [enter leave] type [print as-red ["!!" type "from an image"]]
		unless src/track? [print as-red "!! an image not tracked"]
		unless src/window == window [print as-red "!! image of another window"]
		;; Each enter is answered by one leave of the same image, before
		;; another image is entered.
		either type = 'enter [
			if over [print as-red ["!! enter while over" over]]
			unless src == image-at position [
				print as-red ["!! entered an image not on top at" position]
			]
			over: src
		][
			unless over == src [print as-red "!! leave of an image not entered"]
			over: none
		]
		print [
			as-green pad form type 12
			pad mold position 12 "image:" src
		]
		exit
	][
		unless event/source == window [print as-red "!! event from another window"]
	]
	;; The window's own leave comes after its image's.
	if all [type = 'leave  over] [print as-red ["!! left the window while over" over]]

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

	;; A resize carries the new size, which the window reports back.
	if all [type = 'resize  position <> window/size] [
		print as-red ["!! resize to" position "but size is" window/size]
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
				(position - hit/offset) * hit/image/size / hit/size]
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
print ["img1 after close:" img1 "(expected removed)"]
print ["the image survives:" type? pic pic/size]
release window
print ["released:" window]

print "done"
