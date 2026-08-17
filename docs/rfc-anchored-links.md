# RFC: Anchored links

Replace `Cloze` and `ClozeBlank` with a range on `Link`, so that a cloze
deletion is an ordinary link which happens to record where its target sits in
the source term's text. Everything is a term; some links are anchored into the
text they are studied from.

## Background

[Terms, links, and clozes](rfc-terms-links-clozes.md) split flashcards into
terms, links, and clozes in order to support synonyms, homographs, and cloze
deletion, leaving `Cloze` and `ClozeBlank` authoring out of scope.

While designing that flow, I realized I wanted a different approach where terms
and clozes are the same thing: a cloze is not a kind of card, but a term whose
text is made of other terms. "고양이가 학교에 갔다" refers to 고양이, 학교 and
가다, each of which is a term already in the graph, and blanking one is a way of
studying it _from_ the sentence.

That opens a flow the current model has no room for: a user adds a term and its
definition, then links the words used in that definition to terms already in the
database. A definition stops being one card and becomes a way of reaching every
term it mentions, so adding one makes the graph denser rather than just larger.

## Design

### Anchored links

`Link` gains a range into its source's text, and `Cloze` and `ClozeBlank` are
deleted.

```swift
@Model
final class Link {
    var source: Term?
    var target: Term?
    var progress: Progress?

    /// Where `target` appears in `source.text`, as a flat list of alternating lower/upper UTF-16
    /// offsets. Empty for an ordinary link, which is studied by showing the whole text.
    private(set) var ranges: [Int] = []

    // Plus helpers to map `ranges` to/from `String.Index`.
}
```

In most cases, there is no range or one range; a list allows a word appearing
twice in a sentence to be blanked in both places at once.

An **anchored** link is one with a non-empty `ranges`, and studying it shows
`source.text` with those ranges replaced by a placeholder. An **unanchored**
link shows `source.text` whole.

Ranges and the target's text are allowed to disagree, so that "갔다" may point
to the term "가다".

### Mixed anchoring

A term's links need not agree. When some are anchored and some are not, each
link renders itself: anchored ones hide their own range, unanchored ones show
the whole text.

```
Term "고양이가 학교에 갔다"
  → 학교                       anchored [5..7]
  → "the cat went to school"  unanchored

studying the first:   고양이가 (...)에 갔다  → recall 학교
studying the second:  고양이가 학교에 갔다    → recall "the cat went to school"
```

An anchored link hides **only its own** ranges, leaving every other anchor
filled in, so two anchors on one sentence are two independent questions rather
than one card with two holes. There is no "hide everything at once" mode.

If the mix reads ambiguously in practice, the refinement is to mark anchored
spans in an unanchored link's prompt -- underlined rather than hidden -- rather
than to restrict the model.

### Marking an anchor

The user selects a range of the term's text and taps **Blank**, offered in the
selection's edit menu and in the keyboard toolbar:

```
Term
  고양이가 학교에 [갔다]
  ┌────────────────────────┐
  │ Cut  Copy  Blank  ...  │
  └────────────────────────┘
```

We use selections rather than Anki-style `{{c1::학교}}` to avoid teaching /
parsing a new syntax, and to allow terms to be selected from the existing
database.

The selection is read the way the tag field already reads it:
`TextField(text:selection:)` bound to a `TextSelection`, whose `indices` give
either a `.selection(Range)` or a `.multiSelection(RangeSet)`. Only the first
range of a multi-selection is blanked. We must however be careful about
`String.Index`, UTF-8, UTF-16, as usual when dealing with offsets into Swift
strings. The selection does not change while a CJK character is being composed
(ㅎ → 하), so text changes have to be observed alongside selection changes.

Tapping **Blank** does not decide the target on its own, it instead behaves like
"Add link", but creating a link which is anchored (and seeded with the selected
text). Like "Add link", this allows an existing term to be reused by picking it,
or a new term to be created by submitting without picking.

Seeding rather than committing the selection is what makes the conjugated case
work. Blanking 갔다 seeds the field with "갔다", which matches no term; typing
back to 가다 finds it, and picking it anchors the range over 갔다 while pointing
the link at 가다. Blanking 학교, which is already a term, is the same flow with
the first suggestion picked.

Because the target is a term like any other, an anchored link's row in the
"Links" section is the same row an ordinary link gets, with the target's text
editable in place as it already is.

A selection overlapping an existing anchor -- even partially -- does not offer
**Blank**.

### Editing an anchored term

Ranges are offsets into text the user can edit, so they are maintained as it
changes. SwiftUI reports the text after the fact, in `.onChange(of: text)`, so
the edit is recovered by comparing the old text with the new: the common prefix
and the common suffix bound the replaced range, and the length difference is the
delta. That is exact for a single contiguous edit, which is what typing,
pasting, and deleting a selection all produce. Each range is then adjusted by
position:

```
         ┌── anchor at 5..7
  고양이가 학교에 갔다
  ▲
  └── insert "작은 " (3 UTF-16 units)

  작은 고양이가 학교에 갔다
             └── anchor at 8..10
```

- Entirely before the edit: unchanged.
- Entirely after: both offsets shift by `delta`.
- Containing or overlapping the edit: clipped to what the edit left behind.

Clipping keeps the anchor over whatever survived rather than giving up on it. An
edit inside an anchored word is the common case -- fixing a typo, or conjugating
the same verb differently -- and the range should follow it:

```
고양이가 학교에 갔다     anchor 8..10 over 갔다, pointing at 가다
replace 9..10 with "어요"
고양이가 학교에 갔어요   anchor 8..11 over 갔어요, still pointing at 가다
```

The target does not move: 갔다 and 갔어요 are the same verb, so the link is as
correct after the edit as before it.

A range only unanchors when clipping leaves it empty, which means the anchored
text was deleted outright and there is nothing left to point at. The link
survives that too, along with its progress and its review history; it becomes an
ordinary link to the same term, and can be anchored again by selecting the new
text. Nothing is destroyed, so even the worst edit can be corrected.

Clipping can leave the anchor over text nobody would have chosen -- rewriting a
sentence around a blank can leave it covering half a word. That is why it is
only a default, and why unanchoring is also available on demand, from the link
row's context menu alongside the actions already there. The recovery from a bad
automatic re-anchor is to unanchor and select again, and both halves of that
have to be reachable without deleting the link.

If this strategy is too naive due to complex edits / full text replacements,
that's okay: anchors will be lost, but links (and their progress) are kept.

### Rendering

The term's text field marks each anchor with a tinted background over its range,
so the text stays readable while showing what has been taken out of it, using an
`AttributedString`, recomputed when the ranges change.

Anchors are ordered by position for the "Links" section, and we do not try to
accommodate for sentences whose anchored links would overflow the screen.

In "Links", link rows quote (with aggressive clipping) their text in the term,
with the same background tint to make it obvious that this corresponds to the
term substring for the (common) case where the anchor text and the target term's
text are the same. This quote appears before the arrow which indicates the
direction of the link.

Focusing a row highlights its anchors in the text above, more strongly than the
resting tint the other anchors keep. Similarly, when the user's selection
overlaps an anchor, the anchor will be tinted more strongly, and its
corresponding link will be highlighted. If a selection spans multiple anchors,
no highlighting takes place.

Tints are arbitrary; we keep a static list of 6 colors, and cycle through them
in order. Alternatively we could pick a color based on the term's ID, which
would allow terms to always be represented with the same color, but the downside
would be that colors would likely be reused within the same term's blanks.

### The rest of the app

Most of it does not change, which is the point.

The term list gains nothing structural, but anchored terms are long, so rows cap
their height and truncate, in the way Reminders lets an item grow to a few lines
before cutting it off. This is work that long-form terms already needed -- a
definition typed into a term today has the same problem.

### Schema

`Cloze` and `ClozeBlank` are registered in `SchemaV2`, so they exist on disk as
tables. However, no shipped build can create a cloze, so both tables are empty
on every real device.

So there is nothing to convert, and no custom migration stage to write. That is
within what SwiftData infers, so no `SchemaV3` is needed:

```
CoreData: annotation: Migration: CloudKit tables detected. Adding migration statements for removed table: ZCLOZEBLANK
CoreData: annotation: Migration: CloudKit tables detected. Adding migration statements for removed table: ZCLOZE
```

All references to `Cloze` and `ClozeBlank` can be removed, simplifying things.

### Simplification

In [Terms, links, and clozes](rfc-terms-links-clozes.md), we added `Studiable`
to represent a link or cloze blank. It can now be removed, relying on `Link`
instead. Related helpers can be removed if now trivial, or change
`any Studiable` to `Link`.

## Non-goals

- **Anchors spanning terms.** A range points at one target. A sentence where two
  adjacent words are one idiom is either one target or two ranges, not a nested
  structure.

- **Anchoring without being asked.** Nothing scans a definition and links the
  terms it finds. Every anchor is one the user selected and every target one
  they picked, as [the previous RFC](rfc-terms-links-clozes.md) established.
  Proposing anchors is a different thing from creating them, and is
  [future work](#future-work).

- **An import/export format expressing anchors.** Both formats stay as they are
  for now, and the anchor is dropped on export, so a round trip loses data.
  Fixing this is [future work](#future-work).

## Future work

**LLM-assisted anchoring.** The one step of marking an anchor that is not
mechanical is going from the form in the sentence to the term it belongs to.
Blanking 갔다 seeds the search with "갔다", which matches nothing, and the user
has to know that the term is 가다 and type it. A model asked for the dictionary
form of a selection would offer 가다 as a suggestion alongside the text matches,
turning that step back into picking.

The same model can propose the anchors themselves: given a term's text, which
spans are worth blanking and which term each belongs to.

Both stay suggestions, shown as a proposed anchor the user accepts or dismisses,
never applied on their own, and requiring interaction to bring up. That is what
keeps the non-goal above intact: the model narrows what the user picks from, and
picking is still what creates a link.

**A richer import/export format.** JSON is already a per-link object carrying
`created`, `nextReview`, `tags` and the full `reviews` history. It could be
extended to also support terms (incl. anchored links), allowing the full graph
to be exported (and then imported).

The CSV format could theoretically be extended as well; it would be incompatible
with most flashcards formats, but there may still be value in exporting all
terms as CSV, using IDs to link them together. The real value is in JSON,
though.

## Rejected alternative: an editor for `Cloze`

The obvious move was to keep `Cloze` and `ClozeBlank` as designed and write the
editor the previous RFC deferred: a sentence with blanks, authored on a screen
of its own or reached by converting a term into one. But a cloze being separate
from terms means every part of the app has to know which kind it is holding.

Thinking of clozes purely as clozes, it makes sense to separate them from terms
from a display and storage perspective. But by, uhm, being a bit liberal with
our definition of "term", we can instead fit clozes into them, simplifying the
model, and allowing definitions to serve as both terms and clozes.

What the separate model does buy is strictness: `Cloze` and `Term` differ, and
holding them apart in the type system means the differences must be handled
rather than assumed away. That is worth something, and it is why this was not an
easy call. But I thought the "definition as term+close" thing was useful enough
to go into that direction.
