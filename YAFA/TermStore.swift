import CoreData  // For `NSManagedObjectContextObjectsDidChange`.
import SwiftData
import SwiftUI

/// Every term (and tag) in the store.
///
/// There is one `TermStore` per `ModelContainer`, obtained via `@Environment(TermStore.self)`. Use
/// it whenever you need access to all terms and tags and cannot efficiently filter them via
/// `@Query`, e.g. when searching by text.
///
/// This exists to solve the following problem: a `@Query` over e.g. all terms will refetch the
/// whole table whenever any object changes in memory. As such, editing a term or tag will refresh
/// each `@Query` in the current navigation stack on every keystroke, making the app very sluggish.
///
/// This fetches once, and again only after the store has been quiet for a moment. What is being
/// typed is read by the rows straight from the model, which is observed, so a rename shows up as it
/// is typed; only the *order* of the list, its grouping, and the suggestions wait for the next
/// refresh. Anything being added or deleted -- a term, a link, a tag -- refreshes at once, since
/// those are the changes a screen would visibly miss, and none of them happens per keystroke.
///
/// Consumers which derive something from the graph (the term list's grouping reads each term's
/// links and progress) should key their recomputation on ``version``, not on ``terms``: a link
/// added to a term changes neither the terms nor their order, and an array comparison would say
/// nothing happened.
///
/// ## Why this listens to Core Data
///
/// SwiftData publishes no "model changed" event. It has `ModelContext.willSave`/`didSave`, but
/// autosave saves on lifecycle events, not on edits, so e.g. lists would remain stale far too long.
/// `hasChanges` cannot be observed. Instead, we use `NSManagedObjectContextObjectsDidChange`.
@MainActor
@Observable
final class TermStore {
    /// All terms, sorted by text.
    private(set) var terms: [Term] = []

    /// All tags, sorted by name.
    ///
    /// There are far fewer tags than terms, so fetching them is cheap. However, tags reference
    /// terms, so modifying a term refreshes `Tag` `@Query`'s, and since the `Main` view reads all
    /// tags, this would lead to rerenders on every keystroke for tags.
    private(set) var tags: [Tag] = []

    /// Bumped on every refresh of ``terms`` and ``tags``, for `onChange` to key on more cheaply
    /// than the arrays.
    private(set) var version = 0

    @ObservationIgnored private let context: ModelContext

    /// Optional to deal with `weak self` being captured by the callback given to the observer, but never `nil`.
    @ObservationIgnored private var observer: (any NSObjectProtocol)?
    @ObservationIgnored private var pendingRefresh: Task<Void, Never>?

    /// ``terms`` indexed for search, built on first use and dropped on refresh: the decomposition it
    /// does per term is not worth doing for a screen nobody searches from.
    @ObservationIgnored private var searchByText: SearchDictionary<Term>?

    init(context: ModelContext) {
        self.context = context

        observer = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextObjectsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Delivered on the main queue, so this is the main actor in all but name.
            MainActor.assumeIsolated { self?.contextDidChange(notification) }
        }

        refresh()
    }

    deinit {
        NotificationCenter.default.removeObserver(observer!)
    }

    /// One store per container, so that the app and every preview hand out the same instance for
    /// the same data. See ``SwiftUI/View/appModelContainer(_:)``.
    static func shared(for container: ModelContainer) -> TermStore {
        stores[ObjectIdentifier(container), default: TermStore(context: container.mainContext)]
    }

    private static var stores: [ObjectIdentifier: TermStore] = [:]

    // MARK: Reading

    /// `SearchDictionary` over ``terms``.
    var search: SearchDictionary<Term> {
        if let searchByText { return searchByText }

        let built = SearchDictionary(terms, by: \.text)

        searchByText = built

        return built
    }

    /// The term whose text is exactly `text`, if there is one.
    func term(named text: String) -> Term? {
        terms.first { $0.text == text }
    }

    // MARK: Refreshing

    /// Fetches every term again, now.
    func refresh() {
        pendingRefresh?.cancel()
        pendingRefresh = nil

        let termDescriptor = FetchDescriptor<Term>(sortBy: [SortDescriptor(\.text)])
        let tagDescriptor = FetchDescriptor<Tag>(sortBy: [SortDescriptor(\.name)])

        terms = (try? context.fetch(termDescriptor)) ?? []
        tags = (try? context.fetch(tagDescriptor)) ?? []
        searchByText = nil
        version &+= 1
    }

    private func contextDidChange(_ notification: Notification) {
        guard let info = notification.userInfo else { return }

        let inserted = info[NSInsertedObjectsKey] as? Set<NSManagedObject> ?? []
        let deleted = info[NSDeletedObjectsKey] as? Set<NSManagedObject> ?? []
        let updated = info[NSUpdatedObjectsKey] as? Set<NSManagedObject> ?? []

        // Process insertions and deletions immediately, as they don't trigger very often (unlike
        // updates, which can happen on each keystroke), and this is necessary to properly update
        // the UI.
        if !inserted.isEmpty || !deleted.isEmpty {
            scheduleRefresh(after: .zero)
        } else if !updated.isEmpty {
            scheduleRefresh(after: Self.quietPeriod)
        }
        // Otherwise only refreshed or invalidated objects (a merge from CloudKit re-reading rows
        // that did not change): nothing to reorder.
    }

    /// How long the store has to be quiet before an update -- as opposed to an insert or delete --
    /// is reflected in the list's order and the suggestions. Long enough that typing never triggers
    /// it; short enough that the list is right by the time a reader looks back at it.
    private static let quietPeriod: Duration = .seconds(1)

    private func scheduleRefresh(after delay: Duration) {
        pendingRefresh?.cancel()

        pendingRefresh = Task { @MainActor [weak self] in
            if delay > .zero {
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    // Superseded by a later change, which scheduled a refresh of its own.
                    return
                }
            }

            self?.refresh()
        }
    }
}

extension View {
    /// Installs `container` and the ``TermStore`` over it.
    ///
    /// Used everywhere `.modelContainer(_:)` alone is typically enough -- the app root and every
    /// preview -- so that a view reading `@Environment(TermStore.self)` finds one wherever it finds
    /// a model context.
    func appModelContainer(_ container: ModelContainer) -> some View {
        modelContainer(container).environment(TermStore.shared(for: container))
    }
}

extension Scene {
    /// The same as ``SwiftUI/View/appModelContainer(_:)``, for the app's `WindowGroup`.
    func appModelContainer(_ container: ModelContainer) -> some Scene {
        modelContainer(container).environment(TermStore.shared(for: container))
    }
}
