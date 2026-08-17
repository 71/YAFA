# RFC: Sibling answers during study

Studying a term with more than one outgoing link only reveals the one answer
that link points to, so a correct recall of a sibling reads as a miss. Let the
user see what else it could have been before guessing, and grade whichever one
they actually recalled.

## Background

[Terms, links, and clozes](rfc-terms-links-clozes.md) replaced the front/back
flashcard with a term graph specifically to allow more than one outgoing link
per term -- that's what makes synonyms ("big" and "large" both → "큰") and
homographs ("차" → "tea", "차" → "car") representable without duplicating the
term. Each link is scheduled and studied independently.

That independence is also the new problem. `StudyPrompt` shows one `Link`'s
prompt and, on reveal, that link's `answerText` alone. Given "차", a user may
recall "tea" while the link being prompted actually points to "car". They have
no way to grade themselves correctly: marking it wrong punishes a right answer,
marking it right lies to FSRS about which link was actually recalled.

## Design

Three pieces:

1. A per-link [hint](#hints), for narrowing a guess without giving it away.

1. [Showing siblings before the answer](#revealing-siblings-before-the-answer),
   so the user knows what not to guess.

1. [Grading whichever sibling was actually recalled](#grading-a-sibling-instead),
   so a right answer to the wrong link isn't marked wrong or thrown away.

No single one of these is enough on its own. A hint can't always disambiguate
without giving the game away -- "vehicle" on 차 → car helps too much, "not tea"
helps the _next_ 차 → tea recall instead. Revealing the answer after the fact
doesn't help either, even pointed at the right link for grading: by the time the
user sees "car" they've already been shown "tea" was wrong, priming the next 차
→ tea recall regardless of what the screen says afterwards. So all three are
offered, opt-in, and the user picks how much a review is allowed to give away.

### Siblings

For a link `L`, its **siblings** are every other outgoing link that shares
`L.source`:

```swift
extension Link {
    /// Other links studied from the same source, offered as alternative answers during study.
    ///
    /// Anchored siblings are excluded: their targets answer a different blank in the same
    /// sentence, not this one.
    var siblings: [Link] {
        guard let source else { return [] }

        return source.sortedOutgoingLinks
            .filter { $0.persistentModelID != persistentModelID && !$0.isAnchored }
    }
}
```

### Hints

A single ambiguous link has no sibling to fall back on -- 차 → car is still just
"car" to someone who hasn't yet added 차 → tea. So a link also gets an optional
**hint**: free text shown ahead of the blank, before the answer, for the user to
write themselves.

```swift
@Model
final class Link {
    // ...
    var hint: String = ""
}
```

Set from the link's row in the term view. If the hint is empty, no line is shown
to edit it unless focus is on its text, in which case a "Hints" placeholder is
shown on the below line (like in Reminders). If non-empty, it is always shown
and clickable, on its own line, though with a small font / low-contrast color.
We also allow a hint to be created without focusing the text via a context menu
item which directly opens the "Hints" line and focuses it.

### Revealing siblings before the answer

Pre-reveal, `PromptView` gets a disclosure control -- "Tap to reveal siblings"
collapsed under a caret, matching the existing "Tap to reveal" affordance for
the answer itself.

```swift
if !link.siblings.isEmpty {
    DisclosureGroup("Tap to reveal siblings", isExpanded: $showSiblings) {
        ForEach(link.siblings) { sibling in
            Text(sibling.answerText)
        }
    }
}
```

This stays collapsed by default, so we do not reveal answers which could impact
the next review of a sibling.

### Grading a sibling instead

Once siblings are listed, each row grows its own set of answer buttons (two or
four, following the existing simple/advanced preference), so the user grades
whichever link they actually recalled instead of only the one shown.
`StudyPrompt`'s callback gains the graded link alongside the outcome:

```swift
struct StudyPrompt: View {
    let link: Link
    let onChange: (Link, Review.Outcome) -> Void  // was (Review.Outcome) -> Void
}
```

No new model API: `Progress.addReview(of:outcome:)` already takes any `Link`,
and `StudyView` already threads whatever it's handed through to that link's own
progress -- it just needs to receive whichever link's row was answered instead
of always `link`.

Grading a sibling whose progress isn't due yet still advances it: it was always
possible to review a card ahead of schedule, and FSRS already treats an early
review as a smaller step than a due one rather than as a full interval's worth
of evidence.

## Non-goals

- **No merging siblings' progress.** Grading 차 → car instead of 차 → tea
  doesn't imply the two should share a `Progress` -- that's still the separate,
  explicit "share progress with..." action.

- **No free-text answer checking.** Matching typed input against `answerText`
  and its siblings is a different feature; this RFC only concerns what's shown
  and gradable on a self-graded reveal.
