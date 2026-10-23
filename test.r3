Rebol [
	Title:   "Rebol/Pugl extension test"
	Needs:   3.22.10
	Purpose: {
		Opens a view and prints the events it produces. Meant to be run
		by a human - close the view (or press Escape) to end it.

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
print as-yellow "^/== Opening a view"
;;=============================================================================

;; /hidden, so the accessors are read before anything is on screen.
view: open-view/title/at/hidden 480x320 "Rebol Pugl extension" 200x120

print ["view:     " view]
print ["id:       " view/id]
print ["open?:    " view/open? "(expected true)"]
print ["visible?: " view/visible? "(expected false)"]
print ["title:    " mold view/title {(expected "Rebol Pugl extension")}]
print ["size:     " view/size "(expected 480x320)"]
print ["offset:   " view/offset]
print ["scale:    " view/scale "(sizes and offsets are in device pixels)"]

;; every accessor which can be read can also be written, except
;; scale, id, visible? and open?
view/title: "Rebol Pugl extension - move the mouse"
print ["title:    " mold view/title]
view/size: 500x340
print ["size:     " view/size "(expected 500x340)"]
print ["a bad size is refused:   " error? try [view/size: 0x10]]
print ["a bad type is refused:   " error? try [view/title: 42]]
print ["read-only scale:         " error? try [view/scale: 2.0]]
print ["an unknown word:         " error? try [view/foo]]
print ["the handle type:         " view/type]

;;=============================================================================
print as-yellow "^/== Closing a view"
;;=============================================================================

;; A closed view keeps its handle: it reports `open?` false and none for
;; everything else, rather than pointing at freed memory.
spare: open-view/hidden 200x100
print ["spare:           " spare]
print ["open?:           " spare/open? "(expected true)"]
print ["close-view:      " close-view spare "(expected true)"]
print ["open? after:     " spare/open? "(expected false)"]
print ["size after:      " mold spare/size "(expected none)"]
print ["title after:     " mold spare/title "(expected none)"]
print ["id after:        " spare/id "(expected 0)"]
print ["molded:          " spare "(expected closed)"]
print ["closing twice:   " close-view spare "(expected true)"]
print ["show refused:    " error? try [show-view spare]]
print ["redraw refused:  " error? try [redraw spare]]
print ["image after:     " mold spare/image "(expected none)"]
print ["icon after:      " mold spare/icon "(expected none)"]
print ["icon refused:    " error? try [spare/icon: make image! 16x16]]
print ["set refused:     " error? try [spare/title: "x"]]
release spare

;;=============================================================================
print as-yellow "^/== Bad arguments"
;;=============================================================================

print ["zero size:       " error? try [open-view 0x10]]
print ["too big:         " error? try [open-view 20000x10]]
print ["not a view:      " error? try [show-view 42]]

;;=============================================================================
print as-yellow "^/== Polling"
;;=============================================================================

;; Always a block, empty when nothing happened, so it can be iterated
;; without a test.
print ["poll-events:     " mold type? poll-events]
print ["drained:         " length? poll-events "events"]

;; Opening reports nothing: the initial frame is the starting point.
fresh: open-view/hidden 100x100
print ["after opening:   " length? poll-events "events (expected 0)"]
close-view fresh
release fresh

;; Pugl reports a move and a resize as one event; the extension reports
;; only what changed - `resize`, `offset` or both.
view/size: 480x320
wait 0.1
print ["after resizing:  " mold collect [foreach evt poll-events [keep evt/type]]]
print "  (expected [resize] - an `offset` too where the system moves the frame)"

;;=============================================================================
print as-yellow "^/== Showing the view"
;;=============================================================================

show-view view
wait 0.1  ;; on X11 a view is mapped asynchronously
print ["visible?:        " view/visible? "(expected true)"]
hide-view view
wait 0.1
print ["hidden again:    " not view/visible?]
show-view view

;;=============================================================================
print as-yellow "^/== An image"
;;=============================================================================

;; The view keeps a REFERENCE to the image, not a copy - so drawing into
;; `pic` and calling `redraw` is all it takes to change what is on screen.
;; It is drawn at its own size, in device pixels, centered in the view.
pic: make image! 256x256

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
paint pic 0

print ["image before:    " mold view/image "(expected none)"]
view/image: pic
print ["the same series: " same? view/image pic "(expected true)"]
;; NEVER mold an image! into the console - only its type and size.
shown: view/image
print ["image is:        " type? shown "size:" shown/size "(expected 256x256)"]
shown: none
print ["a string refused:" error? try [view/image: "x"]]
print ["redraw:          " redraw view "(expected true)"]

;; Where it lands: half the spare room on each side, in whole pixels.
;; Pixels cannot be read back from the screen, so this prints where the
;; image's corner should be and the scene below shows it.
image-at: func [/local d][
	d: view/size - pic/size
	;; truncated, as C's integer division does it - also when negative
	as-pair to integer! d/x / 2  to integer! d/y / 2
]
print ["view size:       " view/size]
print ["image corner at: " image-at "(centered)"]

;; WATCH: a gradient in the middle of the view, black at its top-left, red
;; to the right, green downwards, with an equal black border left and right,
;; and top and bottom. It goes away and comes back.
wait 0.5
view/image: none
print ["removed:         " mold view/image "(expected none)"]
wait 0.5
view/image: pic

;; WATCH: the image stays centered as the view changes size - smaller than
;; the image too, where it is cropped equally on both sides.
foreach size [400x300 300x400 200x150 480x320] [
	view/size: size
	wait 0.4
	print ["view size:       " pad view/size 9 "image corner at:" image-at]
]

;;=============================================================================
print as-yellow "^/== An icon"
;;=============================================================================

;; The platform gets a COPY of the pixels when the icon is set, so drawing
;; into the image afterwards changes nothing until it is set again. On
;; macOS it is the application's Dock icon, which the last view set wins.
;; Any size: Windows scales it down to its two icon sizes itself.
ico: make image! 64x64
paint ico 200

print ["icon before:     " mold view/icon "(expected none)"]
view/icon: ico
print ["the same series: " same? view/icon ico "(expected true)"]
shown: view/icon
print ["icon is:         " type? shown "size:" shown/size "(expected 64x64)"]
shown: none
print ["a string refused:" error? try [view/icon: "x"]]
print ["an empty image:  " error? try [view/icon: make image! 0x0]]

;; WATCH: the title bar and the taskbar (on macOS the Dock) show a red
;; and green gradient with a blue tint. It goes away and comes back.
wait 0.5
view/icon: none
print ["removed:         " mold view/icon "(expected none)"]
wait 0.5
;; Drawn into AFTER being set - the copy keeps the old colours until the
;; icon is set again, which is what the second line does.
view/icon: ico
paint ico 0
print ["redrawn image:   " same? view/icon ico "(still the same series)"]
wait 0.5
view/icon: ico   ;; WATCH: now without the blue tint

;; A big one, scaled down - 256x256, as an application icon usually is.
view/icon: pic
print ["a bigger icon:   " view/icon/size "(expected 256x256)"]

;; A path going on PAST a handle field: the handle's answer is in the
;; path's scratch cell, and the image getter used to overwrite its own
;; input there - `view/image/size` crashed the interpreter.
print ["image/size:      " view/image/size "(expected 256x256)"]
print ["image/width:     " view/image/width "(expected 256)"]
print ["image/height:    " view/image/height "(expected 256)"]

;;=============================================================================
print as-yellow "^/== Events"
;;=============================================================================

print {
Move the mouse over the view, click (left, right, middle), use the wheel,
type, resize and move it, switch to another window and back.
A left click repaints the image in a new colour.
Resize the view by dragging its edge - the image stays centered WHILE
dragging, shrinking as well as growing, with no stale copy left behind.
A click on it is reported with its position on the image too.
ESCAPE or the close button ends the test.
}

;; `move` events are collapsed by the extension, but there are still plenty
;; of them - only report a move once it has travelled a bit.
last-move: 0x0
pressed: none   ;; the button between its `down` and its `up`

report: func [event /local type position d on-image][
	type:     event/type
	position: event/offset

	if type = 'move [
		d: position - last-move
		if 10 > ((abs d/x) + (abs d/y)) [exit]
		last-move: position
	]

	;; Every event names the view it came from.
	unless event/source == view [print as-red "!! event from another view"]

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

	;; With no button held, a move comes from inside the view.
	if all [type = 'move  not pressed] [
		unless all [
			position/x >= 0  position/y >= 0
			position/x < view/size/x  position/y < view/size/y
		][
			print as-red ["!! move outside the view:" position]
		]
	]

	;; A resize carries the new size, which the view reports back - and
	;; moves the centered image.
	if type = 'resize [
		if position <> view/size [
			print as-red ["!! resize to" position "but size is" view/size]
		]
		print ["  image corner now at" image-at]
	]

	;; Escape ends it; `do-events` sees the view closed and returns.
	if all [type = 'key  event/key = #"^["] [
		print "Escape - closing the view"
		close-view view
	]

	;; Drawing into the very image the view was given, then asking for it
	;; to be shown. Nothing is copied.
	if type = 'down [
		;; The image is centered, so its own coordinates are the event's
		;; minus where its corner is.
		on-image: position - image-at
		either all [
			on-image/x >= 0  on-image/y >= 0
			on-image/x < pic/size/x  on-image/y < pic/size/y
		][
			print ["  on the image at" on-image]
		][
			print ["  outside the image"]
		]
		paint pic random 256
		redraw view
	]

	if type = 'close [print ["Closing view:" event/source]]

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

;; Pumps the view, hands every event! to `report`, and returns once the view
;; has been closed - by `close` or by the handler.
do-events view :report

print ["^/view closed - open?:" view/open? "(expected false)"]
print ["molded:" view "(expected closed)"]
print ["image after close:" mold view/image "(expected none)"]
print ["the image survives:" type? pic pic/size]
release view
print ["released:" view]

print "done"
