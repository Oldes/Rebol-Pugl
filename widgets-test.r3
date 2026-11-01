Rebol [
	Title:   "Rebol/Pugl - basic widgets test"
	Needs:   3.22.10
	Purpose: {
		Basic widgets built of what the extension has: a group, a
		nine-scaled frame from an atlas and a text. For now: buttons.

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
;; The atlas: four 24x24 frames side by side - the button's, the default
;; button's, the focus ring and a slider's filled part - each nine-scaled by
;; [3x3 18x18]: square, a
;; dark face in a light edge, as the button in font-test.r3. Hover, pressed
;; and disabled are tints of it.
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

atlas: make image! reduce [as-pair cell * 4 cell 0.0.0.0]    ;; transparent
paint-frame atlas 0x0  70.70.90.255 160.160.200.255 2    ;; a button
paint-frame atlas 24x0 70.70.90.255 120.170.255.255 2    ;; the default one
paint-frame atlas 48x0 none         120.180.255.255 1    ;; the focus ring
paint-frame atlas 72x0 80.120.210.255 120.170.255.255 2  ;; a slider's fill

part-of: func [n [integer!]][reduce [as-pair n * cell 0  as-pair cell cell]]
nine: [3x3 18x18]

;;=============================================================================
print as-yellow "^/== The window and the font"
;;=============================================================================

window: open-window/title 420x370 "Widgets"
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
	]
]

;; A disabled widget is not tracked: the pointer goes through it to the
;; window, so it gets no events, and shows no hand.
set-enabled: func [w on [logic!]][
	w/enabled?: on
	w/group/track?: on
	w/group/cursor: either on ['hand][none]
	unless on [
		w/hover?: w/pressed?: false
		if same? focused w [focus none]
	]
	refresh w
]

focus: func [w][
	if focused [focused/ring/visible?: false]
	focused: w
	if w [w/ring/visible?: true]
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
	focus live/:n
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

status: add-label window "Click a button, or Tab to one and press Space" 20x340
status/tint: 170.170.185

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
print ["textures:        " window/textures "(expected 3 - the atlas, the font, the background)"]

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
Tab and Shift-Tab move a blue focus ring over the enabled widgets; Space or
Enter clicks a focused button, Enter with none focused the default one. A
click on the background takes the focus away. The line at the bottom says
what was clicked or moved. Escape or the close button ends the test.
}

do-events window func [event /local w][
	w: find-widget event/source
	switch event/type [
		enter [if w [w/hover?: true   refresh w]]
		leave [if w [w/hover?: false  refresh w]]
		down  [
			either w [
				w/pressed?: true  focus w  refresh w
				if w/kind = 'slider [slide w value-at w local-of w event]
			][focus none]
		]
		;; While pressed, the moves come from what took the press, wherever
		;; the pointer is.
		move  [
			if all [w  w/pressed?  w/kind = 'slider] [
				slide w value-at w local-of w event
			]
		]
		up    [
			if w [
				;; A click only when released over it again.
				if all [w/kind = 'button  w/pressed?  w/group/hover?] [click w]
				w/pressed?: false
				refresh w
			]
		]
		;; The wheel over a slider: up for more.
		scroll-line [
			if all [w  w/kind = 'slider] [nudge w event/code]
		]
		key   [
			switch event/key [
				#"^-"      [focus-next 1]
				#" " #"^M" [
					case [
						all [focused  focused/kind = 'button] [click focused]
						all [not focused  event/key = #"^M"]  [click default-btn]
					]
				]
			]
		]
		named-key [
			switch event/key [
				backtab [focus-next -1]
				escape  [close-window window]
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
