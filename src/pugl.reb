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
		hides and is entered and left as a whole.
	}
]

;; ---------------------------------------------------------------------------
;; C-side configuration
c-prefix: Pugl

c-header: {
extern REBCNT Handle_PuglWindow;
extern REBCNT Handle_PuglImage;
extern REBCNT Handle_PuglGroup;

// The device which runs puglUpdate() from the host's WAIT.
extern REBDEV Dev_Pugl;
extern int    Pugl_Dev_Id;

// The payload is opaque (`view` is a void* rather than a PuglView*), so
// that gen-pugl.h stays free of pugl's own headers.
typedef struct Pugl_Window_Context {
	void   *view;   // PuglView*; NULL once the view is closed
	REBHOB *hob;    // back reference, so queued events can name their source
	void   *next;   // next open view (PUGLWIN*), so they can all be
	                // closed before the world is freed
	REBINT  x, y;   // position and size last reported - Pugl sends one
	REBINT  w, h;   // `configure` for both, Rebol has `offset` and `resize`

	// The native icon objects, where a platform keeps any (Windows: the
	// big and the small HICON). The image! itself is in hob->series.
	void   *icon[2];

	// What the window shows: the images and groups added to it
	// (PUGLNODE*), in the order they are drawn - the first one at the
	// bottom. A group draws its own the same way, where it is in the list.
	void   *images;

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
	REBINT  w, h;    // size it is drawn at; 0 for the image's own
	REBCNT  visible;
	REBCNT  track;   // `track?`: enter and leave are reported for it
	REBCNT  texture;      // GL texture name, 0 before the first draw
	REBINT  tex_w, tex_h; // the size it was made with
	REBCNT  dirty;        // the pixels must be uploaded again
} PUGLNODE;
}

;; ---------------------------------------------------------------------------
;; Handle types and their path accessors.
handles: [
	window: [
		"Pugl window handle - a top-level window with an OpenGL view"
		;NAME    GET       SET       DESCRIPTION
		title    string!   string!   "Text shown in the title bar"
		size     pair!     pair!     "Size of the window"
		offset   pair!     pair!     "Position of the top-left corner on the screen"
		scale    decimal!  none      "Scale factor - 1.0 at standard DPI, 2.0 on a Retina display"
		id       integer!  none      "Native view handle (HWND / NSView* / X11 Window) as an integer"
		visible? logic!    none      "Whether the window is currently visible"
		open?    logic!    none      "False once the window has been closed"
		images   block!    none      "Images and groups added to it, in drawing order - the first one at the bottom"
		icon     image!    [image! none!] "Icon of the window - its title bar and taskbar entry; on macOS the application's Dock icon, which the last one set wins; none for the default. Copied when set: drawing into the image changes it only when it is set again"
	]
	image: [
		"Pugl image handle - an image! shown in a window"
		;NAME    GET       SET       DESCRIPTION
		image    image!    image!    "The image shown - kept by reference: draw into it and call `redraw`"
		offset   pair!     pair!     "Position of its top-left corner in the window - or in its group"
		size     pair!     pair!     "Size it is drawn at - scaled to it; a zero axis is the image's own"
		visible? logic!    logic!    "Whether it is drawn"
		track?   logic!    logic!    "Whether `enter` and `leave` are reported for it, with the image as the source; off by default"
		hover?   logic!    none      "Whether the pointer is over it - the topmost visible image under the pointer, as of the last `poll-events`"
		window   handle!   none      "The window it is shown in; none once removed"
		parent   handle!   none      "The group it is in; none at the window's top level"
	]
	group: [
		"Pugl group handle - images and groups moved, hidden and hovered together"
		;NAME    GET       SET       DESCRIPTION
		offset   pair!     pair!     "Position of its origin in the window - or in its group; what is in it is placed relative to it"
		visible? logic!    logic!    "Whether what is in it is drawn"
		track?   logic!    logic!    "Whether `enter` and `leave` are reported for it as a whole, with the group as the source; off by default"
		hover?   logic!    none      "Whether the pointer is over one of its images, as of the last `poll-events`"
		images   block!    none      "Images and groups added to it, in drawing order"
		window   handle!   none      "The window it is shown in; none once removed"
		parent   handle!   none      "The group it is in; none at the window's top level"
	]
]

;; ---------------------------------------------------------------------------
;; Commands. Order is significant - new ones are appended, not inserted.
commands: [
	open-window: [
		"Creates a top-level window and returns its handle"
		size [pair!] "Size of the window"
		/title text [string!] "Text shown in the title bar"
		/at offset [pair!] "Position of the top-left corner on the screen"
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
	]
	remove-image: [
		"Takes an image out of its window - or a group, with all that is in it"
		image [handle!] "An image or a group"
	]
	add-group: [
		"Makes a group in a window or a group and returns its handle"
		target [handle!] "A window, or a group"
		offset [pair!]   "Position of its origin - what is added to it is placed relative to it"
	]
]

;; ---------------------------------------------------------------------------
;; Module body.
mezzanine: [
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
