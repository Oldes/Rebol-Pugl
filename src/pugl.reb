REBOL [
	Title:   "Rebol Pugl extension"
	Name:    pugl
	Version: 0.0.1
	Needs:   3.22.10
	Author:  @Oldes
	License: MIT
	Options: [delay]
	Exports: [
		open-window close-window show-window hide-window
		poll-events do-events redraw add-image remove-image add-group
		image-at add-text text-size make-font screens
	]
	Purpose: {
		Native top-level windows through the Pugl library.

		Pugl events are NOT posted to system/ports/event: the extension
		keeps its own queue and `poll-events` drains it into a block of
		event! values, the same model as Rebol-GUI.

		The extension registers a device with RDO_AUTO_POLL, so the host
		runs Pugl's main loop iteration from inside WAIT whenever a window
		is open.

		Windows draw with OpenGL. `add-image` puts an image! in a window - by
		reference, so drawing into it and calling `redraw` is all it takes
		to animate. Images are drawn in the order they were added.

		`add-group` makes a group, which images and other groups are added
		to like to a window: their offsets are relative to it, and it moves,
		hides and is entered and left as a whole. With a size, it clips what
		is in it - a viewport, scrolled by moving what is inside.

		Images and groups can be turned, scaled and faded - `rotation`,
		`scale`, `pivot`, `opacity` - and a group does it to all in it. The
		pointer finds them where they are drawn, clipping included.

		`add-text` shows a line - or lines - of text in a bitmap font: one
		node, drawn from the font's atlas in one go, its text settable.
		`make-font` makes the font from an object with `atlas` (an image!)
		and `glyphs` (a map! of char to [offset size bearing advance]).

		`screens` gives the connected displays, the primary first, and a
		window's `screen` the one it is on - the same handle for the same
		display, measured in units like a window's offset.
	}
]

;; ---------------------------------------------------------------------------
;; C-side configuration
c-prefix: Pugl

c-header: {
extern REBCNT Handle_PuglWindow;
extern REBCNT Handle_PuglImage;
extern REBCNT Handle_PuglGroup;
extern REBCNT Handle_PuglText;
extern REBCNT Handle_PuglFont;
extern REBCNT Handle_PuglScreen;

// A screen: a display, named by the key its platform finds it by again
// (see pugl-screen.h) - every read asks the platform.
#ifndef PUGL_SCREEN_KEY
#define PUGL_SCREEN_KEY 64
#endif
typedef struct Pugl_Screen_Context {
	REBHOB *hob;
	char    key[PUGL_SCREEN_KEY];
} PUGLSCREEN;

// A glyph of a bitmap font: its box in the atlas, where that goes from the
// pen at the line's top-left (bx, by), and how far the pen then moves.
typedef struct Pugl_Glyph {
	u32     code;     // its character
	REBINT  x, y, w, h;
	REBINT  bx, by;
	REBINT  advance;
} PUGLGLYPH;

// A bitmap font: an atlas image! and its glyphs, sorted by character for
// a binary search. The atlas is also in hob->series, for the GC.
typedef struct Pugl_Font_Context {
	REBHOB    *hob;
	void      *image;        // the atlas image! series
	PUGLGLYPH *glyphs;
	REBCNT     count;
	PUGLGLYPH  fallback;     // drawn for a character it has no glyph for
	REBCNT     has_fallback; // ... when there is one; else such are skipped
	REBINT     line_height;
	REBCNT     uses;         // text nodes showing it - locked while any are
} PUGLFONT;

// The device which runs puglUpdate() from the host's WAIT.
extern REBDEV Dev_Pugl;
extern int    Pugl_Dev_Id;

// A texture of a window, shared by every image handle in it showing the
// same image! - uploaded once, however many handles show it. A slot is
// free while nothing uses it (refs 0); slots are never moved, so a handle
// keeps its slot number.
typedef struct Pugl_Texture {
	void   *image;   // the image! series it is made from (marked by the handles)
	REBCNT  texture; // GL texture name, 0 before the first draw
	REBINT  w, h;    // the size it was made with
	REBCNT  refs;    // image handles using it
	REBCNT  dirty;   // the pixels must be uploaded again
	REBCNT  filter;  // W_PUGL_FILTER_* it is set to now, 0 before its first draw
	REBCNT  wrap;    // repeated (TRUE) or clamped as set now; 2 before its first draw
	REBCNT  version; // counts its uploads - a pattern copied from it knows when to copy again
} PUGLTEX;

// The payload is opaque (`view` is a void* rather than a PuglView*), so
// that gen-pugl.h stays free of pugl's own headers.
typedef struct Pugl_Window_Context {
	void   *view;   // PuglView*; NULL once the view is closed
	REBHOB *hob;    // back reference, so queued events can name their source
	void   *next;   // next open view (PUGLWIN*), so they can all be
	                // closed before the world is freed
	REBINT  x, y;   // position and size, device pixels, as pugl last said -
	REBINT  w, h;   // one `configure` for both
	REBINT  ux, uy; // ... and in units, as last reported - Rebol has
	REBINT  uw, uh; // `offset` and `resize`, sent when these change
	double  scale;  // device pixels per unit set with `scale:`; 0 for the screen's

	// The native icon objects, where a platform keeps any (Windows: the
	// big and the small HICON). The image! itself is in hob->series.
	void   *icon[2];

	// What the window shows: the images and groups added to it
	// (PUGLNODE*), in the order they are drawn - the first one at the
	// bottom. A group draws its own the same way, where it is in the list.
	void   *images;

	// The textures of its images, shared between handles showing the same
	// image!, in slots which do not move (PUGLTEX).
	PUGLTEX *tex;
	REBCNT   tex_size;

	// Textures of images removed while the window was open. A texture
	// belongs to the window's GL context, which is current only while it
	// draws - so they are deleted at the start of the next draw.
	REBCNT *dead;
	REBCNT  dead_count, dead_size;

	// The image the pointer is over (PUGLNODE*), worked out when the queued
	// pointer events are converted - and where it was last seen over it,
	// for that image's `leave`. The groups it is in are hovered too. Right
	// after a removal it can be a group: the pointer is still in it, but
	// over nothing in it until the next move says otherwise.
	void   *hover;
	REBINT  hover_x, hover_y;

	// The buttons held down (bit 0 primary, 1 secondary, 2 middle), as of
	// the events converted so far - a move outside the window is reported
	// only while one is, the same on every platform.
	REBCNT  buttons;

	// The tracked image or group which took the press (PUGLNODE*): its
	// `up` and its drag `move`s come from it until every button is up,
	// wherever the pointer goes - so a button sees its own release.
	void   *capture;

	// The window's own cursor (W_PUGL_CURSOR_*, 0 for arrow), and the one
	// shown now - set only on a change.
	REBCNT  cursor;
	REBCNT  cursor_now;
} PUGLWIN;

// An image shown in a window, or a group of them - the same context for
// both, as they sit in the same lists. The image! itself is kept in the
// handle's hob->series (which the GC marks); `image` is the same series,
// for the expose handler to read without calling into the interpreter.
typedef struct Pugl_Node_Context {
	REBHOB *hob;     // back reference
	void   *win;     // PUGLWIN* it is shown in; NULL once removed
	void   *parent;  // PUGLNODE* group it is in; NULL at the window's top
	void   *next;    // next one in the same list, drawn above this one
	void   *children;// a group's own list (PUGLNODE*)
	REBCNT  group;   // a group, not an image
	void   *image;   // the image! series; NULL once removed, and for groups
	REBINT  x, y;    // offset in the window, or in the group it is in
	REBINT  w, h;    // size it is drawn at; 0 for the image's own - for a
	                 // group the size it clips to; 0 for not clipped
	REBCNT  visible;
	REBCNT  track;   // `track?`: enter and leave are reported for it

	// The transform: moved to offset, then around the pivot turned by
	// `rot` degrees (clockwise - y points down) and scaled. A group's
	// applies to everything in it, and so does its opacity, multiplied.
	double  rot;
	double  sx, sy;
	double  px, py;
	double  opacity; // 0.0 - 1.0
	REBCNT  blend;   // W_PUGL_BLEND_*, or 0 for the group's (normal at the top)
	REBCNT  cursor;      // W_PUGL_CURSOR_*, or 0 for its group's (the window's)
	REBCNT  filter;      // W_PUGL_FILTER_*, or 0 for its group's (nearest at the top)
	REBCNT  tint_len;    // 0 for no tint, else 3 or 4 - the tuple as set
	REBYTE  tint[4];     // R G B, and A where tint_len is 4 (255 opaque)
	REBCNT  slot;    // its window's texture slot, 1-based; 0 for none

	// The part of the image! shown, in its pixels - an atlas frame. part_w 0
	// is the whole image. Its size is the image's own size where `size`
	// has a zero axis.
	REBINT  part_x, part_y, part_w, part_h;

	// `nine-scale`: the box of the middle, in its own pixels (its part's).
	// Outside it the corners keep their size and the edges stretch one
	// way only. nine 0 is plain scaling.
	REBCNT  nine;
	REBINT  nine_x, nine_y, nine_w, nine_h;
	REBCNT  fill;    // W_PUGL_FILL_*, 0 for scale: how stretched pieces fill

	// A part filled as a pattern repeats only itself, which GL_REPEAT on
	// the atlas cannot do: the part is copied into a texture of its own -
	// again when the part, the image! or its pixels (`version`) change.
	REBCNT  pat_tex;      // GL texture name, 0 for none
	REBCNT  pat_version;  // of the shared texture it was copied from
	void   *pat_image;    // the image! it was copied from
	REBINT  pat_x, pat_y, pat_w, pat_h;  // the part it holds
	REBCNT  pat_filter;   // W_PUGL_FILTER_* it is set to now

	// A text node: the characters of its text (C memory, UTF-32) in a font
	// (PUGLFONT*, whose handle is in hob->series), and the size they take.
	REBCNT  is_text;
	void   *font;
	u32    *chars;
	REBCNT  nchars;
	REBINT  text_w, text_h;
	REBCNT  align;        // W_PUGL_ALIGN_*, 0 for left
} PUGLNODE;
}

;; ---------------------------------------------------------------------------
;; Words resolved at init time. ORDER IS SIGNIFICANT - each list's enum is
;; its positions, so append, never insert. The `arg:` list is collected from
;; `handles:` by the generator.
words: [
	;; What `blend` takes and answers.
	blend: [
		normal      ;; over what is below, by its alpha
		add         ;; its colour added - lighter, light through light
		multiply    ;; what is below multiplied by it - darker, like a filter
		screen      ;; the inverse of multiply - lighter, never past white
	]
	;; How an image fills a size other than its own.
	fill: [
		scale       ;; stretched to it
		tile        ;; repeated at its own size, as a pattern - the last ones cut
		round       ;; repeated a whole number of times, scaled a little to fit
	]
	;; How a texture is sampled when it is not drawn 1:1.
	filter: [
		nearest     ;; the nearest pixel - sharp, blocky when scaled; pixel art, atlases
		linear      ;; between the nearest four - smooth when scaled or turned
	]
	;; Pointer shapes - pugl's own, in its order (PuglCursor).
	cursor: [
		arrow               ;; the default pointing arrow
		caret               ;; the I-beam, for text
		crosshair
		hand                ;; a pointing finger - something to click
		no                  ;; not allowed
		left-right          ;; horizontal resize
		up-down             ;; vertical resize
		up-left-down-right  ;; diagonal resize
		up-right-down-left  ;; the other diagonal
		all-scroll          ;; move or pan in any direction
	]
	;; How the lines of a text line up.
	align: [
		left
		center
		right
	]
	;; What `index` takes besides a number.
	place: [
		top         ;; drawn last in its list - above the rest of it
		bottom      ;; drawn first - below the rest of it
	]
]

;; ---------------------------------------------------------------------------
;; Handle types and their path accessors.
handles: [
	window: [
		"Pugl window handle - a top-level window with an OpenGL view"
		;NAME    GET       SET       DESCRIPTION
		title    string!   string!   "Text shown in the title bar"
		size     pair!     pair!     "Size of the window, in units"
		offset   pair!     pair!     "Position of the top-left corner on the screen, in units"
		scale    decimal!  [decimal! integer! none!] "Device pixels per unit - the screen's, 1.0 at standard DPI and 2.0 on a Retina display, until set (up to 16); none follows the screen again. Everything is in units: sizes, offsets, events, images - drawn this many times bigger. Setting it zooms: the window keeps its size on the screen, so its size in units changes, reported as `resize`"
		id       integer!  none      "Native view handle (HWND / NSView* / X11 Window) as an integer"
		visible? logic!    none      "Whether the window is currently visible"
		open?    logic!    none      "False once the window has been closed"
		images   block!    none      "Images and groups added to it, in drawing order - the first one at the bottom"
		textures integer!  none      "How many textures it holds - one per image! shown, however many image handles show it"
		cursor   word!     word!     "The pointer's shape over it, where nothing under the pointer has its own: arrow (default), caret, crosshair, hand, no, left-right, up-down, up-left-down-right, up-right-down-left or all-scroll"
		icon     image!    [image! none!] "Icon of the window - its title bar and taskbar entry; on macOS the application's Dock icon, which the last one set wins; none for the default. Copied when set: drawing into the image changes it only when it is set again"
		screen   handle!   none      "The screen holding most of it - the same handle `screens` gives for that display; none while it is on none"
	]
	image: [
		"Pugl image handle - an image! shown in a window"
		;NAME    GET       SET       DESCRIPTION
		image    image!    image!    "The image shown - kept by reference: draw into it and call `redraw`"
		fill     word!     word!     "How it fills a size other than its own - scale (default); tile: repeated at its own size, the last ones cut; round: repeated a whole number of times, each scaled to fit. Not nine-scaled, it is a pattern: one shape, the texture repeated by the GPU - a part gets a copy of its own for it. With nine-scale, its edges and middle are repeated"
		nine-scale block!  [block! none!] "Scales it in nine pieces - [offset size] of the middle box, in its own pixels; the corners keep their size and the edges stretch one way only; none (default) scales it whole"
		part     block!    [block! none!] "The part of the image shown - [offset size] in its pixels, a frame of an atlas; none (default) for all of it. Set, only the first two values are used, so a block of many parts can be walked"
		offset   pair!     pair!     "Position of its top-left corner in the window - or in its group"
		size     pair!     pair!     "Size it is drawn at - scaled to it; a zero axis is the image's own, or its part's"
		visible? logic!    logic!    "Whether it is drawn"
		track?   logic!    logic!    "Whether it reports the pointer itself, as the event source: enter and leave, presses - and their release and drag, wherever the pointer goes - and scrolls over it; off by default"
		hover?   logic!    none      "Whether the pointer is over it - the topmost visible image under the pointer, as of the last `poll-events`"
		window   handle!   none      "The window it is shown in; none once removed"
		parent   handle!   none      "The group it is in; none at the window's top level"
		rotation decimal!  [decimal! integer!] "Degrees it is turned around its pivot, clockwise (default 0.0)"
		scale    [decimal! pair!] [decimal! integer! pair!] "Scale around its pivot - one for both axes, or a pair for each (default 1.0); a pair! only while the two differ"
		pivot    pair!     pair!     "Point it is turned and scaled around, in its own units from its top-left (default 0x0)"
		opacity  percent!  [percent! decimal! integer!] "How opaque it is, 0% to 100% (default 100%); still there for the pointer at 0%"
		blend    word!     [word! none!] "How it is drawn over what is below: normal, add, multiply or screen; none (default) for its group's"
		filter   word!     [word! none!] "How it is sampled when not drawn 1:1 - nearest: sharp pixels, or linear: smooth; none (default) for its group's, nearest at the top. An atlas drawn linear wants a gap between its frames"
		cursor   word!     [word! none!] "The pointer's shape over it - one of the window's cursor words; none (default) for its group's, or the window's"
		tint     tuple!    [tuple! none!] "A colour its own is multiplied by - a fourth value is alpha, 255 opaque, multiplied with its opacity; none (default) for none"
		index    integer!  [integer! word!] "Its place in its window's or group's list, 1 at the bottom; set a number (clamped) or top or bottom to move it"
	]
	group: [
		"Pugl group handle - images and groups moved, hidden and hovered together"
		;NAME    GET       SET       DESCRIPTION
		offset   pair!     pair!     "Position of its origin in the window - or in its group; what is in it is placed relative to it"
		size     pair!     pair!     "Size of the box from its origin which what is in it is clipped to - drawn and hit only inside; a zero axis is not clipped (default 0x0)"
		visible? logic!    logic!    "Whether what is in it is drawn"
		track?   logic!    logic!    "Whether it reports the pointer itself, as a whole, as the event source: enter and leave, and presses and scrolls over any of its images which do not track it themselves; off by default"
		hover?   logic!    none      "Whether the pointer is over one of its images, as of the last `poll-events`"
		images   block!    none      "Images and groups added to it, in drawing order"
		window   handle!   none      "The window it is shown in; none once removed"
		parent   handle!   none      "The group it is in; none at the window's top level"
		rotation decimal!  [decimal! integer!] "Degrees it - and all in it - is turned around its pivot, clockwise (default 0.0)"
		scale    [decimal! pair!] [decimal! integer! pair!] "Scale around its pivot, of all in it - one for both axes, or a pair for each (default 1.0)"
		pivot    pair!     pair!     "Point it is turned and scaled around, in its own units from its origin (default 0x0)"
		opacity  percent!  [percent! decimal! integer!] "How opaque all in it is, 0% to 100% (default 100%), multiplied with their own"
		blend    word!     [word! none!] "How what is in it is drawn, where it does not say itself: normal, add, multiply or screen; none (default) for its own group's"
		filter   word!     [word! none!] "How all in it is sampled, where it does not say itself - nearest or linear; none (default) for its own group's"
		cursor   word!     [word! none!] "The pointer's shape over all in it which does not have its own; none (default) for its group's, or the window's"
		tint     tuple!    [tuple! none!] "A colour all in it is multiplied by, on top of their own tint - a fourth value is alpha; none (default) for none"
		index    integer!  [integer! word!] "Its place in its window's or group's list, 1 at the bottom; set a number (clamped) or top or bottom to move it, with all in it"
	]
	text: [
		"Pugl text handle - lines of text in a bitmap font, one node drawn from the font's atlas"
		;NAME    GET       SET       DESCRIPTION
		text     string!   string!   "The text shown - a newline starts the next line"
		font     handle!   handle!   "The font it is drawn in, from `make-font`"
		align    word!     word!     "How its lines line up: left (default), center or right - within the widest"
		size     pair!     none      "The size its text takes: the widest line, by the lines times the line height"
		offset   pair!     pair!     "Position of its top-left in the window - or in its group"
		visible? logic!    logic!    "Whether it is drawn"
		track?   logic!    logic!    "Whether it reports the pointer itself, as an image does"
		hover?   logic!    none      "Whether the pointer is over it"
		window   handle!   none      "The window it is shown in; none once removed"
		parent   handle!   none      "The group it is in; none at the window's top level"
		rotation decimal!  [decimal! integer!] "Degrees it is turned around its pivot, clockwise"
		scale    [decimal! pair!] [decimal! integer! pair!] "Scale around its pivot - 2 for twice as big, crisp with nearest"
		pivot    pair!     pair!     "Point it is turned and scaled around"
		opacity  percent!  [percent! decimal! integer!] "How opaque it is"
		blend    word!     [word! none!] "How it is drawn over what is below; none for its group's"
		filter   word!     [word! none!] "How its glyphs are sampled when not 1:1; none for its group's"
		cursor   word!     [word! none!] "The pointer's shape over it; none for its group's"
		tint     tuple!    [tuple! none!] "Its colour - the glyphs are white; none for white"
		index    integer!  [integer! word!] "Its place in its window's or group's list"
	]
	font: [
		"Pugl font handle - a bitmap font for `add-text`"
		;NAME        GET       SET       DESCRIPTION
		line-height  integer!  none      "Height of a line of text, in units"
		glyphs       integer!  none      "How many characters it has a glyph for"
		atlas        image!    none      "The image its glyphs are drawn from"
		fallback?    logic!    none      "Whether a character it has no glyph for is drawn as its fallback glyph - or skipped"
	]
	screen: [
		"Pugl screen handle - one display; every read asks the platform again"
		;NAME    GET       SET   DESCRIPTION
		name     string!   none  "What the system calls the display"
		size     pair!     none  "Size of the whole display, in its units"
		offset   pair!     none  "Top-left corner, in the same space as a window's offset"
		work-size   pair!  none  "Size of the part windows should use - without the taskbar, the Dock or the menu bar"
		work-offset pair!  none  "Top-left corner of that part"
		scale    decimal!  none  "Device pixels per unit - what a window on this screen reports as its own scale, until that is set"
		primary? logic!    none  "Whether this is the primary screen - the one with the menu bar on macOS"
	]
]

;; ---------------------------------------------------------------------------
;; Commands. Order is significant - new ones are appended, not inserted.
commands: [
	open-window: [
		"Creates a top-level window and returns its handle"
		size [pair!] "Size of the window, in units - device pixels / scale"
		/title text [string!] "Text shown in the title bar"
		/at offset [pair!] "Position of the top-left corner on the screen, in units"
		/hidden "Creates the window without showing it"
		/fixed  "The user cannot resize it"
	]
	close-window: ["Destroys the window" window [handle!]]
	show-window:  ["Makes the window visible" window [handle!]]
	hide-window:  ["Hides the window without destroying it" window [handle!]]
	poll-events:  ["Runs one Pugl main loop iteration and returns the collected events"]
	redraw: [
		"Shows images again - use after drawing into them"
		target [handle!] "A window or a group (all the images in it) or one image"
	]
	add-image: [
		"Shows an image in a window or a group and returns its handle"
		target [handle!] "A window, or a group - then the offset is relative to it"
		image  [image!]  "Shown as is; the window keeps a reference, not a copy"
		offset [pair!]   "Position of its top-left corner in the window"
		/size sz [pair!] "Scales it to this size (default: the image's own)"
		/part rect [block!] "Shows only this part of the image: [offset size] in its pixels - the first two values, so a block of many parts can be walked"
	]
	remove-image: [
		"Takes an image out of its window - or a group, with all that is in it"
		image [handle!] "An image or a group"
	]
	add-group: [
		"Makes a group in a window or a group and returns its handle"
		target [handle!] "A window, or a group"
		offset [pair!]   "Position of its origin - what is added to it is placed relative to it"
		/size sz [pair!] "Clips what is in it to this size (default: not clipped)"
	]
	image-at: [
		"The topmost visible image at a point of the window, or none - where it is drawn, turned and clipped"
		window [handle!]
		point  [pair!] "In the window, as an event's offset"
	]
	add-text: [
		"Shows text in a bitmap font in a window or a group, and returns its handle"
		target [handle!] "A window, or a group"
		font   [handle!] "From `make-font`"
		text   [string!] "A newline starts the next line"
		offset [pair!]   "Position of its top-left"
	]
	text-size: [
		"The size a text takes in a font: the widest line, by the lines times the line height"
		font [handle!]
		text [string!]
	]
	font-from: [
		"Makes a font handle - use `make-font`, which gives these from an object"
		atlas       [image!]
		glyphs      [block!] "char [offset size bearing advance] ..."
		line-height [integer!]
		fallback    [block! none!] "[offset size bearing advance] of the glyph for characters it has none for"
	]
	screens: [
		"Returns a block of the connected screens, the primary one first"
	]
]

;; ---------------------------------------------------------------------------
;; Module body.
mezzanine: [
	make-font: function [
		"Makes a bitmap font for `add-text`, from an object such as a font file returns"
		font [object!] {With `atlas` (an image!) and `glyphs` (a map! or block of char [offset size bearing advance]); optionally `line-height` (else `size`) and `fallback` - a glyph block, a char whose glyph to use, or none to skip characters it has no glyph for}
	][
		fallback: select font 'fallback
		if char? fallback [fallback: select/case font/glyphs fallback]
		font-from
			font/atlas
			to block! font/glyphs
			any [select font 'line-height  select font 'size]
			fallback
	]

	do-events: function [
		"Pumps window events until the given window is closed"
		window  [handle!]
		handler [any-function!] "Called with one event! for each event"
		/rate delay [number!] {Longest it may sleep with nothing to do (default: 0.02)}
	][
		;; `wait` does the sleeping, and the device pumps Pugl from inside
		;; it. There is no doorbell port yet, so an event is noticed at the
		;; end of the delay at the latest.
		delay: any [delay 0.02]
		forever [
			foreach evt poll-events [
				handler evt
				;; `close` only reports the request - closing is ours to do
				;; `==`, not `=`: on handles `=` compares only the type,
				;; so any window's close would match
				if all [evt/type = 'close  evt/source == window] [
					close-window window
				]
				unless window/open? [break]
			]
			unless window/open? [exit]
			wait delay
		]
	]
]
