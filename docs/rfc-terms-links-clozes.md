# RFC: Terms, links, and clozes

Replace YAFA's flashcard model -- a front/back pair with per-tag study direction
-- with a graph of terms connected by directed links, so the same piece of
knowledge can have synonyms, homographs, and cloze-sentence prompts without
duplicating it.

## Background

Today a `Flashcard` is a `front`/`back` string pair with one `FSRSCard` and one
review history, scheduled by
[`FSRS`](https://github.com/open-spaced-repetition/fsrs4anki). Study direction
(front → back, back → front, or both) is set per `FlashcardTag` and inherited by
every card carrying that tag -- a card with two tags that disagree on direction
studies both.

This has three limits I want to remove:

- **No synonyms.** "Big" and "large" both meaning "큰" requires two separate
  cards, each with its own independent FSRS progress, even though recalling one
  is evidence about the other.
- **No homographs.** "차" can mean "tea" or "car"; today that's either two cards
  with identical fronts (confusing in the card list) or one card that picks a
  single back, losing information.
- **No cloze deletions.** There's no way to ask "고양이가 (학교)에 갔다" because
  a card is always two flat strings, not a template.

The last point is the most important one: I want to add cloze deletion, but this
is not very compatible with the current data model. I further want progress to
be tracked for a single term even if it appears in multiple cloze sentences,
hence the need for a graph model.

## Terminology

- **Term** -- a piece of textual knowledge: a word, phrase, or definition.
  Replaces `Flashcard` as the atomic unit. A term has no direction and no
  front/back; those are properties of links.

- **Link** -- a directed edge from one term to another. "Directed" means the
  prompt/answer roles are fixed: link A → B is studied by showing A and grading
  recall of B. The reverse direction is a different link (which may share the
  same progress, see [Progress](#progress)).

- **Cloze** -- a sentence template with one or more numbered blanks. Each blank
  is a **cloze blank**: a term shown as the answer when that blank is hidden.
  Studying blank _n_ shows the sentence with blank _n_ hidden and the rest
  filled in. A cloze is not a link -- there's no "source" term prompting it, the
  sentence itself is the prompt -- but each of its blanks is independently
  studyable and tracks its own progress, same as a link does.

- **Progress** -- the FSRS state and review history something is scheduled
  against. Both links and cloze blanks have one; each gets its own by default,
  but two or more can share one, so that reviewing any of them advances
  scheduling for all of them (e.g. EN→KO and KO→EN for the same term).

## Design

### Term

```swift
struct Term {
    var text: String
    var notes: String
    var tags: [Tag]
}
```

A term is just text plus metadata -- no `front`/`back`, no FSRS state, no review
history. Tags are per-term, rather than per-link. Progress is moved to
[links](#link) and [cloze blanks](#cloze).

### Link

```swift
struct Link {
    var source: Term
    var target: Term
    var progress: Progress
}
```

A link is a directed edge from term to term: study `source`, grade recall of
`target`. Scheduling lives on the `progress` it points to, not on the link
itself, so that two links can share one (see [Progress](#progress) below). By
default every link gets its own progress.

Synonyms and homographs are naturally represented: "차" has two outgoing links,
one to "tea" and one to "car", each independently schedulable.

### Cloze

```swift
struct Cloze {
    var template: String  // e.g. "He went to the bank yesterday."
    var blanks: [ClozeBlank]
}

struct ClozeBlank {
    var term: Term
    var ranges: [Range<String.Index>]  // Where `term` appears in `template`.
    var progress: Progress
}
```

`template` holds the full sentence as ordinary text, without placeholders. Each
blank points at the range(s) of `template` it covers instead of owning a
separate rendered string. This means the sentence is always readable as-is
(useful for authoring and for search), and blanks cannot differ from the term
they point to (e.g capitalization).

Studying blank _n_ renders `template` with blank _n_'s range(s) replaced by a
reveal prompt and everything else shown as-is.

### Progress

```swift
struct Progress {
    var fsrsCard: Card
    var reviews: [Review]
}

struct Review {
    enum Studied {
        case link(Link)
        case clozeBlank(ClozeBlank)
    }

    var studied: Studied  // What was actually shown for this review.
    var date: Date
    var outcome: Outcome  // ok, fail, easy, hard -- unchanged from today.
}
```

A progress holds one `FSRSCard` and one review history, same shape as today's
per-`Flashcard` state, just detached from any single link or cloze blank. Both
get their own progress at creation time; pointing two of them at the same
progress is an explicit action ("share progress with...", offered from a link's
or cloze blank's context menu, which displays existing sets of links which can
then be joined).

Each `Review` records `studied`, not just which `Progress` it belongs to,
because once a progress is shared, the reviews inside it can come from different
links or cloze blanks.

There is no standalone screen for progress -- progress is reachable only from
the links and cloze blanks that use it, deliberately less prominently than tags
or terms.

### Scheduling and study direction

A link or cloze blank is due when its progress' `fsrsCard` due date has passed,
exactly as today, except the check runs per link/blank instead of per flashcard.
"Study direction" as a standalone setting disappears. Wanting to study both
EN→KO and KO→EN for a term means having both links, optionally sharing progress
as above; wanting only EN→KO means creating only that link. This is a strict
generalization of today's per-tag toggle: the three `StudyMode` cases (front,
back, both) correspond to (only the reverse link exists, only the forward link
exists, both exist), but now decidable per term instead of forced to agree
across every card under a tag -- the `studyMode` enum and its per-tag
inheritance logic go away entirely.

When a due progress has more than one sharer (link or cloze blank), the one
shown is whichever hasn't been studied the longest: look at
`progress.reviews.last?.studied` for each sharer and pick the one with the
oldest (or missing) last review. This needs no new stored field is
deterministic, so two sharers alternate exactly rather than merely tending to;
picking randomly, even weighted by staleness, would let the same sharer come up
twice in a row.

### UI

The current [Flashcard detail view](Screenshots/flashcard.png) shows one Content
section (front text field, then back text field) plus Tags / Notes /
Information. It becomes a **Term view**: one term's text at the top, followed by
a list of its outgoing links -- each rendered as a row with the target's text
and its own due date, tappable to open that target's own Term view. A term with
exactly one link (the common case, and every migrated card) looks identical to
today's screen minus the second text field, which moves into the link list as a
single row. Adding a synonym or a second direction is adding another row to that
list, not a new screen.

The study prompt, [due-list](Screenshots/flashcards.png), and
[tag summary](Screenshots/tags.png) views are unaffected in spirit --
"flashcard" becomes "recall", "review", or "term" depending on what's actually
being counted (e.g. "6 recalls due").

### Schema versioning

`appModelContainer()` currently builds a bare `Schema` with no `VersionedSchema`
and no `SchemaMigrationPlan`. This change deletes `Flashcard` and
`FlashcardTag.studyMode`, so we need a stronger migration strategy. This is a
good opportunity to introduce versioned schemas.

Concretely:

```swift
enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Flashcard.self, FlashcardReview.self, FlashcardTag.self]
    }
}

enum SchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Term.self, Link.self, Cloze.self, ClozeBlank.self, Progress.self, Tag.self]
    }
}

enum YAFAMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self] }
    static var stages: [MigrationStage] { [migrateV1toV2] }

    static let migrateV1toV2 = MigrationStage.custom(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self,
        willMigrate: nil,
        didMigrate: { context in
            // See below.
        }
    )
}
```

`SchemaV1` is a **retroactive** snapshot of the current model, added in the same
change that introduces versioning -- it doesn't change today's on-disk format,
it just gives SwiftData a named, versioned description of what's already there
to migrate _from_. `ModelContainer` then takes
`migrationPlan: YAFAMigrationPlan.self` alongside the existing `config`.

### Migration

Each existing `Flashcard` becomes two terms (`front`, `back`) and one or two
links depending on its resolved `studyMode`:

| old `studyMode`        | links created |
| ---------------------- | ------------- |
| `recallBack` (default) | front → back  |
| `recallFront`          | back → front  |
| `recallBothSides`      | both          |

Sharing one progress for `recallBothSides` preserves today's actual behavior --
one FSRS card, one review history, randomly-chosen direction per review
([StudyPrompt.swift:100-110](YAFA/Views/StudyPrompt.swift#L100-L110)) -- rather
than splitting it into two newly-independent progresses, which would silently
change every existing card's scheduling on upgrade. The existing
`FlashcardReview` history and `fsrsCard` carry over unchanged onto the resulting
progress, shared by both links.

## Non-goals

- No cloze _editor_ UX (blank insertion, template authoring) or extended
  import/export format -- see [Future work](#future-work).

- No inferrence for synonyms or homograps; it is all driven by the user.

## Future work

- **Cloze editor.** This RFC fixes the data model -- `template` as plain text,
  blanks as ranges into it -- but not the authoring UX: how a user marks a span
  of text as a blank, links it to a term, or edits a template without breaking
  existing blanks' ranges.

- **Export/import format for the new structure.** The current two-column
  CSV/JSON is kept, using links and terms to represent flashcards; it has no way
  to express a term with multiple outgoing links (synonyms, both directions) or
  a cloze.
