# TODO

- Show a count of cards next to every section in "Terms", not just "Unlinked".

- Show an explanation of what "unlinked" cards are as a footer of the "Unlinked"
  section.

- Modify the onboarding sheet wrt new changes.

- Review the new UI to see how it could be made more user-friendly (ideally
  using progressive disclosure, not with a big tutorial); the app is quite
  different from existing flashcard apps now.

- Review the tag list UI. Probably bring up a sheet from the bottom, and tapping
  a tag closes the sheet and opens the terms view focused on that tag.

- **Truncation in the term list is invisible.** A term's row caps its height at
  three lines, but the field it caps is a `TextEditor` -- the only editable
  control which can tint an anchored span -- and a `TextEditor` scrolls rather
  than truncating, so there is no ellipsis and nothing else to say the text
  continues. The row still opens the term, where the whole text is, so nothing
  is unreachable. Fixing it means either showing a `Text` while the row is
  unfocused and swapping in the editor when it is, or drawing the cut ourselves.
