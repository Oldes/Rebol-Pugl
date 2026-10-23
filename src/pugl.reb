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
		poll-events do-events redraw
	]
	Purpose: {
		Native top-level windows through the Pugl library.

		Pugl events are NOT posted to system/ports/event: the extension
		keeps its own queue and `poll-events` drains it into a block of
		event! values, the same model as Rebol-GUI.

		The extension registers a device with RDO_AUTO_POLL, so the host
		runs Pugl's main loop iteration from inside WAIT whenever a window
		is open.

		Windows draw with OpenGL. A window shows an image! - by reference, so
		drawing into it and calling `redraw` is all it takes to animate.
	}
]

;; ---------------------------------------------------------------------------
;; C-side configuration
c-prefix: Pugl

c-header: {
extern REBCNT Handle_PuglWindow;

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

	// What the view shows. `image` is the image! series itself, read at
	// every expose; what keeps it alive is the block in hob->series, which
	// the GC marks. NULL for nothing.
	void   *image;
	REBCNT  texture;      // GL texture name in the view's context, 0 before the first draw
	REBINT  tex_w, tex_h; // the size it was made with
	REBCNT  dirty;        // the pixels must be uploaded again
} PUGLWIN;
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
		image    image!    [image! none!] "Image shown at its own size, centered in the window; none for nothing. Kept by reference - draw into it and call `redraw`"
		icon     image!    [image! none!] "Icon of the window - its title bar and taskbar entry; on macOS the application's Dock icon, which the last one set wins; none for the default. Copied when set: drawing into the image changes it only when it is set again"
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
	redraw:       ["Shows the window's image again - use after drawing into it" window [handle!]]
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
