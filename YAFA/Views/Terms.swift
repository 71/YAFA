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

    @Query(sort: \Term.text) private var terms: [Term]
    @Query(sort: \Tag.name) private var allTags: [Tag]

    @State private var selectedTerms = Set<Term>()

    /// Terms to display in an export sheet. If empty, do not display the export sheet.
    ///
    /// Ideally we would use `selectedTerms` here, but opening a sheet will exit the `editMode`,
    /// which further deselects all terms. As a workaround, when we open the export sheet, we save
    /// the selected terms to this variable.
    @State private var selectedTermsForExportSheet: Set<Term> = .init()

    var body: some View {
        GroupedTerms(
            terms: terms,
            focusedTerm: $focusedTerm,
            searchText: searchText,
            selectedTags: searchTags,
            searchUntagged: searchUntagged,
            selectedTerms: $selectedTerms
        )
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
                    TagsButton(selectedTerms: selectedTerms, tags: allTags)
                        .disabled(selectedTerms.isEmpty)

                    Button("Export") {
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
}

private struct TagsButton: View {
    let selectedTerms: Set<Term>
    let tags: [Tag]

    var body: some View {
        Menu {
            ForEach(tags) { tag in
                let termsWithTag = selectedTerms.count { $0.has(tag: tag) }

                if termsWithTag == 0 {
                    Button(tag.name) {
                        for term in selectedTerms {
                            term.add(tag: tag)
                        }
                    }
                } else {
                    Button(
                        tag.name,
                        systemImage: termsWithTag == selectedTerms.count
                            ? "checkmark" : "circlebadge"
                    ) {
                        for term in selectedTerms {
                            term.remove(tag: tag)
                        }
                    }
                }
            }
        } label: {
            Text("Tags")
        }
        .menuActionDismissBehavior(.disabled)
    }
}

private struct GroupedTerms: View {
    let terms: [Term]
    @Binding var focusedTerm: Term?
    let searchText: String
    let selectedTags: [Tag]
    let searchUntagged: Bool

    @Binding var selectedTerms: Set<Term>

    @State private var groups: [TermGroup] = []
    @State private var termsSearch: SearchDictionary<Term> = .init()

    @State private var editTerm: Term?
    @State private var creatingTerm = false

    /// Whether the unlinked section is folded away. Remembered, since whether unfinished terms are
    /// worth keeping in view is a standing preference rather than a per-visit one.
    @AppStorage("collapsedUnlinked") private var collapsedUnlinked = false

    var body: some View {
        List(selection: $selectedTerms) {
            ForEach(groups) { group in
                Section(header: GroupHeader(group: group, collapsed: $collapsedUnlinked)) {
                    ForEach(visibleTerms(of: group), id: \.id) {
                        term in
                        // Here we would like to use `NavigationLink(value: term)`, but for some
                        // reason this doesn't work when `List(selection:)` is used above. We don't
                        // have any other way of having a selection, so we avoid using
                        // `NavigationLink()`, using `navigationDestination(item:)` instead with a
                        // button and custom array. https://stackoverflow.com/q/78866705
                        Button {
                            editTerm = term
                        } label: {
                            HStack {
                                TermItem(focusedTerm: $focusedTerm, term: term)

                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                            // The row is a button, and its tint colours the text inside its label
                            // -- which turned the subtitle accent-green. Stating the tint here
                            // leaves `foregroundStyle` to do its job.
                            .tint(.primary)
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
                                }
                                .tint(.red)
                            }
                        }
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
        .onChange(of: searchText, initial: true) { old, new in
            if new.isEmpty {
                termsSearch = .init()
            } else if old.isEmpty {
                termsSearch = .init(terms, by: searchKey)
            }

            updateGroups()
        }
        .onChange(of: terms, initial: true) {
            if !searchText.isEmpty {
                // Update the search cache.
                termsSearch = .init(terms, by: searchKey)
            }

            updateGroups()
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
            searchText.isEmpty
            ? AnySequence(terms)
            : AnySequence(termsSearch.including(searchText))

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

        groups = []

        if !unlinkedTerms.isEmpty {
            groups.append(
                .init(
                    dueDate: String(localized: "Unlinked (\(unlinkedTerms.count))"),
                    terms: unlinkedTerms,
                    isCollapsible: true
                )
            )
        }

        if !neverStudiedTerms.isEmpty {
            groups.append(
                .init(
                    dueDate: String(localized: "Never studied (\(neverStudiedTerms.count))"),
                    terms: neverStudiedTerms
                )
            )
        }

        if !dueNowTerms.isEmpty {
            groups.append(.init(dueDate: String(localized: "Due"), terms: dueNowTerms))
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

            groups.append(.init(dueDate: dueDateText, terms: terms))
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
                    Text(group.dueDate)

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
            Text(group.dueDate)
        }
    }
}

private struct TermGroup: Identifiable {
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
        .modelContainer(previewModelContainer())
    }
}
