Rebol [
	Title:   "Rebol/Pugl - basic widgets"
	Needs:   3.22.10
	Purpose: {
		Basic widgets built of what the extension has: a group, a
		nine-scaled frame from an atlas and a text - buttons, sliders, text
		fields, a scroller, check boxes and radio buttons. With focus, Tab
		order, hover, press and the keys.

		`do` it to get an object of them; `init` it with a window before
		making any, and hand it every event:

			ui: do %widgets.reb
			ui/init window
			ok: ui/make-button window "OK" 20x20 80x22
			ok/action: func [b][print "OK!"]
			do-events window func [event][ui/handle event]

		A widget is an object with its tracked group in `group` - entered,
		left and pressed as a whole, and a press keeps it until the release.
		Its `action` - a function of the widget - is called when it is used:
		a button clicked, a slider moved, Enter in a field, a check box or a
		radio button chosen. `on-action`, when set, is called after it for
		every widget.

		The text is Ubuntu at 12 units, from the `font` folder next to this
		file: of its atlases - 12, 15, 16, 18, 21 and 24 px - the smallest
		with at least as many pixels as the screen has for 12 units, drawn
		scaled to 12 units - so on a screen at 1.4 the 18 px one, drawn at
		2/3, smooth. Labels are put on whole device pixels.
	}
]

make object! [
	dir: system/script/path   ;; where the fonts are, in font/

	;;=========================================================================
	;; The atlas: 24x24 cells side by side. Five frames - the button's, the
	;; default button's, the focus ring, a slider's filled part and a field's
	;; - each nine-scaled by [3x3 18x18]: square, a dark face in a light edge.
	;; Hover, pressed and disabled are tints of it. Then three marks of 14x14,
	;; drawn smooth, shown at their size: a check mark, a radio button's
	;; circle and its dot.
	;;=========================================================================

	cell: 24
	nine: [3x3 18x18]
	box-size: 14

	part-of:   func [n [integer!]][reduce [as-pair n * cell 0  as-pair cell cell]]
	mark-part: func [n [integer!]][reduce [as-pair n * cell 0  as-pair box-size box-size]]

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
	;; A mark: each pixel's coverage by a shape, as its alpha. `shade` gives
	;; a pixel's centre [color alpha], or none.
	paint-mark: func [img [image!] at [pair!] shade [any-function!] /local c][
		repeat y box-size [
			repeat x box-size [
				if c: shade x - 0.5 y - 0.5 [
					if c/2 > 0 [img/(at + as-pair x y): rgba c/1 c/2]
				]
			]
		]
	]

	atlas: make image! reduce [as-pair cell * 8 cell 0.0.0.0]    ;; transparent
	paint-frame atlas 0x0  70.70.90.255   160.160.200.255 2  ;; a button
	paint-frame atlas 24x0 70.70.90.255   120.170.255.255 2  ;; the default one
	paint-frame atlas 48x0 none           120.180.255.255 1  ;; the focus ring
	paint-frame atlas 72x0 80.120.210.255 120.170.255.255 2  ;; a slider's fill
	paint-frame atlas 96x0 22.22.28.255   110.110.140.255 1  ;; a field
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

	caret-img: make image! [1x1 255.255.255]

	;;=========================================================================
	;; The window and the font
	;;=========================================================================

	window:     none
	font:       none
	font-px:    12      ;; the size of the atlas used
	text-scale: 1.0     ;; how much its glyphs are scaled: 12 / font-px
	font-sizes: [12 15 16 18 21 24]   ;; Ubuntu's atlases in font/
	text-units: 12      ;; the text's size, in units

	init: func [
		"Readies the widgets for a window - before any is made"
		win [handle!]
		/with-font fnt [handle!] "Another font than Ubuntu, drawn at its size"
		/local want
	][
		window: win
		either with-font [
			font: fnt
			text-scale: 1.0
		][
			;; As many pixels as the screen has for the text - or the next
			;; atlas up, scaled down a little: smooth, and never blocky.
			want: text-units * win/scale
			font-px: last font-sizes
			foreach n font-sizes [if n >= (want - 0.01) [font-px: n  break]]
			text-scale: text-units / font-px
			font: make-font do join dir rejoin [%font/ubuntu- font-px %.reb]
		]
		font
	]

	;; The size a text takes in units, as it is drawn.
	tsize: func [text [string!]][
		(text-size font text) * text-scale
	]

	;; A position on whole device pixels: glyphs drawn between two pixels
	;; would be blurred.
	snap: func [p [pair!] /local k][
		k: any [all [window window/scale] 1.0]
		as-pair (round p/x * k) / k  (round p/y * k) / k
	]

	;; Text at the size of the font.
	add-label: func [
		"A text in the widgets' font"
		parent [handle!] text [string!] offset [pair!] /local t
	][
		t: add-text parent font text snap offset
		if text-scale <> 1.0 [t/scale: text-scale  t/filter: 'linear]
		t
	]

	;;=========================================================================
	;; What all widgets share: a tracked group, a focus ring, a state.
	;;=========================================================================

	widgets:   copy []   ;; in Tab order
	focused:   none
	default-button: none ;; clicked by Enter when nothing has the focus
	on-action: none      ;; a function of the widget, after its own action

	;; The fields every widget has; a kind adds its own.
	widget-base: [
		kind: group: ring: none
		enabled?: true
		hover?:   false
		pressed?: false
		action:   none
	]

	;; The group, and the ring in it - below what follows, sticking out
	;; around a box of `size`.
	widget-group: func [w parent offset size][
		w/group: add-group parent offset
		w/ring: add-image/size/part w/group atlas -2x-2 size + 4x4 part-of 2
		w/ring/nine-scale: nine
		w/ring/visible?: false
		w/group/track?: true
		w/group/cursor: 'hand
		append widgets w
	]

	;; It was used: its action, then the general one.
	act: func [w][
		if any-function? get in w 'action [w/action w]
		if any-function? :on-action [on-action w]
	]

	refresh: func [w][
		switch w/kind [
			button      [refresh-button w]
			slider      [refresh-slider w]
			field       [refresh-field w]
			scroller    [refresh-scroller w]
			check radio [refresh-choice w]
		]
	]

	;; A disabled widget is not tracked: the pointer goes through it to the
	;; window, so it gets no events, and shows no hand.
	set-enabled: func [w on [logic!]][
		w/enabled?: on
		w/group/track?: on
		w/group/cursor: either on [
			switch/default w/kind [field ['caret] scroller ['arrow]]['hand]
		][none]
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

	find-same: func [blk value][
		forall blk [if same? blk/1 value [return blk]]
		none
	]

	;; Where an event's offset - in the window - is in a widget, from its
	;; group's corner: its group's offset and those of the groups it is in
	;; taken away. (Turned or scaled groups are not undone.)
	local-of: func [w event /local p g][
		p: event/offset
		g: w/group
		while [g][
			p: p - g/offset
			g: g/parent
		]
		p
	]

	;;=========================================================================
	;; Buttons
	;;=========================================================================

	padding: 10x3   ;; around the label of a button sized by it

	make-button: function [
		"A button in a window or a group; a zero axis of size is the label's, padded"
		parent [handle!] text [string!] offset [pair!] size [pair!]
		/toggle  "Stays pressed until clicked again - `on?`"
		/default "Edged in blue, and clicked by Enter when nothing has the focus"
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
		if default [set 'default-button b]
		b
	]

	center-label: func [b][
		b/label/offset: snap b/face/size - (tsize b/text) / 2
	]

	;; Its state, as a tint of its frame - and of its label.
	refresh-button: func [b][
		b/face/tint: case [
			not b/enabled?                         [110.110.120]
			any [b/on?  all [b/pressed? b/hover?]] [140.160.220]
			b/hover?                               [200.220.255]
			true                                   [none]
		]
		b/label/tint: either b/enabled? [none][130.130.140]   ;; white, or grey
	]

	set-text: func [
		"A button's label"
		b text [string!]
	][
		b/text: copy text
		b/label/text: b/text
		center-label b
	]

	;; Clicked: a toggle flips first, so its action sees the new state.
	click: func [b][
		if b/toggle? [b/on?: not b/on?]
		refresh b
		act b
	]

	;;=========================================================================
	;; Sliders
	;;
	;; A thin track - a button's frame - filled from its start to the knob
	;; with the blue frame, and a knob: a small button's frame, lit as a
	;; button is. Horizontal when wider than tall; a vertical one has 0 at
	;; the bottom.
	;;=========================================================================

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

	;; The value as shown: its step, or a percent.
	value-text: func [s][
		either s/steps [
			form to integer! round s/value * s/steps
		][
			ajoin [to integer! round s/value * 100 "%"]
		]
	]

	set-value: function [
		{Moves a slider to `v`, clamped and snapped to its steps - no action. Whether it changed}
		s v [number!]
	][
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
		if s/shown [s/shown/text: value-text s]
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

	;; Moved by the user: its action, when it changed.
	slide: func [s v][
		if set-value s v [act s]
	]

	;; By a step - its own, or a twentieth - up or down.
	nudge: func [s times [number!]][
		slide s s/value + (times / any [s/steps 20])
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

	;;=========================================================================
	;; Text fields
	;;
	;; A dark frame with the text in a clipped group inside it, so a long
	;; text is cut at the edges and scrolled to keep the caret in view. The
	;; caret is a 1-unit wide line, shown while the field has the focus.
	;; What is typed comes as `char` events - shifted, composed, accented;
	;; the keys move the caret and delete. Enter is its action. No selection
	;; yet.
	;;=========================================================================

	field-pad: 5      ;; between the frame and the text

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
		f/label/offset: snap as-pair negate f/shift f/label/offset/y
		f/caret/offset: as-pair x - f/shift 3
		f/caret/visible?: same? focused f
	]

	set-field: func [
		"A field's text, the caret at its end"
		f text [string!]
	][
		f/text: copy text
		f/pos: length? f/text
		update-field f
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

	;;=========================================================================
	;; Scrollers
	;;
	;; A box showing a part of a bigger content: a clipped group - the view
	;; - with the content group in it, moved by minus the position. Scroll
	;; bars where the content does not fit: a track and a thumb, drawn by
	;; the scroller's own group, which is tracked - so a press on a bar is
	;; the scroller's, and its drag too. What is in the content is anything:
	;; widgets in it work as anywhere else, hit only where they are shown.
	;;=========================================================================

	bar: 10           ;; the scroll bars' thickness
	thumb-min: 16     ;; the shortest a thumb gets
	wheel-step: 40    ;; units a line of the wheel scrolls

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

	scroll-to: function [
		"Shows a scroller's content from `p`, clamped; the thumbs follow"
		s p [pair!]
	][
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
		tint-of: func [which][
			case [
				s/drag = which                   [140.160.220]
				all [not s/drag  s/over = which] [200.220.255]
				true                             [none]
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

	;; What a scroll is for: a slider or a scroller - also a scroll over a
	;; button in one, which comes from the button (tracked, it is the
	;; innermost) and goes to its scroller.
	scroller-of: function [source][
		while [all [source  find [pugl-image pugl-group pugl-text] source/type]][
			if all [w: find-widget source  find [scroller slider] w/kind] [return w]
			source: source/parent
		]
		none
	]

	;;=========================================================================
	;; Check boxes and radio buttons
	;;
	;; A box and a label, in one tracked group: a press anywhere on either
	;; is the widget's. A check box is the field's frame with a check mark
	;; over it; a radio button a circle with a dot - one of a set, which one
	;; block holds: choosing one clears the others.
	;;=========================================================================

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

	choose: func [
		"A check box flips; a radio button is chosen, the rest of its set cleared"
		c
	][
		either c/kind = 'radio [
			foreach o c/in-set [o/on?: same? o c  refresh o]
		][
			c/on?: not c/on?
			refresh c
		]
		act c
	]

	;; The arrows move the choice through a set, round.
	choose-next: func [c step /local radios n][
		radios: c/in-set
		n: index? find-same radios c
		n: n + step
		if n > length? radios [n: 1]
		if n < 1 [n: length? radios]
		unless radios/:n/enabled? [exit]
		choose radios/:n
		focus/keyboard radios/:n
	]

	;;=========================================================================
	;; Events
	;;=========================================================================

	handle: func [
		"Hands an event to the widgets; whether it was theirs"
		event [event!] /local w
	][
		w: find-widget event/source
		switch/default event/type [
			enter [
				unless w [return false]
				w/hover?: true
				refresh w
			]
			leave [
				unless w [return false]
				w/hover?: false
				if w/kind = 'scroller [w/over: none]
				refresh w
			]
			down [
				;; A press on nothing takes the focus away.
				unless w [focus none  return false]
				w/pressed?: true  focus w  refresh w
				switch w/kind [
					slider   [slide w value-at w local-of w event]
					field    [caret-to w (pick local-of w event 1) - field-pad]
					scroller [
						press-scroller w local-of w event
						;; a page jump moved the thumb: under the pointer now, or not
						w/over: thumb-at w local-of w event
						refresh w
					]
				]
			]
			;; While pressed, the moves come from what took the press,
			;; wherever the pointer is.
			move [
				if all [w  w/pressed?] [
					switch w/kind [
						slider   [slide w value-at w local-of w event]
						scroller [drag-scroller w local-of w event]
					]
				]
				hover-thumbs event
				return false   ;; others may want moves too
			]
			up [
				unless w [return false]
				;; A click only when released over it again.
				if all [w/pressed?  w/group/hover?] [
					switch w/kind [
						button      [click w]
						check radio [choose w]
					]
				]
				if w/kind = 'scroller [
					w/drag: none
					w/over: thumb-at w local-of w event   ;; still over it?
				]
				w/pressed?: false
				refresh w
			]
			;; The wheel over a slider: up for more. Over a scroller, or what
			;; is in it: up shows what is above.
			scroll-line [
				unless w: scroller-of event/source [return false]
				either w/kind = 'slider [nudge w event/code][
					scroll-by w as-pair 0 negate wheel-step * event/code
				]
			]
			key [
				switch/default event/key [
					#"^-" [focus-next 1]
					#" " [
						unless focused [return false]
						switch/default focused/kind [
							button      [click focused]
							check radio [choose focused]
						][return false]
					]
					#"^M" [
						case [
							not focused [
								either default-button [click default-button][return false]
							]
							focused/kind = 'button [click focused]
							focused/kind = 'field  [act focused]
							true [return false]
						]
					]
				][return false]
			]
			;; What is typed - into the focused field.
			char [
				unless all [focused  focused/kind = 'field] [return false]
				type-in focused to char! event/code
			]
			named-key [
				if event/key = 'backtab [focus-next -1  return true]
				unless focused [return false]
				switch/default focused/kind [
					field [field-key focused event/key]
					scroller [
						switch/default event/key [
							up        [scroll-by focused 0x-20]
							down      [scroll-by focused 0x20]
							left      [scroll-by focused -20x0]
							right     [scroll-by focused 20x0]
							page-up   [scroll-by focused as-pair 0 negate focused/vsize/y]
							page-down [scroll-by focused as-pair 0 focused/vsize/y]
							home      [scroll-to focused 0x0]
							end       [scroll-to focused as-pair focused/pos/x 100000]
						][return false]
					]
					slider [
						switch/default event/key [
							right up    [nudge focused 1]
							left down   [nudge focused -1]
							page-up     [slide focused focused/value + 0.25]
							page-down   [slide focused focused/value - 0.25]
							home        [slide focused 0]
							end         [slide focused 1]
						][return false]
					]
					radio [
						switch/default event/key [
							down right [choose-next focused 1]
							up left    [choose-next focused -1]
						][return false]
					]
				][return false]
			]
		][return false]
		true
	]
]
