# TODO

- **Truncation in the term list is invisible.** A term's row caps its height at
  three lines, but the field it caps is a `TextEditor` -- the only editable
  control which can tint an anchored span -- and a `TextEditor` scrolls rather
  than truncating, so there is no ellipsis and nothing else to say the text
  continues. The row still opens the term, where the whole text is, so nothing
  is unreachable. Fixing it means either showing a `Text` while the row is
  unfocused and swapping in the editor when it is, or drawing the cut ourselves.
