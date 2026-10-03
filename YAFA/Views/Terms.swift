import SwiftData
import SwiftUI

struct TermsView: View {
    private struct Import: Hashable {}

    @Binding var focusedTerm: Term?

    let searchText: String
    let searchTags: [Tag]
    let searchUntagged: Bool
    /// Leaves the search. In the navigation bar rather than beside the search field, so that it
    /// sits where "Back" does on the screens this one pushes.
    let close: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.editMode) private var editMode

    @Environment(TermStore.self) private var store

    private var allTags: [Tag] { store.tags }

    /// Read from the store rather than a `@Query` of its own: a query over every term refetches on
    /// every keystroke in the editor this screen stays mounted behind. See `TermStore`.
    private var terms: [Term] { store.terms }

    @State private var selectedTerms = Set<Term>()

    /// Terms to display in an export sheet. If empty, do not display the export sheet.
    ///
    /// Ideally we would use `selectedTerms` here, but opening a sheet will exit the `editMode`,
    /// which further deselects all terms. As a workaround, when we open the export sheet, we save
    /// the selected terms to this variable.
    @State private var selectedTermsForExportSheet: Set<Term> = .init()

    /// Whether the tag picker is showing, and which terms it applies to -- snapshotted the same way
    /// `selectedTermsForExportSheet` is, and for the same reason.
    @State private var selectedTermsForTagsSheet: Set<Term>?

    var body: some View {
        GroupedTerms(
            terms: terms,
            version: store.version,
            focusedTerm: $focusedTerm,
            searchText: searchText,
            selectedTags: searchTags,
            searchUntagged: searchUntagged,
            selectedTerms: $selectedTerms
        )
        // The store catches up on its own once edits pause, but coming back from an editor is
        // exactly when a reader looks at the order, so it is brought up to date right then rather
        // than a moment later.
        .onAppear { store.refresh() }
        .toolbar {
            if editMode?.wrappedValue.isEditing != true {
                ToolbarItem(placement: .topBarLeading) {
                    // Tinted like the "Back" button it stands in for: the app tints the whole
                    // stack, which would otherwise make leaving a search look like an action.
                    Button("Close", systemImage: "xmark", action: close)
                        .tint(.primary)
                }
            }

            if editMode?.wrappedValue.isEditing == true {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button("Select all") {
                        selectedTerms.formUnion(terms)
                    }
                    .disabled(selectedTerms.count == terms.count)
                }
            }

            if editMode?.wrappedValue.isEditing == true {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // A plain `Button` presenting a `.sheet` rather than a `Menu`: a `Menu` here --
                    // alongside `EditButton()` and this list's own edit mode -- made the whole
                    // trailing toolbar (and every row's delete control) blink as it presented,
                    // something `Export`'s plain `Button`+`.sheet` never did.
                    //
                    // The presentation itself is attached at the bottom of `body` rather than to
                    // this button: a `.popover` tried here crashed (`UIPreviewTarget requires that
                    // the container view is in a window`) because its anchor -- this `Button` --
                    // sits inside a `ToolbarItemGroup` this `if` can remove out from under it. A
                    // `.sheet` doesn't need a stable anchor the same way, and matches `Export`'s
                    // already-working presentation.
                    Button("Tags") {
                        selectedTermsForTagsSheet = selectedTerms
                    }
                    .disabled(selectedTerms.isEmpty)

                    Button(exportTitle) {
                        selectedTermsForExportSheet = selectedTerms
                    }
                    .disabled(selectedTerms.isEmpty)
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink("Import", value: Import()).navigationDestination(
                        for: Import.self
                    ) { _ in ImportView(initialData: "", selectedTags: searchTags) }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .sheet(isPresented: showExportSheet) {
            ExportSheet(terms: selectedTermsForExportSheet)
        }
        .sheet(isPresented: showTagsSheet) {
            NavigationStack {
                TagsSheet(selectedTerms: selectedTermsForTagsSheet ?? [], tags: allTags)
                    .navigationTitle("Tags")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { selectedTermsForTagsSheet = nil }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
    }

    /// "Export" while nothing is selected yet, "Export (3)" once something is -- selection is shown
    /// per-row too (see ``TermRow``), but the count next to the button people actually tap is what
    /// confirms how many will be exported.
    private var exportTitle: String {
        selectedTerms.isEmpty
            ? String(localized: "Export")
            : String(localized: "Export (\(selectedTerms.count))")
    }

    private var showExportSheet: Binding<Bool> {
        Binding {
            !selectedTermsForExportSheet.isEmpty
        } set: {
            if !$0 {
                selectedTermsForExportSheet = .init()
            }
        }
    }

    private var showTagsSheet: Binding<Bool> {
        Binding {
            selectedTermsForTagsSheet != nil
        } set: {
            if !$0 {
                selectedTermsForTagsSheet = nil
            }
        }
    }
}

/// The tag picker for a batch of selected terms, shown from a `.sheet` rather than a `Menu` -- see
/// the comment where it's presented for why.
private struct TagsSheet: View {
    let selectedTerms: Set<Term>
    let tags: [Tag]

    @Environment(TermStore.self) private var store

    var body: some View {
        List(tags) { tag in
            let termsWithTag = selectedTerms.count { $0.has(tag: tag) }

            Button {
                if termsWithTag == selectedTerms.count {
                    for term in selectedTerms {
                        term.remove(tag: tag)
                    }
                } else {
                    for term in selectedTerms {
                        term.add(tag: tag)
                    }
                }

                // A list filtered by this tag should gain or lose these terms now, not at the next
                // save.
                store.refresh()
            } label: {
                HStack {
                    Text(tag.name)

                    Spacer()

                    if termsWithTag > 0 {
                        Image(
                            systemName: termsWithTag == selectedTerms.count
                                ? "checkmark" : "circlebadge"
                        )
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .tint(.primary)
        }
    }
}

private struct GroupedTerms: View {
    let terms: [Term]

    /// `TermStore.version` as of `terms`. What the regrouping keys on, rather than `terms` itself:
    /// a link added to a term, or a review moving its due date, changes neither which terms there
    /// are nor their order, so comparing the arrays would miss exactly the changes that move a
    /// term between sections.
    let version: Int

    @Binding var focusedTerm: Term?
    let searchText: String
    let selectedTags: [Tag]
    let searchUntagged: Bool

    @Binding var selectedTerms: Set<Term>

    @Environment(\.editMode) private var editMode
    @Environment(TermStore.self) private var store

    @State private var groups: [TermGroup] = []
    @State private var termsSearch: SearchDictionary<Term> = .init()

    /// Whether this list is on screen, as opposed to sitting under an editor pushed from it.
    /// `NavigationStack` sends `onDisappear` to what it covers and `onAppear` when it is uncovered.
    @State private var isVisible = false

    /// Set when `terms` changed while the list was covered, so that the regrouping skipped then is
    /// done once on the way back.
    @State private var groupsAreStale = false

    /// `searchText`, delayed until typing pauses. Grouping walks every matching term's tags, links,
    /// and progress which is too slow to redo on every keystroke against many terms.
    @State private var debouncedSearchText = ""

    @State private var editTerm: Term?
    @State private var creatingTerm = false

    /// Whether the list was empty, with nothing searched for, when it appeared. Sampled once, for
    /// the reason given on `TermEditor.tip`.
    @State private var startedEmpty = false

    /// Whether the unlinked section is folded away. Remembered, since whether unfinished terms are
    /// worth keeping in view is a standing preference rather than a per-visit one.
    @AppStorage("collapsedUnlinked") private var collapsedUnlinked = false

    var body: some View {
        // Not `List(selection: $selectedTerms)`: selection is driven entirely by hand, through
        // `TermRow`'s own tap gesture (see its doc comment for why `List`'s native selection isn't
        // usable here). Handing `List` the binding as well let it reconcile -- and sometimes clear
        // -- our selection on its own schedule, which is what made it empty out from under a menu
        // opening in the toolbar with no code of ours asking for that.
        List {
            // Nothing to group, and nothing typed to explain the emptiness: this is a database with
            // no terms in it rather than a search which found none, so it says what a term is
            // instead of leaving a blank list.
            if startedEmpty && searchText.isEmpty {
                Tip(
                    "A term is a word, a phrase, or a whole sentence. Link one to what it means, and that link is what you study."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .listRowSeparator(.hidden)
            }

            ForEach(groups) { group in
                Section {
                    ForEach(visibleTerms(of: group), id: \.id) { term in
                        TermRow(
                            focusedTerm: $focusedTerm,
                            term: term,
                            isEditing: editMode?.wrappedValue.isEditing == true,
                            isSelected: selectedTerms.contains(term),
                            select: { selectedTerms.insert(term) },
                            deselect: { selectedTerms.remove(term) },
                            open: { editTerm = term }
                        )
                        .id(term)
                        // Rows slide out from under the header as the section folds, rather than
                        // the list simply reflowing without them.
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    .onDelete { offsets in
                        for offset in offsets {
                            let term = group.terms[offset]

                            term.delete()
                        }

                        // The groups come from the store, which only refreshes on its own when
                        // the context saves; until then the row would come straight back.
                        store.refresh()
                    }
                } header: {
                    GroupHeader(group: group, collapsed: $collapsedUnlinked)
                } footer: {
                    if group.isCollapsible && !collapsedUnlinked {
                        // Only "Unlinked" is collapsible.
                        Text(
                            "These terms link to nothing, so there is nothing to study from them. Add a link or blank to start studying them."
                        )
                    }
                }
            }
            .animation(.snappy(duration: 0.25), value: collapsedUnlinked)

            if !searchText.isEmpty {
                // Since the "+" button may not be obvious, suggest creating a new term at the end
                // of the list.
                VStack {
                    Text("Didn't find what you're looking for?")

                    // Ideally this would be a `NavigationLink()`, but then it would have a
                    // list-like style we don't want and can't seem to remove. So instead this is a
                    // button which sets `creatingTerm`, which is picked up by a
                    // `navigationDestination()`.
                    Button("Create term") {
                        creatingTerm = true
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .navigationDestination(item: $editTerm) { term in
            TermEditor(term: term, autoFocus: false)
        }
        .navigationDestination(isPresented: $creatingTerm) {
            NewTermEditor(text: searchText, tags: selectedTags)
        }
        .scrollDismissesKeyboard(.interactively)
        // Only while a term row is being edited: the search field holds the keyboard the rest of
        // the time, and it has a close button of its own.
        .dismissKeyboardToolbar(enabled: focusedTerm != nil)
        // Recomputing the list below is too slow to redo on every keystroke, so we do debounce.
        .task(id: searchText) {
            guard !searchText.isEmpty else {
                debouncedSearchText = ""
                return
            }

            do {
                try await Task.sleep(for: .milliseconds(200))
                debouncedSearchText = searchText
            } catch {
                // Cancelled by a newer keystroke; that one's task will set it instead.
            }
        }
        .onChange(of: debouncedSearchText, initial: true) { old, new in
            if new.isEmpty {
                termsSearch = .init()
            } else if old.isEmpty {
                termsSearch = .init(terms, by: searchKey)
            }

            updateGroups()
        }
        // The store refreshes only on a save or when a screen asks it to (this list does on
        // appear), so this is rare enough that the search index is simply rebuilt whenever it
        // fires. Keyed on the version, not the array; see `version`.
        .onChange(of: version) {
            if !debouncedSearchText.isEmpty {
                termsSearch = .init(terms, by: searchKey)
            }

            // Not while an editor is pushed over this list, as computing groups can be quite slow
            // with many terms (>200ms for 1700 terms).
            if isVisible {
                updateGroups()
            } else {
                groupsAreStale = true
            }

            // A selected term can leave `terms` without ever passing through `deselect` -- deleted
            // by its own swipe action, say, rather than by the "Export"/"Tags" buttons that read
            // this selection -- so it's pruned here instead of trusting every way out to keep it in
            // sync. Otherwise the count next to "Export" (and what it would actually export) stays
            // stale, counting a term that's already gone.
            //
            // Matched by `persistentModelID` rather than by `Term`'s own equality: this fires on
            // every fetch, including ones that hand back the same rows as different `Term`
            // instances (a CloudKit merge, say), and comparing by identity there would drop a
            // selection that never actually lost anything.
            if !selectedTerms.isEmpty {
                let stillPresentIds = Set(terms.map(\.persistentModelID))

                selectedTerms = selectedTerms.filter { stillPresentIds.contains($0.persistentModelID) }
            }
        }
        // After the first `updateGroups()`, so it reads the groups rather than racing them. Terms
        // arriving later -- a CloudKit sync landing while this is open -- clear it: the tip
        // explains an empty list, and it is not one any more.
        .onAppear {
            startedEmpty = terms.isEmpty
            isVisible = true

            if groupsAreStale {
                updateGroups()
            }
        }
        .onDisappear { isVisible = false }
        .onChange(of: terms.isEmpty) { _, isEmpty in
            if !isEmpty { startedEmpty = false }
        }
        .onChange(of: selectedTags) {
            updateGroups()
        }
        .onChange(of: searchUntagged) {
            updateGroups()
        }
    }

    /// The terms a group shows, which is none of them while it is collapsed.
    private func visibleTerms(of group: TermGroup) -> [Term] {
        group.isCollapsible && collapsedUnlinked ? [] : group.terms
    }

    /// Terms are searchable by their own text *and* by what they are linked to, so that typing a
    /// definition still finds the word it defines, as it did when both lived on one flashcard.
    private func searchKey(_ term: Term) -> String {
        ([term.text] + (term.outgoingLinks ?? []).compactMap { $0.target?.text })
            .joined(separator: " ")
    }

    private func updateGroups() {
        var unlinkedTerms = [Term]()
        var neverStudiedTerms = [Term]()
        var dueNowTerms = [Term]()
        var termsByDueOffset: [Int: [Term]] = [:]

        let calendar = Calendar.autoupdatingCurrent
        let now = Date.now
        let today = calendar.startOfDay(for: now)

        let filteredTerms =
            debouncedSearchText.isEmpty
            ? AnySequence(terms)
            : AnySequence(termsSearch.including(debouncedSearchText))

        for term in filteredTerms {
            if searchUntagged {
                guard term.tags?.isEmpty ?? true == true else { continue }
            } else {
                guard selectedTags.allSatisfy({ term.has(tag: $0) }) else { continue }
            }

            // A term connected to nothing is unfinished work rather than something to study, so it
            // goes to its own section at the top instead of into a due group.
            if term.isUnlinked {
                unlinkedTerms.append(term)
                continue
            }

            // A term which is only ever a target -- a definition -- has nothing studied from it,
            // and is already shown as the answer of the row which links to it.
            guard term.isStudied else { continue }

            let links = term.studiedLinks

            // A term is grouped by the soonest thing studied from it, since that is when it will
            // next come up.
            guard
                let soonest = links.compactMap({ $0.progress }).min(by: {
                    $0.nextReviewDate < $1.nextReviewDate
                })
            else {
                neverStudiedTerms.append(term)
                continue
            }

            if links.allSatisfy({ $0.progress?.reviews?.isEmpty != false }) {
                neverStudiedTerms.append(term)
                continue
            }

            // Anything already due goes in its own group ahead of the rest of today: a term which
            // can be studied now is a different proposition from one which merely comes up before
            // midnight, and lumping them together hides how much there is to do.
            guard soonest.nextReviewDate > now else {
                dueNowTerms.append(term)
                continue
            }

            let termDate = calendar.startOfDay(for: soonest.nextReviewDate)
            let daysBetweenTodayAndDue = calendar.dateComponents(
                [.day],
                from: today,
                to: termDate
            ).day!
            let offset = max(daysBetweenTodayAndDue, 0)

            termsByDueOffset[offset, default: []].append(term)
        }

        var newGroups: [TermGroup] = []

        if !unlinkedTerms.isEmpty {
            newGroups.append(
                .init(
                    dueDate: String(localized: "Unlinked"),
                    terms: unlinkedTerms,
                    isCollapsible: true
                )
            )
        }

        if !neverStudiedTerms.isEmpty {
            newGroups.append(
                .init(
                    dueDate: String(localized: "Never studied"),
                    terms: neverStudiedTerms
                )
            )
        }

        if !dueNowTerms.isEmpty {
            newGroups.append(.init(dueDate: String(localized: "Due"), terms: dueNowTerms))
        }

        for (daysBetweenTodayAndDue, terms) in termsByDueOffset.sorted(by: { $0.key < $1.key }) {
            let dueDateText =
                if daysBetweenTodayAndDue == 0 {
                    String(localized: "Due later today")
                } else if daysBetweenTodayAndDue == 1 {
                    String(localized: "Due tomorrow")
                } else {
                    String(localized: "Due in \(daysBetweenTodayAndDue) days")
                }

            newGroups.append(.init(dueDate: dueDateText, terms: terms))
        }

        // Built aside and assigned once, and only when it differs, to avoid redraws.
        if newGroups != groups {
            groups = newGroups
        }
    }
}

/// One row of the term list: always the same editable `TermItem`, with a leading selection
/// checkmark that only appears while editing and a tap that means "select" instead of "open" for as
/// long as it's showing.
///
/// The row used to switch to an entirely different, read-only view while selecting, which is what
/// caused the flicker entering and leaving edit mode -- SwiftUI has to tear down and rebuild the row
/// rather than simply restyle it. Keeping one view means the checkmark fades in and out instead.
///
/// `TermItem` embeds a `TextEditor` (via `TermTextField`), which would otherwise take a tap as a
/// request to focus and edit rather than as a row selection -- so it's disabled while editing, which
/// both stops that and frees the tap to reach this row's own gesture underneath.
private struct TermRow: View {
    @Binding var focusedTerm: Term?
    let term: Term
    let isEditing: Bool
    let isSelected: Bool
    let select: () -> Void
    let deselect: () -> Void
    let open: () -> Void

    @Environment(TermStore.self) private var store

    var body: some View {
        // `spacing: 0` and the checkmark's own trailing padding (rather than the `HStack`'s default
        // inter-item spacing) so that collapsing the checkmark to zero width when not editing also
        // collapses the gap around it -- an `HStack` still reserves its spacing on both sides of a
        // zero-width child, which is what pushed every row's content over even outside edit mode.
        HStack(spacing: 0) {
            // Always laid out, so the row's width doesn't jump when the checkmark appears -- only
            // its opacity animates.
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                .imageScale(.large)
                .opacity(isEditing ? 1 : 0)
                .frame(width: isEditing ? nil : 0)
                .padding(.trailing, isEditing ? 8 : 0)
                .clipped()

            TermItem(focusedTerm: $focusedTerm, term: term)
                .disabled(isEditing)

            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
                .opacity(isEditing ? 0 : 1)
                .padding(.leading, isEditing ? 0 : 8)
        }
        // The row is a button elsewhere in the app, and its tint colours the text inside its label
        // -- which turned the subtitle accent-green. Stating the tint here leaves `foregroundStyle`
        // to do its job regardless of how the row is driven.
        .tint(.primary)
        .contentShape(Rectangle())
        // Here we would like to use `NavigationLink(value: term)`, but for some reason this doesn't
        // work when `List(selection:)` is used on the list above. We don't have any other way of
        // having a selection, so we avoid using `NavigationLink()`, using `navigationDestination(item:)`
        // instead with a plain array, driven from this tap gesture. https://stackoverflow.com/q/78866705
        //
        // That workaround is also why edit mode's own selection UI -- the leading checkmark
        // `List(selection:)` would otherwise draw -- never appears: this isn't one of the row kinds
        // `List` knows how to decorate. So selection is drawn and toggled by hand instead.
        .onTapGesture {
            if isEditing {
                isSelected ? deselect() : select()
            } else {
                open()
            }
        }
        .contextMenu {
            let now = Date.now
            let dueLater = term.studiedLinks.filter { $0.isDoneForNow(now: now) }

            if !dueLater.isEmpty {
                Button("Study now", systemImage: "timer") {
                    for link in dueLater {
                        link.progress?.reschedule(to: now)
                    }
                }
                .tint(.primary)
            }

            Button("Delete term", systemImage: "trash", role: .destructive) {
                term.delete()
                // As for the swipe: the list would keep showing the term until the next save.
                store.refresh()
            }
            .tint(.red)
        }
    }
}

/// A section header, with a disclosure control on the section which can be folded away.
private struct GroupHeader: View {
    let group: TermGroup
    @Binding var collapsed: Bool

    var body: some View {
        if group.isCollapsible {
            Button {
                collapsed.toggle()
            } label: {
                HStack {
                    Text("\(group.dueDate) (\(group.terms.count))")

                    Spacer()

                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(collapsed ? 0 : 90))
                        .font(.caption.weight(.semibold))
                        // The same animation the rows use, so the chevron turns as they slide
                        // rather than on a timing of its own.
                        .animation(.snappy(duration: 0.25), value: collapsed)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        } else {
            Text("\(group.dueDate) (\(group.terms.count))")
        }
    }
}

private struct TermGroup: Identifiable, Equatable {
    let dueDate: String
    var terms: [Term]
    /// Whether the section can be folded away. Only the unlinked section is: it sits at the top so
    /// that unfinished terms are easy to find, which shouldn't mean pushing the due lists down.
    var isCollapsible: Bool = false

    var id: String { dueDate }
}

#Preview {
    // Use a `NavigationStack` to display the top bar.
    NavigationStack {
        TermsView(
            focusedTerm: .constant(nil),
            searchText: "",
            searchTags: [],
            searchUntagged: false,
            close: {}
        )
        .appModelContainer(previewModelContainer())
    }
}
