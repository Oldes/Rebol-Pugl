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
;; The atlas: three 24x24 frames side by side - the button's, the default
;; button's and the focus ring - each nine-scaled by [3x3 18x18]: square, a
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

atlas: make image! reduce [as-pair cell * 3 cell 0.0.0.0]    ;; transparent
paint-frame atlas 0x0  70.70.90.255 160.160.200.255 2    ;; a button
paint-frame atlas 24x0 70.70.90.255 120.170.255.255 2    ;; the default one
paint-frame atlas 48x0 none         120.180.255.255 1    ;; the focus ring

part-of: func [n [integer!]][reduce [as-pair n * cell 0  as-pair cell cell]]
nine: [3x3 18x18]

;;=============================================================================
print as-yellow "^/== The window and the font"
;;=============================================================================

window: open-window/title 420x210 "Widgets - buttons"
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
;; Buttons
;;=============================================================================

buttons: copy []
focused: none
clicks:  0
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
	b: make object! [
		group: ring: face: label: text: none
		enabled?: true
		toggle?:  did toggle
		on?:      false
		default?: did default
		hover?:   false
		pressed?: false
	]
	b/text: copy text
	b/group: add-group parent offset
	;; The ring first - below the frame, sticking out around it.
	b/ring: add-image/size/part b/group atlas -2x-2 size + 4x4 part-of 2
	b/ring/nine-scale: nine
	b/ring/visible?: false
	b/face: add-image/size/part b/group atlas 0x0 size part-of either default [1][0]
	b/face/nine-scale: nine
	b/label: add-label b/group b/text 0x0
	b/group/track?: true
	b/group/cursor: 'hand
	center-label b
	refresh b
	append buttons b
	b
]

center-label: func [b][
	b/label/offset: b/face/size - (tsize b/text) / 2
]

;; Its state, as a tint of its frame - as in font-test.r3 - and of its label.
refresh: func [b][
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

;; A disabled button is not tracked: the pointer goes through it to the
;; window, so it gets no events, and shows no hand.
set-enabled: func [b on [logic!]][
	b/enabled?: on
	b/group/track?: on
	b/group/cursor: either on ['hand][none]
	unless on [
		b/hover?: b/pressed?: false
		if same? focused b [focus none]
	]
	refresh b
]

focus: func [b][
	if focused [focused/ring/visible?: false]
	focused: b
	if b [b/ring/visible?: true]
]

;; Tab and Shift-Tab: the next or the previous enabled one.
focus-next: function [step [integer!]][
	live: copy []
	foreach b buttons [if b/enabled? [append/only live b]]
	if empty? live [exit]
	n: 0
	repeat k length? live [if same? live/:k focused [n: k]]
	n: n + step
	if n > length? live [n: 1]
	if n < 1 [n: length? live]
	focus live/:n
]

find-button: func [source][
	foreach b buttons [if b/group == source [return b]]
	none
]

click: func [b][
	if b/toggle? [
		b/on?: not b/on?
		set-text b either b/on? ["Toggle: on"]["Toggle: off"]
		;; the toggle turns the disabled one on and off
		set-enabled disabled-btn b/on?
		set-text disabled-btn either b/on? ["Enabled"]["Disabled"]
	]
	clicks: clicks + 1
	status/text: ajoin ["Clicked: " b/text "  (" clicks " in all)"]
	refresh b
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
short-btn: buttons/4

;; States.
disabled-btn: make-button window "Disabled" 20x88 100x22
set-enabled disabled-btn false
toggle-btn:  make-button/toggle  window "Toggle: off" 128x88 100x22
default-btn: make-button/default window "Default" 236x88 100x22

;; Stretched big - the frame's corners keep their size.
big-btn: make-button window "A big one" 20x122 380x40

status: add-label window "Click a button, or Tab to one and press Space" 20x176
status/tint: 170.170.185

print ["buttons:         " length? buttons "(expected 10)"]
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
print ["textures:        " window/textures "(expected 3 - the atlas, the font, the background)"]

print {
WATCH: dark buttons with light edges, as in font-test.r3 - three of one
size; three as wide as their labels, the last in Czech; a grey disabled one,
a toggle and a blue-edged default one; a big one with its edges kept thin.
Hover: it lights up and the hand shows. Pressed, it darkens; a release off
it is no click. The toggle stays pressed and enables the
disabled one. Tab and Shift-Tab move a blue focus ring over the enabled
buttons; Space or Enter clicks the focused one, Enter with none focused the
default one. A click on the background takes the focus away. The line at the
bottom counts the clicks. Escape or the close button ends the test.
}

do-events window func [event /local b][
	b: find-button event/source
	switch event/type [
		enter [if b [b/hover?: true   refresh b]]
		leave [if b [b/hover?: false  refresh b]]
		down  [
			either b [b/pressed?: true  focus b  refresh b][focus none]
		]
		up    [
			if b [
				;; A click only when released over it again.
				if all [b/pressed?  b/group/hover?] [click b]
				b/pressed?: false
				refresh b
			]
		]
		key   [
			switch event/key [
				#"^-"      [focus-next 1]
				#" " #"^M" [
					case [
						focused  [click focused]
						event/key = #"^M" [click default-btn]
					]
				]
			]
		]
		named-key [
			switch event/key [
				backtab [focus-next -1]
				escape  [close-window window]
			]
		]
		resize [bg/size: window/size]
	]
]

print ["^/clicks:" clicks]
print "done"
