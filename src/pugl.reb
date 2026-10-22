REBOL [
	Title:   "Rebol Pugl extension"
	Name:    pugl
	Version: 0.0.1
	Needs:   3.22.10
	Author:  @Oldes
	License: MIT
	Options: [delay]
	Exports: [
		open-view close-view show-view hide-view
		poll-events do-events
	]
	Purpose: {
		Native top-level views (windows) through the Pugl library.

		Pugl events are NOT posted to system/ports/event: the extension
		keeps its own queue and `poll-events` drains it into a block of
		event! values, the same model as Rebol-GUI.

		The extension registers a device with RDO_AUTO_POLL, so the host
		runs Pugl's main loop iteration from inside WAIT whenever a view
		is open.
	}
]

;; ---------------------------------------------------------------------------
;; C-side configuration
c-prefix: Pugl

c-header: {
extern REBCNT Handle_PuglView;

// The device which runs puglUpdate() from the host's WAIT.
extern REBDEV Dev_Pugl;
extern int    Pugl_Dev_Id;

// The payload is opaque (`view` is a void* rather than a PuglView*), so
// that gen-pugl.h stays free of pugl's own headers.
typedef struct Pugl_View_Context {
	void   *view;   // PuglView*; NULL once the view is closed
	REBHOB *hob;    // back reference, so queued events can name their source
	void   *next;   // next open view (PUGLVIEWCTX*), so they can all be
	                // closed before the world is freed
	REBINT  x, y;   // position and size last reported - Pugl sends one
	REBINT  w, h;   // `configure` for both, Rebol has `offset` and `resize`
} PUGLVIEWCTX;
}

;; ---------------------------------------------------------------------------
;; Handle types and their path accessors.
handles: [
	view: [
		"Pugl view handle - a top-level window"
		;NAME    GET       SET       DESCRIPTION
		title    string!   string!   "Text shown in the title bar"
		size     pair!     pair!     "Size of the view"
		offset   pair!     pair!     "Position of the top-left corner on the screen"
		scale    decimal!  none      "Scale factor - 1.0 at standard DPI, 2.0 on a Retina display"
		id       integer!  none      "Native view handle (HWND / NSView* / X11 Window) as an integer"
		visible? logic!    none      "Whether the view is currently visible"
		open?    logic!    none      "False once the view has been closed"
	]
]

;; ---------------------------------------------------------------------------
;; Commands. Order is significant - new ones are appended, not inserted.
commands: [
	open-view: [
		"Creates a top-level view and returns its handle"
		size [pair!] "Size of the view"
		/title text [string!] "Text shown in the title bar"
		/at offset [pair!] "Position of the top-left corner on the screen"
		/hidden "Creates the view without showing it"
		/fixed  "The user cannot resize it"
	]
	close-view:  ["Destroys the view" view [handle!]]
	show-view:   ["Makes the view visible" view [handle!]]
	hide-view:   ["Hides the view without destroying it" view [handle!]]
	poll-events: ["Runs one Pugl main loop iteration and returns the collected events"]
]

;; ---------------------------------------------------------------------------
;; Module body.
mezzanine: [
	do-events: function [
		"Pumps view events until the given view is closed"
		view    [handle!]
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
				;; so any view's close would match
				if all [evt/type = 'close  evt/source == view] [
					close-view view
				]
				unless view/open? [break]
			]
			unless view/open? [exit]
			wait delay
		]
	]
]
