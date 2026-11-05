Rebol [
	Title:   "Rebol/Pugl - basic widgets test"
	Needs:   3.22.10
	Purpose: {
		Tests the widgets of widgets.reb - buttons, sliders, text fields, a
		scroller, check boxes and radio buttons: what can be checked by
		itself is printed with what is expected, the rest is to be tried.

		Usage:
			r3 widgets-test.r3
	}
]

try [system/modules/pugl: none]
if modules-dir: get-env 'REBOL_MODULES_DIR [
	system/options/modules: dirize to-rebol-file modules-dir
]
pugl: import 'pugl

ui: do %widgets.reb

;;=============================================================================
print as-yellow "^/== The window and the font"
;;=============================================================================

window: open-window/title 680x450 "Widgets"
print ["window scale:    " window/scale]
ui/init window
;; The atlas with the screen's pixels for 12 units - or the next one up.
print ["font:            " ajoin ["Ubuntu " ui/font-px " px, drawn at " ui/text-scale]]
print ["  (expected 12 px at 1.0 and 15 at 1.25; 18 px at 1.4 and 1.5; 24 at 2)"]
print ["text size of OK: " ui/tsize "OK" "(about 17x15, scaled from the atlas)"]
print ["snapped:         " ui/snap 10.3x7.6 "(expected 10x8 at 1.0, 10.4x8 at 1.25)"]

;; A plain dark background, stretched over the window.
bg: add-image/size window make image! [1x1 30.30.38] 0x0 window/size

;; The line at the bottom: what was used last.
status: ui/add-label window "Click a button, or Tab to one and press Space" 20x418
status/tint: 170.170.185
clicks: 0

ui/on-action: func [w][
	status/text: switch w/kind [
		button [
			clicks: clicks + 1
			ajoin ["Clicked: " w/text "  (" clicks " in all)"]
		]
		slider [ajoin ["Slider: " ui/value-text w]]
		field  [ajoin ["Entered: " mold w/text]]
		check  [ajoin [w/text ": " either w/on? ["on"]["off"]]]
		radio  [ajoin ["Chosen: " w/text]]
	]
]

;;=============================================================================
print as-yellow "^/== Buttons"
;;=============================================================================

;; Fixed sizes.
ok-btn:     ui/make-button window "OK"     20x20  80x22
cancel-btn: ui/make-button window "Cancel" 108x20 80x22
apply-btn:  ui/make-button window "Apply"  196x20 80x22

;; Sized by their labels: a zero axis.
x: 20
foreach text ["Short" "A much longer label" "Příliš žluťoučký"][
	b: ui/make-button window text as-pair x 54 0x0
	x: x + b/face/size/x + 8
]
short-btn: ui/widgets/4

;; States.
disabled-btn: ui/make-button window "Disabled" 20x88 100x22
ui/set-enabled disabled-btn false
toggle-btn:  ui/make-button/toggle  window "Toggle: off" 128x88 100x22
default-btn: ui/make-button/default window "Default" 236x88 100x22

;; Stretched big - the frame's corners keep their size.
big-btn: ui/make-button window "A big one" 20x122 380x40

;; The toggle turns the disabled ones on and off.
toggle-btn/action: func [b][
	ui/set-text b either b/on? ["Toggle: on"]["Toggle: off"]
	ui/set-enabled disabled-btn b/on?
	ui/set-text disabled-btn either b/on? ["Enabled"]["Disabled"]
	ui/set-enabled disabled-sld b/on?
	ui/set-enabled disabled-chk b/on?
]

print ["buttons:         " length? ui/widgets "(expected 10)"]
print ["OK size:         " ok-btn/face/size "(expected 80x22)"]
print ["ring around it:  " ok-btn/ring/size "at" ok-btn/ring/offset "(expected 84x26 at -2x-2)"]
print ["ring hidden:     " not ok-btn/ring/visible? "(expected true)"]
print ["label centred:   " 1 >= abs (ok-btn/label/offset/x * 2) + (pick ui/tsize "OK" 1) - 80 "(expected true - to a device pixel)"]
print ["sized by label:  " short-btn/face/size "for text" ui/tsize "Short" "(text + 20x6, rounded up)"]
print ["frame from part: " mold ok-btn/face/part "(expected [0x0 24x24])"]
print ["default's frame: " mold default-btn/face/part "(expected [24x0 24x24])"]
print ["the default:     " same? ui/default-button default-btn "(expected true)"]
print ["disabled tint:   " disabled-btn/face/tint "(expected 110.110.120)"]
print ["disabled tracked:" disabled-btn/group/track? "(expected false)"]
print ["image at OK:     " (image-at window ok-btn/group/offset + 3x3) == ok-btn/face "(expected true)"]

;;=============================================================================
print as-yellow "^/== Sliders"
;;=============================================================================

volume:  ui/make-slider/value/show window 20x186 240x16 50%
tenths:  ui/make-slider/steps/show window 20x218 240x16 10
disabled-sld: ui/make-slider/value/show window 20x250 240x16 30%
ui/set-enabled disabled-sld false
upright: ui/make-slider/value/show window 360x186 16x110 75%

print ["sliders:         " length? ui/widgets "(expected 14)"]
print ["value:           " volume/value "(expected 0.5)"]
print ["knob at:         " volume/knob/offset "(expected 114x0 - half of 240 - 12)"]
print ["filled to:       " volume/fill/size "(expected 120x6 - to the knob's middle)"]
print ["shown:           " mold volume/shown/text {(expected "50%")}]
print ["clamped:         " ui/set-value volume 2 volume/value "(expected true 1.0)"]
ui/set-value volume 0.5
print ["snapped:         " ui/set-value tenths 0.33 tenths/value "(expected true 0.3)"]
print ["the same again:  " ui/set-value tenths 0.3 "(expected false - not changed)"]
print ["empty, no fill:  " ui/set-value tenths 0 not tenths/fill/visible? "(expected true true)"]
print ["vertical:        " upright/vertical? "(expected true)"]
print ["its knob at:     " upright/knob/offset "(expected 0x25 - a quarter of 110 - 12, rounded)"]
print ["value at middle: " ui/value-at volume 120x8 "(expected 0.5)"]
print ["value at bottom: " ui/value-at upright 8x104 "(expected 0.0)"]

;;=============================================================================
print as-yellow "^/== Text fields"
;;=============================================================================

name-fld: ui/make-field/hint window 20x310 240x22 "Your name"
pass-fld: ui/make-field/secure/hint window 20x342 240x22 "Password"
long-fld: ui/make-field/with window 20x374 240x22 "A text longer than the field, so it is scrolled to its end"

print ["empty, hint:     " name-fld/hint/visible? "(expected true)"]
ui/type-in name-fld #"Ž"  ui/type-in name-fld #"a"
print ["typed:           " mold name-fld/text {(expected "Ža")} "caret at" name-fld/pos]
print ["hint gone:       " not name-fld/hint/visible? "(expected true)"]
print ["caret after it:  " name-fld/caret/offset/x = ui/caret-x name-fld 2 "(expected true)"]
ui/field-key name-fld 'left  ui/type-in name-fld #"l"
print ["inserted:        " mold name-fld/text {(expected "Žla")}]
ui/field-key name-fld 'backspace  ui/field-key name-fld 'delete
print ["deleted:         " mold name-fld/text {(expected "Ž")}]
ui/field-key name-fld 'backspace
print ["empty again:     " mold name-fld/text name-fld/hint/visible? {(expected "" true)}]
foreach c "abc" [ui/type-in pass-fld c]
print ["secure shows:    " mold pass-fld/label/text {(expected "***")} "keeps" mold pass-fld/text]
print ["long, scrolled:  " long-fld/shift > 0 "(expected true)"]
print ["caret in view:   " long-fld/caret/offset/x < long-fld/view/size/x "(expected true)"]
ui/field-key long-fld 'home
print ["home, unscrolled:" long-fld/shift = 0 long-fld/caret/offset/x = 0 "(expected true true)"]
print ["caret hidden:    " not name-fld/caret/visible? "(expected true - not focused)"]
ui/set-field name-fld "Oldes"
print ["set:             " mold name-fld/text name-fld/pos {(expected "Oldes" 5)}]
ui/set-field name-fld ""

;;=============================================================================
print as-yellow "^/== A scroller"
;;=============================================================================

sc: ui/make-scroller window 440x20 220x260 480x520
;; Its content: a pattern, lines of text, and buttons - one below the view.
tile: make image! 32x32
repeat y 32 [repeat x 32 [
	tile/(as-pair x y): either odd? (to integer! x - 1 / 16) + (to integer! y - 1 / 16) [44.44.56][36.36.46]
]]
pattern: add-image/size sc/content tile 0x0 480x520
pattern/fill: 'tile
repeat i 10 [
	ui/add-label sc/content ajoin ["Line " i " - the wheel, the bars or the keys move it"] as-pair 10 i * 50 - 32
]
inside-1: ui/make-button sc/content "Inside" 20x70 80x22
inside-2: ui/make-button sc/content "Far right" 380x200 80x22
inside-3: ui/make-button sc/content "At the bottom" 20x490 0x0

print ["view, without bars:" sc/vsize "(expected 210x250)"]
print ["thumbs:          " sc/vthumb/size sc/hthumb/size "(expected 10x120 91x10)"]
print ["can scroll:      " ui/scroll-max sc "(expected 270x270)"]
ui/scroll-to sc 0x10000
print ["clamped:         " sc/pos "(expected 0x270)"]
print ["content moved:   " sc/content/offset "(expected 0x-270)"]
print ["thumb at bottom: " sc/vthumb/offset "(expected 210x130)"]
ui/scroll-to sc 0x0
print ["bar over content:" (image-at window 655x220) == sc/vtrack "(expected true - the content is clipped under it)"]
print ["button inside:   " (image-at window 440x20 + 23x73) == inside-1/face "(expected true)"]
print ["scroller of it:  " same? ui/scroller-of inside-1/group sc "(expected true)"]
ui/focus sc
print ["clicked, no ring:" not sc/ring/visible? "(expected true - focused, but not by Tab)"]
ui/focus/keyboard sc
print ["by Tab, a ring:  " sc/ring/visible? "(expected true)"]
ui/focus ok-btn
print ["a button's ring: " ok-btn/ring/visible? "(expected true - clicked or not)"]
ui/focus none
print ["thumb at:        " ui/thumb-at sc 215x10 ui/thumb-at sc 215x200 ui/thumb-at sc 10x255 "(expected v none h)"]
sc/hover?: true  ui/refresh sc
ui/scroll-to sc 100x100
ui/resize-scroller sc 220x260 200x200
print ["fits, no bars:   " none? sc/vthumb none? sc/hthumb sc/vsize sc/pos "(expected true true 220x260 0x0)"]
ui/resize-scroller sc 220x260 480x520
print ["bars again:      " sc/vthumb/size sc/hthumb/size "(expected 10x120 91x10)"]
print ["above the view:  " (image-at window 655x220) == sc/vtrack "(expected true)"]
print ["hovered, unlit:  " none? sc/vthumb/tint "(expected true - only a thumb under the pointer is lit)"]
sc/hover?: false

;;=============================================================================
print as-yellow "^/== Check boxes and radio buttons"
;;=============================================================================

bold-chk:     ui/make-choice/checked window "Bold" 440x300
italic-chk:   ui/make-choice window "Italic" 440x324
disabled-chk: ui/make-choice window "Underline" 440x348
ui/set-enabled disabled-chk false
sizes: copy []
small-rad:  ui/make-choice/radio window "Small" 560x300 sizes
medium-rad: ui/make-choice/radio/checked window "Medium" 560x324 sizes
large-rad:  ui/make-choice/radio window "Large" 560x348 sizes

print ["widgets so far:  " length? ui/widgets "(expected 27 - 17, the scroller and its 3 buttons, these 6)"]
print ["checked:         " bold-chk/on? bold-chk/mark/visible? "(expected true true)"]
print ["unchecked:       " italic-chk/on? italic-chk/mark/visible? "(expected false false)"]
print ["box:             " mold bold-chk/box/part "(expected [96x0 24x24] - the field's)"]
print ["mark:            " mold bold-chk/mark/part "(expected [120x0 14x14])"]
print ["one set:         " length? sizes "(expected 3)"]
print ["chosen:          " medium-rad/on? small-rad/on? large-rad/on? "(expected true false false)"]
print ["label hit:       " (image-at window bold-chk/group/offset + bold-chk/label/offset + 3x6) == bold-chk/label "(expected true)"]
print ["disabled tracked:" disabled-chk/group/track? "(expected false)"]
acted: none
italic-chk/action: func [c][acted: c/on?]
ui/choose italic-chk
print ["flipped:         " italic-chk/on? italic-chk/mark/visible? "(expected true true)"]
print ["its action:      " acted "(expected true - called with it flipped)"]
print ["status:          " mold status/text {(expected "Italic: on")}]
ui/choose italic-chk
italic-chk/action: none
ui/choose large-rad
print ["chose another:   " large-rad/on? medium-rad/on? small-rad/on? "(expected true false false)"]
ui/choose medium-rad
status/text: "Click a button, or Tab to one and press Space"
print ["textures:        " window/textures "(expected 5 - the atlas, the font, the background, the caret, the tile)"]

print {
WATCH: dark buttons with light edges - three of one size; three as wide as
their labels, the last in Czech; a grey disabled one, a toggle and a
blue-edged default one; a big one with its edges kept thin. Hover: it lights
up and the hand shows. Pressed, it darkens; a release off it is no click.
The toggle stays pressed and enables the disabled button, the disabled slider
and the disabled check box.
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
arrow keys move the choice through the set.
Tab and Shift-Tab move a blue focus ring over the enabled widgets; Space or
Enter clicks a focused button, Enter with none focused the default one. A
click on the background takes the focus away. The line at the bottom says
what was used. Escape or the close button ends the test.
}

do-events window func [event][
	ui/handle event
	;; What is the window's, whatever the widgets did with it.
	switch event/type [
		named-key [if event/key = 'escape [close-window window]]
		resize    [bg/size: window/size]
	]
]

print ["^/clicks:" clicks]
print "done"
