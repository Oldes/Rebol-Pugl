Rebol [
	Title:   "Rebol/Pugl - basic widgets test"
	Needs:   3.22.10
	Purpose: {
		Basic widgets built of what the extension has: a group, a
		nine-scaled frame from an atlas and a text - buttons, sliders,
		text fields, a scroller, check boxes and radio buttons.

		A button is a tracked group - so it is entered, left and pressed
		as a whole, and a press keeps it until the release - holding its
		frame, a focus ring and its label. The frames - a button's, the
		default one's and the ring - are one atlas; hover, pressed and
		disabled are tints, as in font-test.r3.

		The text is Ubuntu at 12 units: its 12 px atlas, or on a screen of
		2 device pixels per unit or more, its 24 px one drawn at half.

		Usage:
			r3 widgets-test.r3
	}
]

try [system/modules/pugl: none]
if modules-dir: get-env 'REBOL_MODULES_DIR [
	system/options/modules: dirize to-rebol-file modules-dir
]
pugl: import 'pugl

;;=============================================================================
;; The atlas: 24x24 cells side by side. Five frames - the button's, the
;; default button's, the focus ring, a slider's filled part and a field's -
;; each nine-scaled by [3x3 18x18]: square, a dark face in a light edge, as
;; the button in font-test.r3. Hover, pressed and disabled are tints of it.
;; Then three marks of 14x14, drawn smooth, shown at their size: a check
;; mark, a radio button's circle and its dot.
;;=============================================================================

cell: 24

;; One frame at `at`: an edge `width` pixels wide, filled inside - or not.
paint-frame: func [
	img [image!] at [pair!] fill [tuple! none!] edge [tuple!] width [integer!]
	/local color
][
	repeat y cell [
		repeat x cell [
			color: either any [
				x <= width  y <= width  x > (cell - width)  y > (cell - width)
			][edge][fill]
			if color [img/(at + as-pair x y): color]
		]
	]
]

atlas: make image! reduce [as-pair cell * 8 cell 0.0.0.0]    ;; transparent
paint-frame atlas 0x0  70.70.90.255 160.160.200.255 2    ;; a button
paint-frame atlas 24x0 70.70.90.255 120.170.255.255 2    ;; the default one
paint-frame atlas 48x0 none         120.180.255.255 1    ;; the focus ring
paint-frame atlas 72x0 80.120.210.255 120.170.255.255 2  ;; a slider's fill
paint-frame atlas 96x0 22.22.28.255   110.110.140.255 1  ;; a field

;; The marks: each pixel's coverage by a shape, as its alpha.
box-size: 14
clamp01: func [v][max 0.0 min 1.0 v]
rgba: func [c [tuple!] a [number!]][
	to tuple! reduce [c/1 c/2 c/3  to integer! round 255 * clamp01 a]
]
mix: func [a [tuple!] b [tuple!] t [number!]][
	to tuple! reduce [
		to integer! round a/1 + (t * (b/1 - a/1))
		to integer! round a/2 + (t * (b/2 - a/2))
		to integer! round a/3 + (t * (b/3 - a/3))
	]
]
;; How far a point is from a line segment.
seg-dist: func [px py ax ay bx by /local dx dy t][
	dx: bx - ax  dy: by - ay
	t: clamp01 ((px - ax) * dx + ((py - ay) * dy)) / ((dx * dx) + (dy * dy))
	square-root ((px - ax - (t * dx)) ** 2) + ((py - ay - (t * dy)) ** 2)
]
;; `shade` gives a pixel's centre [color alpha], or none.
paint-mark: func [img [image!] at [pair!] shade [any-function!] /local c][
	repeat y box-size [
		repeat x box-size [
			if c: shade x - 0.5 y - 0.5 [
				if c/2 > 0 [img/(at + as-pair x y): rgba c/1 c/2]
			]
		]
	]
]
;; a check mark: two strokes
paint-mark atlas as-pair 5 * cell 0 func [x y /local d][
	d: min seg-dist x y 3.5 7.5 6 10.5  seg-dist x y 6 10.5 11 4
	reduce [235.240.255 1.6 - d]
]
;; a radio button's circle: a dark disc in a light rim
paint-mark atlas as-pair 6 * cell 0 func [x y /local d][
	d: square-root ((x - 7) ** 2) + ((y - 7) ** 2)
	reduce [mix 22.22.28 110.110.140 clamp01 1 - abs (d - 6)  6.75 - d]
]
;; its dot
paint-mark atlas as-pair 7 * cell 0 func [x y /local d][
	d: square-root ((x - 7) ** 2) + ((y - 7) ** 2)
	reduce [120.180.255 3.5 - d]
]
mark-part: func [n][reduce [as-pair n * cell 0  as-pair box-size box-size]]

part-of: func [n [integer!]][reduce [as-pair n * cell 0  as-pair cell cell]]
nine: [3x3 18x18]

;;=============================================================================
print as-yellow "^/== The window and the font"
;;=============================================================================

window: open-window/title 680x450 "Widgets"
print ["window scale:    " window/scale]

;; The size for widgets: 12 units. Sharp on a dense screen too: the 24 px
;; atlas, drawn at half.
hi-dpi?: window/scale >= 1.5
font: make-font do either hi-dpi? [%font/ubuntu-24.reb][%font/ubuntu-12.reb]
print ["font:            " either hi-dpi? ["Ubuntu 24, at half"]["Ubuntu 12"]]

;; The size a text takes in units - halved with the big atlas, as it is drawn.
tsize: func [text [string!] /local s][
	s: text-size font text
	either hi-dpi? [s / 2][s]
]
print ["text size of OK: " tsize "OK" "(expected 17x15, or 17x14.5 at half)"]

;; Text at the size of the font chosen.
add-label: func [parent text offset /local t][
	t: add-text parent font text offset
	if hi-dpi? [t/scale: 0.5  t/filter: 'linear]
	t
]

;; A plain dark background, stretched over the window.
bg: add-image/size window make image! [1x1 30.30.38] 0x0 window/size

;;=============================================================================
;; What all widgets share: a tracked group, a focus ring, a state.
;;=============================================================================

widgets: copy []   ;; in Tab order
focused: none
clicks:  0

;; The fields every widget has; a kind adds its own.
widget-base: [
	kind: group: ring: none
	enabled?: true
	hover?:   false
	pressed?: false
]

;; The group, and the ring in it - below what follows, sticking out around
;; a box of `size`.
widget-group: func [w parent offset size][
	w/group: add-group parent offset
	w/ring: add-image/size/part w/group atlas -2x-2 size + 4x4 part-of 2
	w/ring/nine-scale: nine
	w/ring/visible?: false
	w/group/track?: true
	w/group/cursor: 'hand
	append widgets w
]

refresh: func [w][
	switch w/kind [
		button [refresh-button w]
		slider [refresh-slider w]
		field  [refresh-field w]
		scroller [refresh-scroller w]
		check radio [refresh-choice w]
	]
]

;; A disabled widget is not tracked: the pointer goes through it to the
;; window, so it gets no events, and shows no hand.
set-enabled: func [w on [logic!]][
	w/enabled?: on
	w/group/track?: on
	w/group/cursor: either on [either w/kind = 'field ['caret]['hand]][none]
	unless on [
		w/hover?: w/pressed?: false
		if same? focused w [focus none]
	]
	refresh w
]

;; The ring shows where the focus is - but around a scroller, a big area
;; clicked into to scroll it, only when it was reached by Tab.
focus: func [w /keyboard "Reached by Tab or Shift-Tab" /local old][
	old: focused
	if old [old/ring/visible?: false]
	focused: w
	if w [w/ring/visible?: did any [keyboard  w/kind <> 'scroller]]
	;; a field shows its caret only while it has the focus
	if all [old  old/kind = 'field] [update-field old]
	if all [w  w/kind = 'field] [update-field w]
]

;; Tab and Shift-Tab: the next or the previous enabled one.
focus-next: function [step [integer!]][
	live: copy []
	foreach w widgets [if w/enabled? [append/only live w]]
	if empty? live [exit]
	n: 0
	repeat k length? live [if same? live/:k focused [n: k]]
	n: n + step
	if n > length? live [n: 1]
	if n < 1 [n: length? live]
	focus/keyboard live/:n
]

find-widget: func [source][
	foreach w widgets [if w/group == source [return w]]
	none
]

;; Where an event's offset - in the window - is in a widget, from its
;; group's corner. (The widgets here are at the window's top level.)
local-of: func [w event][event/offset - w/group/offset]

;;=============================================================================
;; Buttons
;;=============================================================================

padding: 10x3   ;; around the label of a button sized by it

make-button: function [
	"A button in a window or a group; a zero axis of size is the label's, padded"
	parent [handle!] text [string!] offset [pair!] size [pair!]
	/toggle  "Stays pressed until clicked again"
	/default "Edged in blue, and clicked by Enter when no button has the focus"
][
	ts: tsize text
	if zero? size/x [size/x: to integer! round/ceiling ts/x + (2 * padding/x)]
	if zero? size/y [size/y: to integer! round/ceiling ts/y + (2 * padding/y)]
	b: make object! append copy widget-base [
		face: label: text: none
		toggle?:  false
		on?:      false
		default?: false
	]
	b/kind:     'button
	b/text:     copy text
	b/toggle?:  did toggle
	b/default?: did default
	widget-group b parent offset size
	b/face: add-image/size/part b/group atlas 0x0 size part-of either default [1][0]
	b/face/nine-scale: nine
	b/label: add-label b/group b/text 0x0
	center-label b
	refresh b
	b
]

center-label: func [b][
	b/label/offset: b/face/size - (tsize b/text) / 2
]

;; Its state, as a tint of its frame - as in font-test.r3 - and of its label.
refresh-button: func [b][
	b/face/tint: case [
		not b/enabled?                         [110.110.120]
		any [b/on?  all [b/pressed? b/hover?]] [140.160.220]
		b/hover?                               [200.220.255]
		true                                   [none]
	]
	b/label/tint: either b/enabled? [none][130.130.140]   ;; white, or grey
]

set-text: func [b text][
	b/text: copy text
	b/label/text: b/text
	center-label b
]

click: func [b][
	if b/toggle? [
		b/on?: not b/on?
		set-text b either b/on? ["Toggle: on"]["Toggle: off"]
		;; the toggle turns the disabled ones on and off
		set-enabled disabled-btn b/on?
		set-text disabled-btn either b/on? ["Enabled"]["Disabled"]
		set-enabled disabled-sld b/on?
		set-enabled disabled-chk b/on?
	]
	clicks: clicks + 1
	status/text: ajoin ["Clicked: " b/text "  (" clicks " in all)"]
	refresh b
]

;;=============================================================================
;; Sliders
;;
;; A thin track - a button's frame - filled from its start to the knob with
;; the blue frame, and a knob: a small button's frame, lit as a button is.
;; Horizontal when wider than tall; a vertical one has 0 at the bottom.
;;=============================================================================

knob-length: 12   ;; along the track; across, the slider's whole thickness
track-thick: 6

make-slider: function [
	"A slider in a window or a group, its value from 0 to 1"
	parent [handle!] offset [pair!] size [pair!]
	/value v [number!] "Where it starts (default 0)"
	/steps n [integer!] "Only that many steps between 0 and 1 - 10 for tenths"
	/show "A text after it showing the value"
][
	s: make object! append copy widget-base [
		track: fill: knob: shown: none
		value:     0.0
		steps:     none
		vertical?: false
		size:      none
	]
	s/kind:      'slider
	s/size:      size
	s/vertical?: size/y > size/x
	s/steps:     n
	widget-group s parent offset size
	either s/vertical? [
		at: as-pair (size/x - track-thick) / 2 0
		s/track: add-image/size/part s/group atlas at as-pair track-thick size/y part-of 0
		s/fill:  add-image/size/part s/group atlas at as-pair track-thick size/y part-of 3
		s/knob:  add-image/size/part s/group atlas 0x0 as-pair size/x knob-length part-of 0
	][
		at: as-pair 0 (size/y - track-thick) / 2
		s/track: add-image/size/part s/group atlas at as-pair size/x track-thick part-of 0
		s/fill:  add-image/size/part s/group atlas at as-pair size/x track-thick part-of 3
		s/knob:  add-image/size/part s/group atlas 0x0 as-pair knob-length size/y part-of 0
	]
	foreach img reduce [s/track s/fill s/knob] [img/nine-scale: nine]
	if show [
		th: tsize "0"
		s/shown: add-label parent "" offset + either s/vertical? [
			as-pair 0 size/y + 6
		][
			as-pair size/x + 10 (size/y - th/y) / 2
		]
		s/shown/tint: 170.170.185
	]
	set-value s any [v 0]
	refresh s
	s
]

;; Moves it to `v`, clamped and snapped to its steps; the knob, the fill and
;; the text follow. Whether the value changed.
set-value: function [s v [number!]][
	v: min 1.0 max 0.0 to decimal! v
	if s/steps [v: (round v * s/steps) / s/steps]
	changed?: v <> s/value
	s/value: v
	either s/vertical? [
		travel: s/size/y - knob-length
		at: to integer! round travel * (1.0 - v)
		s/knob/offset: as-pair 0 at
		;; filled from the knob's middle down to the bottom
		mid: at + (knob-length / 2)
		s/fill/offset: as-pair s/fill/offset/x mid
		s/fill/size:   as-pair track-thick max 0 s/size/y - mid
	][
		travel: s/size/x - knob-length
		at: to integer! round travel * v
		s/knob/offset: as-pair at 0
		s/fill/size: as-pair max 0 at + (knob-length / 2) track-thick
	]
	;; An empty fill draws nothing - a zero axis would be the part's own size.
	s/fill/visible?: v > 0
	if s/shown [
		s/shown/text: either s/steps [
			form to integer! round v * s/steps
		][
			ajoin [to integer! round v * 100 "%"]
		]
	]
	changed?
]

;; The value under the pointer: the knob's middle goes there.
value-at: func [s pos [pair!] /local travel][
	either s/vertical? [
		travel: s/size/y - knob-length
		1.0 - ((pos/y - (knob-length / 2)) / travel)
	][
		travel: s/size/x - knob-length
		(pos/x - (knob-length / 2)) / travel
	]
]

;; By a step - its own, or a twentieth - up or down.
nudge: func [s times [number!]][
	slide s s/value + (times / any [s/steps 20])
]

;; Set by the user: reported on the status line when it changed.
slide: func [s v][
	if set-value s v [
		status/text: ajoin ["Slider " index? find-same widgets s ": " either s/steps [
			to integer! round s/value * s/steps
		][
			ajoin [to integer! round s/value * 100 "%"]
		]]
	]
]

find-same: func [blk value][
	forall blk [if same? blk/1 value [return blk]]
	none
]

refresh-slider: func [s][
	s/knob/tint: case [
		not s/enabled?                [110.110.120]
		s/pressed?                    [140.160.220]
		s/hover?                      [200.220.255]
		true                          [none]
	]
	s/fill/tint:  either s/enabled? [none][110.110.120]
	s/track/tint: either s/enabled? [none][110.110.120]
]

;;=============================================================================
;; Text fields
;;
;; A dark frame with the text in a clipped group inside it, so a long text
;; is cut at the edges and scrolled to keep the caret in view. The caret is
;; a 1-unit wide line, shown while the field has the focus. What is typed
;; comes as `char` events - shifted, composed, accented; the keys move the
;; caret and delete. No selection yet.
;;=============================================================================

field-pad: 5      ;; between the frame and the text
caret-img: make image! [1x1 255.255.255]

make-field: function [
	"A one-line text field in a window or a group"
	parent [handle!] offset [pair!] size [pair!]
	/with  t [string!] "Its text to start with"
	/hint  h [string!] "Shown while it is empty"
	/secure "Shows a star for each character"
][
	f: make object! append copy widget-base [
		face: view: label: hint: caret: none
		text:    none
		pos:     0       ;; the caret: how many characters are before it
		shift:   0       ;; how far the text is scrolled left, in units
		secure?: false
		size:    none
	]
	f/kind:    'field
	f/text:    copy any [t ""]
	f/pos:     length? f/text
	f/size:    size
	f/secure?: did secure
	widget-group f parent offset size
	f/group/cursor: 'caret
	f/face: add-image/size/part f/group atlas 0x0 size part-of 4
	f/face/nine-scale: nine
	;; The viewport: clipped to the inside of the frame.
	f/view: add-group/size f/group as-pair field-pad 0 as-pair size/x - (2 * field-pad) size/y
	th: tsize "Xg"
	ty: (size/y - th/y) / 2
	f/hint:  add-label f/view any [h ""] as-pair 0 ty
	f/hint/tint: 110.110.125
	f/label: add-label f/view "" as-pair 0 ty
	f/caret: add-image/size f/view caret-img 0x3 as-pair 1 size/y - 6
	update-field f
	refresh f
	f
]

;; What it shows: the text, or a star for each character.
shown-text: func [f][
	either f/secure? [append/dup copy "" #"*" length? f/text][f/text]
]

;; Where the caret is before character `n + 1`, from the text's start.
caret-x: func [f n /local sz][
	sz: tsize copy/part shown-text f n
	sz/x
]

;; The text, the hint, the caret - and scrolled so the caret is in view,
;; with no empty room at the end while the text is longer than the field.
update-field: func [f /local x w end][
	f/label/text: shown-text f
	f/hint/visible?: empty? f/text
	x:   caret-x f f/pos
	w:   f/view/size/x - 1
	end: caret-x f length? f/text
	if x - f/shift > w [f/shift: x - w]
	if x - f/shift < 0 [f/shift: x]
	if end - f/shift < w [f/shift: max 0 end - w]
	f/label/offset: as-pair negate f/shift f/label/offset/y
	f/caret/offset: as-pair x - f/shift 3
	f/caret/visible?: same? focused f
]

;; The caret to the gap nearest to `x` - units from the viewport's corner.
caret-to: func [f x /local n len][
	x: x + f/shift
	n: 0
	len: length? f/text
	while [all [n < len  ((caret-x f n) + (caret-x f n + 1)) / 2 < x]][n: n + 1]
	f/pos: n
	update-field f
]

type-in: func [f c [char!]][
	insert skip f/text f/pos c
	f/pos: f/pos + 1
	update-field f
]

field-key: func [f key [word!]][
	switch key [
		left      [if f/pos > 0 [f/pos: f/pos - 1]]
		right     [if f/pos < length? f/text [f/pos: f/pos + 1]]
		home up   [f/pos: 0]
		end down  [f/pos: length? f/text]
		backspace [if f/pos > 0 [f/pos: f/pos - 1  remove skip f/text f/pos]]
		delete    [if f/pos < length? f/text [remove skip f/text f/pos]]
	]
	update-field f
]

refresh-field: func [f][
	f/face/tint: case [
		not f/enabled? [110.110.120]
		f/hover?       [200.215.255]
		true           [none]
	]
	f/label/tint: either f/enabled? [none][130.130.140]
]

;;=============================================================================
;; Scrollers
;;
;; A box showing a part of a bigger content: a clipped group - the view -
;; with the content group in it, moved by minus the position. Scroll bars
;; where the content does not fit: a track and a thumb, drawn by the
;; scroller's own group, which is tracked - so a press on a bar is the
;; scroller's, and its drag too. What is in the content is anything:
;; widgets in it work as anywhere else, hit only where they are shown.
;;=============================================================================

bar: 10           ;; the scroll bars' thickness
thumb-min: 16     ;; the shortest a thumb gets

make-scroller: function [
	"A scroller in a window or a group; add to its `content` group"
	parent [handle!] offset [pair!] size [pair!]
	content-size [pair!] "How big what it will show is"
][
	s: make object! append copy widget-base [
		view: content: vtrack: vthumb: htrack: hthumb: corner: none
		pos:   0x0    ;; the content's point at the view's top-left
		size:  none   ;; all of it, bars included
		csize: none   ;; the content's
		vsize: none   ;; the view's: without the bars
		drag:  none   ;; v or h, while a thumb is dragged
		over:  none   ;; v or h, while the pointer is over a thumb
		grab:  0      ;; where on the thumb it was taken
	]
	s/kind:  'scroller
	s/size:  size
	s/csize: content-size
	widget-group s parent offset size
	s/group/cursor: 'arrow
	;; A bar takes room, which can make the other one needed too.
	need-v: need-h: false
	loop 2 [
		need-v: content-size/y > (size/y - either need-h [bar][0])
		need-h: content-size/x > (size/x - either need-v [bar][0])
	]
	s/vsize: size - as-pair either need-v [bar][0] either need-h [bar][0]
	s/view: add-group/size s/group 0x0 s/vsize
	s/content: add-group s/view 0x0
	if need-v [
		s/vtrack: add-image/size/part s/group atlas as-pair s/vsize/x 0 as-pair bar s/vsize/y part-of 4
		s/vthumb: add-image/size/part s/group atlas as-pair s/vsize/x 0 as-pair bar thumb-min part-of 0
	]
	if need-h [
		s/htrack: add-image/size/part s/group atlas as-pair 0 s/vsize/y as-pair s/vsize/x bar part-of 4
		s/hthumb: add-image/size/part s/group atlas as-pair 0 s/vsize/y as-pair thumb-min bar part-of 0
	]
	if all [need-v need-h] [
		s/corner: add-image/size/part s/group atlas s/vsize as-pair bar bar part-of 4
	]
	foreach img reduce [s/vtrack s/vthumb s/htrack s/hthumb s/corner] [
		if img [img/nine-scale: nine]
	]
	scroll-to s 0x0
	refresh s
	s
]

;; How far it can go.
scroll-max: func [s][max 0x0 s/csize - s/vsize]

;; Shows the content from `p`, clamped; the thumbs follow.
scroll-to: function [s p [pair!]][
	most: scroll-max s
	s/pos: as-pair (max 0 min most/x p/x) (max 0 min most/y p/y)
	s/content/offset: negate s/pos
	if s/vthumb [
		len: max thumb-min to integer! s/vsize/y * s/vsize/y / s/csize/y
		at: either most/y > 0 [to integer! round (s/vsize/y - len) * s/pos/y / most/y][0]
		s/vthumb/size:   as-pair bar len
		s/vthumb/offset: as-pair s/vsize/x at
	]
	if s/hthumb [
		len: max thumb-min to integer! s/vsize/x * s/vsize/x / s/csize/x
		at: either most/x > 0 [to integer! round (s/vsize/x - len) * s/pos/x / most/x][0]
		s/hthumb/size:   as-pair len bar
		s/hthumb/offset: as-pair at s/vsize/y
	]
]

scroll-by: func [s d [pair!]][scroll-to s s/pos + d]

;; A press at `p` - from its corner: on a thumb it is taken; on a track
;; elsewhere, the view moves by a page towards it.
press-scroller: function [s p [pair!]][
	if all [s/vthumb  p/x >= s/vsize/x  p/y < s/vsize/y] [
		t: s/vthumb
		either all [p/y >= t/offset/y  p/y < (t/offset/y + t/size/y)] [
			s/drag: 'v  s/grab: p/y - t/offset/y
		][
			scroll-by s as-pair 0 either p/y < t/offset/y [negate s/vsize/y][s/vsize/y]
		]
	]
	if all [s/hthumb  p/y >= s/vsize/y  p/x < s/vsize/x] [
		t: s/hthumb
		either all [p/x >= t/offset/x  p/x < (t/offset/x + t/size/x)] [
			s/drag: 'h  s/grab: p/x - t/offset/x
		][
			scroll-by s as-pair either p/x < t/offset/x [negate s/vsize/x][s/vsize/x] 0
		]
	]
]

;; A thumb dragged to where the pointer is, keeping where it was taken.
drag-scroller: function [s p [pair!]][
	most: scroll-max s
	switch s/drag [
		v [
			room: s/vsize/y - s/vthumb/size/y
			if room > 0 [scroll-to s as-pair s/pos/x (p/y - s/grab) * most/y / room]
		]
		h [
			room: s/vsize/x - s/hthumb/size/x
			if room > 0 [scroll-to s as-pair (p/x - s/grab) * most/x / room s/pos/y]
		]
	]
]

;; Only the thumb taken, or the one under the pointer, is lit.
refresh-scroller: func [s /local tint-of][
	tint-of: func [bar][
		case [
			s/drag = bar [140.160.220]
			all [not s/drag  s/over = bar] [200.220.255]
			true         [none]
		]
	]
	if s/vthumb [s/vthumb/tint: tint-of 'v]
	if s/hthumb [s/hthumb/tint: tint-of 'h]
]

;; Which thumb is at `p` - from the scroller's corner: v, h or none.
thumb-at: func [s p [pair!] /local in?][
	in?: func [t][
		all [t  p/x >= t/offset/x  p/y >= t/offset/y
			p/x < (t/offset/x + t/size/x)  p/y < (t/offset/y + t/size/y)]
	]
	case [
		in? s/vthumb ['v]
		in? s/hthumb ['h]
		true         [none]
	]
]

;; The pointer moved: a scroller under it lights the thumb under it. The
;; scroller is entered as a whole, so this is asked of every move over it.
hover-thumbs: func [event /local o][
	foreach w widgets [
		if w/kind = 'scroller [
			o: either w/hover? [thumb-at w local-of w event][none]
			if o <> w/over [w/over: o  refresh w]
		]
	]
]

;; The scroller a scroll is for: a scroll over a button in one comes from
;; the button - tracked, it is the innermost - and goes to its scroller.
scroller-of: function [source][
	while [all [source  find [pugl-image pugl-group pugl-text] source/type]][
		if all [w: find-widget source  find [scroller slider] w/kind] [return w]
		source: source/parent
	]
	none
]

;;=============================================================================
;; Check boxes and radio buttons
;;
;; A box and a label, in one tracked group: a press anywhere on either is
;; the widget's. A check box is the field's frame with a check mark over
;; it; a radio button a circle with a dot - one of a set, which one block
;; holds: choosing one clears the others.
;;=============================================================================

make-choice: function [
	"A check box - or with /radio a radio button - in a window or a group"
	parent [handle!] text [string!] offset [pair!]
	/radio in-set [block!] "The radio buttons it is one of - it is added"
	/checked "On to start with"
][
	c: make object! append copy widget-base [
		box: mark: label: text: none
		on?:    false
		in-set: none
	]
	c/kind: either radio ['radio]['check]
	c/text: copy text
	ts: tsize text
	gap: 6
	size: as-pair
		box-size + gap + to integer! round/ceiling ts/x
		max box-size to integer! round/ceiling ts/y
	widget-group c parent offset size
	at: as-pair 0 (size/y - box-size) / 2
	either radio [
		c/box:  add-image/part c/group atlas at mark-part 6
		c/mark: add-image/part c/group atlas at mark-part 7
		c/in-set: in-set
		append in-set c
	][
		c/box:  add-image/size/part c/group atlas at as-pair box-size box-size part-of 4
		c/box/nine-scale: nine
		c/mark: add-image/part c/group atlas at mark-part 5
	]
	c/label: add-label c/group c/text as-pair box-size + gap (size/y - ts/y) / 2
	c/on?: did checked
	refresh c
	c
]

refresh-choice: func [c][
	c/box/tint: case [
		not c/enabled?                [110.110.120]
		all [c/pressed?  c/hover?]    [140.160.220]
		c/hover?                      [200.220.255]
		true                          [none]
	]
	c/mark/visible?: c/on?
	c/mark/tint:  either c/enabled? [none][130.130.140]
	c/label/tint: either c/enabled? [none][130.130.140]
]

;; A check box flips; a radio button is chosen, the rest of its set cleared.
choose: func [c][
	either c/kind = 'radio [
		foreach o c/in-set [o/on?: same? o c  refresh o]
		status/text: ajoin ["Chosen: " c/text]
	][
		c/on?: not c/on?
		refresh c
		status/text: ajoin [c/text ": " either c/on? ["on"]["off"]]
	]
]

;; The arrows move the choice through a set, round.
choose-next: func [c step /local set n][
	set: c/in-set
	n: index? find-same set c
	n: n + step
	if n > length? set [n: 1]
	if n < 1 [n: length? set]
	unless set/:n/enabled? [exit]
	choose set/:n
	focus/keyboard set/:n
]

;;=============================================================================
print as-yellow "^/== Buttons"
;;=============================================================================

;; Fixed sizes.
ok-btn: make-button window "OK"     20x20  80x22
cancel-btn: make-button window "Cancel" 108x20 80x22
apply-btn: make-button window "Apply"  196x20 80x22

;; Sized by their labels: a zero axis.
x: 20
foreach text ["Short" "A much longer label" "Příliš žluťoučký"][
	b: make-button window text as-pair x 54 0x0
	x: x + b/face/size/x + 8
]
short-btn: widgets/4

;; States.
disabled-btn: make-button window "Disabled" 20x88 100x22
set-enabled disabled-btn false
toggle-btn:  make-button/toggle  window "Toggle: off" 128x88 100x22
default-btn: make-button/default window "Default" 236x88 100x22

;; Stretched big - the frame's corners keep their size.
big-btn: make-button window "A big one" 20x122 380x40

print ["buttons:         " length? widgets "(expected 10)"]
print ["OK size:         " ok-btn/face/size "(expected 80x22)"]
print ["ring around it:  " ok-btn/ring/size "at" ok-btn/ring/offset "(expected 84x26 at -2x-2)"]
print ["ring hidden:     " not ok-btn/ring/visible? "(expected true)"]
print ["label centred:   " (ok-btn/label/offset * 2) + (tsize "OK") = ok-btn/face/size "(expected true)"]
print ["sized by label:  " short-btn/face/size "for text" tsize "Short" "(text + 20x6, rounded up)"]
print ["frame from part: " mold ok-btn/face/part "(expected [0x0 24x24])"]
print ["default's frame: " mold default-btn/face/part "(expected [24x0 24x24])"]
print ["disabled tint:   " disabled-btn/face/tint "(expected 110.110.120)"]
print ["disabled tracked:" disabled-btn/group/track? "(expected false)"]
print ["image at OK:     " (image-at window ok-btn/group/offset + 3x3) == ok-btn/face "(expected true)"]

;;=============================================================================
print as-yellow "^/== Sliders"
;;=============================================================================

volume:  make-slider/value/show window 20x186 240x16 50%
tenths:  make-slider/steps/show window 20x218 240x16 10
disabled-sld: make-slider/value/show window 20x250 240x16 30%
set-enabled disabled-sld false
upright: make-slider/value/show window 360x186 16x110 75%


print ["sliders:         " length? widgets "(expected 14)"]
print ["value:           " volume/value "(expected 0.5)"]
print ["knob at:         " volume/knob/offset "(expected 114x0 - half of 240 - 12)"]
print ["filled to:       " volume/fill/size "(expected 120x6 - to the knob's middle)"]
print ["shown:           " mold volume/shown/text {(expected "50%")}]
print ["clamped:         " set-value volume 2 volume/value "(expected true 1.0)"]
set-value volume 0.5
print ["snapped:         " set-value tenths 0.33 tenths/value "(expected true 0.3)"]
print ["the same again:  " set-value tenths 0.3 "(expected false - not changed)"]
print ["empty, no fill:  " set-value tenths 0 not tenths/fill/visible? "(expected true true)"]
print ["vertical:        " upright/vertical? "(expected true)"]
print ["its knob at:     " upright/knob/offset "(expected 0x25 - a quarter of 110 - 12, rounded)"]
print ["value at middle: " value-at volume 120x8 "(expected 0.5)"]
print ["value at bottom: " value-at upright 8x104 "(expected 0.0)"]

;;=============================================================================
print as-yellow "^/== Text fields"
;;=============================================================================

name-fld:  make-field/hint window 20x310 240x22 "Your name"
pass-fld:  make-field/secure/hint window 20x342 240x22 "Password"
long-fld:  make-field/with window 20x374 240x22 "A text longer than the field, so it is scrolled to its end"


;;=============================================================================
print as-yellow "^/== A scroller"
;;=============================================================================

sc: make-scroller window 440x20 220x260 480x520
;; Its content: a pattern, lines of text, and buttons - one below the view.
tile: make image! 32x32
repeat y 32 [repeat x 32 [
	tile/(as-pair x y): either odd? (to integer! x - 1 / 16) + (to integer! y - 1 / 16) [44.44.56][36.36.46]
]]
pattern: add-image/size sc/content tile 0x0 480x520
pattern/fill: 'tile
repeat i 10 [
	add-label sc/content ajoin ["Line " i " - the wheel, the bars or the keys move it"] as-pair 10 i * 50 - 32
]
inside-1: make-button sc/content "Inside" 20x70 80x22
inside-2: make-button sc/content "Far right" 380x200 80x22
inside-3: make-button sc/content "At the bottom" 20x490 0x0

print ["view, without bars:" sc/vsize "(expected 210x250)"]
print ["thumbs:          " sc/vthumb/size sc/hthumb/size "(expected 10x120 91x10)"]
print ["can scroll:      " scroll-max sc "(expected 270x270)"]
scroll-to sc 0x10000
print ["clamped:         " sc/pos "(expected 0x270)"]
print ["content moved:   " sc/content/offset "(expected 0x-270)"]
print ["thumb at bottom: " sc/vthumb/offset "(expected 210x130)"]
scroll-to sc 0x0
print ["bar over content:" (image-at window 655x220) == sc/vtrack "(expected true - the content is clipped under it)"]
print ["button inside:   " (image-at window 440x20 + 23x73) == inside-1/face "(expected true)"]
print ["scroller of it:  " same? scroller-of inside-1/group sc "(expected true)"]
focus sc
print ["clicked, no ring:" not sc/ring/visible? "(expected true - focused, but not by Tab)"]
focus/keyboard sc
print ["by Tab, a ring:  " sc/ring/visible? "(expected true)"]
focus ok-btn
print ["a button's ring: " ok-btn/ring/visible? "(expected true - clicked or not)"]
focus none
print ["thumb at:        " thumb-at sc 215x10 thumb-at sc 215x200 thumb-at sc 10x255 "(expected v none h)"]
sc/hover?: true  refresh sc
print ["hovered, unlit:  " none? sc/vthumb/tint "(expected true - only a thumb under the pointer is lit)"]
sc/hover?: false

;;=============================================================================
print as-yellow "^/== Check boxes and radio buttons"
;;=============================================================================

bold-chk:     make-choice/checked window "Bold" 440x300
italic-chk:   make-choice window "Italic" 440x324
disabled-chk: make-choice window "Underline" 440x348
set-enabled disabled-chk false
sizes: copy []
small-rad:  make-choice/radio window "Small" 560x300 sizes
medium-rad: make-choice/radio/checked window "Medium" 560x324 sizes
large-rad:  make-choice/radio window "Large" 560x348 sizes

print ["widgets so far:  " length? widgets "(expected 27 - 17, the scroller and its 3 buttons, these 6)"]
print ["checked:         " bold-chk/on? bold-chk/mark/visible? "(expected true true)"]
print ["unchecked:       " italic-chk/on? italic-chk/mark/visible? "(expected false false)"]
print ["box:             " mold bold-chk/box/part "(expected [96x0 24x24] - the field's)"]
print ["mark:            " mold bold-chk/mark/part "(expected [120x0 14x14])"]
print ["one set:         " length? sizes "(expected 3)"]
print ["chosen:          " medium-rad/on? small-rad/on? large-rad/on? "(expected true false false)"]
print ["label hit:       " (image-at window bold-chk/group/offset + bold-chk/label/offset + 3x6) == bold-chk/label "(expected true)"]
print ["disabled tracked:" disabled-chk/group/track? "(expected false)"]

status: add-label window "Click a button, or Tab to one and press Space" 20x418
status/tint: 170.170.185

print ["empty, hint:     " name-fld/hint/visible? "(expected true)"]
type-in name-fld #"Ž"  type-in name-fld #"a"
print ["typed:           " mold name-fld/text {(expected "Ža")} "caret at" name-fld/pos]
print ["hint gone:       " not name-fld/hint/visible? "(expected true)"]
print ["caret after it:  " name-fld/caret/offset/x = caret-x name-fld 2 "(expected true)"]
field-key name-fld 'left  type-in name-fld #"l"
print ["inserted:        " mold name-fld/text {(expected "Žla")}]
field-key name-fld 'backspace  field-key name-fld 'delete
print ["deleted:         " mold name-fld/text {(expected "Ž")}]
field-key name-fld 'backspace
print ["empty again:     " mold name-fld/text name-fld/hint/visible? {(expected "" true)}]
foreach c "abc" [type-in pass-fld c]
print ["secure shows:    " mold pass-fld/label/text {(expected "***")} "keeps" mold pass-fld/text]
print ["long, scrolled:  " long-fld/shift > 0 "(expected true)"]
print ["caret in view:   " long-fld/caret/offset/x < long-fld/view/size/x "(expected true)"]
field-key long-fld 'home
print ["home, unscrolled:" long-fld/shift = 0 long-fld/caret/offset/x = 0 "(expected true true)"]
print ["caret hidden:    " not name-fld/caret/visible? "(expected true - not focused)"]
choose italic-chk
print ["flipped:         " italic-chk/on? italic-chk/mark/visible? "(expected true true)"]
choose italic-chk
choose large-rad
print ["chose another:   " large-rad/on? medium-rad/on? small-rad/on? "(expected true false false)"]
choose medium-rad
print ["textures:        " window/textures "(expected 5 - the atlas, the font, the background, the caret, the tile)"]

print {
WATCH: dark buttons with light edges, as in font-test.r3 - three of one
size; three as wide as their labels, the last in Czech; a grey disabled one,
a toggle and a blue-edged default one; a big one with its edges kept thin.
Hover: it lights up and the hand shows. Pressed, it darkens; a release off
it is no click. The toggle stays pressed and enables the disabled button
and the disabled slider.
Below, sliders: at 50%, one in tenths, a grey disabled one, and an upright
one at 75%. Press anywhere on one and drag: the knob's middle follows the
pointer, also off the slider, the blue part up to it. The wheel over one
moves it a step; so do the arrow keys when it has the focus - Home and End
to the ends, Page Up and Down by a quarter.
At the bottom, text fields: an empty one with a grey hint, a password one,
and one with a long text, scrolled to its end. Click one - the caret goes to
the nearest gap - and type: Shift, accents and dead keys too. Left, Right,
Home and End (Up and Down too) move the caret, Backspace and Delete delete;
the text scrolls to keep the caret in view. Enter reports the text.
Right, a scroller over a bigger checkered content with lines of text and
three buttons, one far right and one at the bottom. The wheel over it - or
over a button in it - scrolls; drag a thumb, or press a track beside it to
move by a page. Focused, arrows scroll it, Page Up and Down by a page, Home
and End to the top and the bottom. Nothing shows outside it, and the
buttons in it are pressed only where they are shown. Only the thumb under
the pointer lights up, the one dragged darkens. Clicked, it takes the focus
for the keys without a ring; reached by Tab, it shows one.
Below it, check boxes - Bold checked, a disabled Underline - and three radio
buttons, Medium chosen. Click a box or its label; Space does it with the
focus. A radio button chosen clears the others; with the focus on one, the
arrow keys move the choice through the set. The toggle enables Underline.
Tab and Shift-Tab move a blue focus ring over the enabled widgets; Space or
Enter clicks a focused button, Enter with none focused the default one. A
click on the background takes the focus away. The line at the bottom says
what was clicked or moved. Escape or the close button ends the test.
}

do-events window func [event /local w][
	w: find-widget event/source
	switch event/type [
		enter [if w [w/hover?: true   refresh w]]
		leave [
			if w [
				w/hover?: false
				if w/kind = 'scroller [w/over: none]
				refresh w
			]
		]
		down  [
			either w [
				w/pressed?: true  focus w  refresh w
				if w/kind = 'slider [slide w value-at w local-of w event]
				if w/kind = 'field  [caret-to w (pick local-of w event 1) - field-pad]
				if w/kind = 'scroller [press-scroller w local-of w event  refresh w]
				;; a page jump moved the thumb: under the pointer now, or not
				if w/kind = 'scroller [w/over: thumb-at w local-of w event  refresh w]
			][focus none]
		]
		;; While pressed, the moves come from what took the press, wherever
		;; the pointer is.
		move  [
			if all [w  w/pressed?  w/kind = 'slider] [
				slide w value-at w local-of w event
			]
			if all [w  w/pressed?  w/kind = 'scroller] [
				drag-scroller w local-of w event
			]
			hover-thumbs event
		]
		up    [
			if w [
				;; A click only when released over it again.
				if all [w/kind = 'button  w/pressed?  w/group/hover?] [click w]
				if all [find [check radio] w/kind  w/pressed?  w/group/hover?] [choose w]
				if w/kind = 'scroller [
					w/drag: none
					w/over: thumb-at w local-of w event   ;; still over it?
				]
				w/pressed?: false
				refresh w
			]
		]
		;; The wheel over a slider: up for more. Over a scroller, or what is
		;; in it: up shows what is above.
		scroll-line [
			if w: scroller-of event/source [
				either w/kind = 'slider [nudge w event/code][
					scroll-by w as-pair 0 -40 * event/code
				]
			]
		]
		key   [
			switch event/key [
				#"^-"      [focus-next 1]
				#" " #"^M" [
					case [
						all [focused  focused/kind = 'button] [click focused]
						all [focused  find [check radio] focused/kind  event/key = #" "] [choose focused]
						all [focused  focused/kind = 'field  event/key = #"^M"] [
							status/text: ajoin ["Entered: " mold focused/text]
						]
						all [not focused  event/key = #"^M"]  [click default-btn]
					]
				]
			]
		]
		;; What is typed - into the focused field.
		char [
			if all [focused  focused/kind = 'field] [type-in focused to char! event/code]
		]
		named-key [
			switch event/key [
				backtab [focus-next -1]
				escape  [close-window window]
			]
			if all [focused  focused/kind = 'field] [field-key focused event/key]
			if all [focused  focused/kind = 'scroller] [
				switch event/key [
					up        [scroll-by focused 0x-20]
					down      [scroll-by focused 0x20]
					left      [scroll-by focused -20x0]
					right     [scroll-by focused 20x0]
					page-up   [scroll-by focused as-pair 0 negate focused/vsize/y]
					page-down [scroll-by focused as-pair 0 focused/vsize/y]
					home      [scroll-to focused 0x0]
					end       [scroll-to focused as-pair focused/pos/x 100000]
				]
			]
			if all [focused  focused/kind = 'radio] [
				switch event/key [
					down right [choose-next focused 1]
					up left    [choose-next focused -1]
				]
			]
			if all [focused  focused/kind = 'slider] [
				switch event/key [
					right up    [nudge focused 1]
					left down   [nudge focused -1]
					page-up     [slide focused focused/value + 0.25]
					page-down   [slide focused focused/value - 0.25]
					home        [slide focused 0]
					end         [slide focused 1]
				]
			]
		]
		resize [bg/size: window/size]
	]
]

print ["^/clicks:" clicks]
print "done"
