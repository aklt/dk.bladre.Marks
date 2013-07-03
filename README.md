# db.bladre.Marks -- Add marks to locations in Renoise

The Marks tool makes it possible to use letters as markers of different
positions in the renoise GUI. Positions remembered include:

* Pattern, track, line and note column
* Selected instrument
* Top, Middle and bottom panel view

Marks are saved in the "________Marks________" instrument and will be saved
together with the song so they are restored when the song is reopened at a
later time.

To use it map "Global:Tools:Marks" to "Numpad -".  Repeatedly pressing
"Numpad -" again toggles dialog minify/maximize.

Press "ESC" to close the dialog.

When the dialog has focus:

  Use Shift-<Letter> to ad a mark and press <Letter> to jump to the mark

The granularity of a jump can be changed in the dialog

  view:    Change just the view of the currently playing pattern
  pattern: Change to pattern where mark is, but not cursor position.  Useful
           for experimenting with mixes.
  cursor:  Also move cursor when jumping.
