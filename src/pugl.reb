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
		poll-events do-events redraw add-image remove-image
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
	}
]

;; ---------------------------------------------------------------------------
;; C-side configuration
c-prefix: Pugl

c-header: {
extern REBCNT Handle_PuglWindow;
extern REBCNT Handle_PuglImage;

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

	// What the window shows: the images added to it (PUGLIMG*), in the
	// order they are drawn - the first one at the bottom.
	void   *images;

	// Textures of images removed while the window was open. A texture
	// belongs to the window's GL context, which is current only while it
	// draws - so they are deleted at the start of the next draw.
	REBCNT *dead;
	REBCNT  dead_count, dead_size;
} PUGLWIN;

// An image shown in a window. The image! itself is kept in the handle's
// hob->series (which the GC marks); `image` is the same series, for the
// expose handler to read without calling into the interpreter.
typedef struct Pugl_Image_Context {
	REBHOB *hob;     // back reference
	void   *win;     // PUGLWIN* it is shown in; NULL once removed
	void   *next;    // next image of the same window, drawn above this one
	void   *image;   // the image! series; NULL once removed
	REBINT  x, y;    // offset in the window
	REBINT  w, h;    // size it is drawn at; 0 for the image's own
	REBCNT  visible;
	REBCNT  texture;      // GL texture name, 0 before the first draw
	REBINT  tex_w, tex_h; // the size it was made with
	REBCNT  dirty;        // the pixels must be uploaded again
} PUGLIMG;
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
		images   block!    none      "Images added with `add-image`, in drawing order - the first one at the bottom"
		icon     image!    [image! none!] "Icon of the window - its title bar and taskbar entry; on macOS the application's Dock icon, which the last one set wins; none for the default. Copied when set: drawing into the image changes it only when it is set again"
	]
	image: [
		"Pugl image handle - an image! shown in a window"
		;NAME    GET       SET       DESCRIPTION
		image    image!    image!    "The image shown - kept by reference: draw into it and call `redraw`"
		offset   pair!     pair!     "Position of its top-left corner in the window"
		size     pair!     pair!     "Size it is drawn at - scaled to it; a zero axis is the image's own"
		visible? logic!    logic!    "Whether it is drawn"
		window   handle!   none      "The window it is shown in; none once removed"
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
		target [handle!] "A window (all its images) or one image"
	]
	add-image: [
		"Shows an image in a window and returns its handle"
		window [handle!]
		image  [image!]  "Shown as is; the window keeps a reference, not a copy"
		offset [pair!]   "Position of its top-left corner in the window"
		/size sz [pair!] "Scales it to this size (default: the image's own)"
	]
	remove-image: ["Takes an image out of its window" image [handle!]]
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
