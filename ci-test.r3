Rebol [
	Title: "Rebol/Pugl extension test"
	Note:  "Needs a display (on Linux an X server, e.g. xvfb-run)"
]

pugl: import 'pugl
? pugl

;; open / accessors
v: open-view/title/hidden 320x200 "Test"
assert [block? poll-events]
assert [handle? v]
assert [v/open?]
assert [integer? v/id]
assert [v/title = "Test"]
assert [v/size = 320x200]
assert [decimal? v/scale]

;; setters
v/title: "Renamed"
assert [v/title = "Renamed"]

;; events
assert [block? poll-events]
assert [block? poll-events]  ;; nothing queued is still a block

;; show / hide
assert [show-view v]
assert [hide-view v]

;; close
assert [close-view v]
assert [not v/open?]
assert [none? v/size]
assert [none? v/title]
assert [close-view v]        ;; closing twice is fine
assert [error? try [show-view v]]
assert [error? try [v/title: "x"]]

;; bad arguments
assert [error? try [open-view 0x10]]
assert [error? try [open-view 20000x10]]

print "Pugl tests passed"
