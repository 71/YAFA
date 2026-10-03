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
/// What is being typed is read by the rows straight from the model, which is observed, so a rename
/// shows up as it is typed; only the *order* of the list, its grouping, and the suggestions depend
/// on this being current. It is kept current two ways:
///
/// - **After every save of the main context** (`ModelContext.didSave`). This is when SwiftData
///   publishes its changes to Core Data. Autosave runs every few tens of seconds, so this alone can
///   leave the store that far behind.
///
/// - **On demand, where being behind would show**: typically by calling `refresh()` in `onAppear`.
///   A refresh fetches every term, so shound not trigger on each keystroke.
///
/// Consumers which derive something from the graph (the term list's grouping reads each term's
/// links and progress) should key their recomputation on ``version``, not on ``terms``: a link
/// added to a term changes neither the terms nor their order, and an array comparison would say
/// nothing happened.
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

    /// ``terms`` indexed for search, built on first use and dropped on refresh: the decomposition it
    /// does per term is not worth doing for a screen nobody searches from.
    @ObservationIgnored private var searchByText: SearchDictionary<Term>?

    init(context: ModelContext) {
        self.context = context

        // Only observe saves on this context. Using `NSManagedObjectContextObjectsDidChange` would
        // make us receive unrelated notifications -- lots of 'em, and won't actually trigger on
        // change, but on save, just like `ModelContext.didSave`.
        observer = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave,
            object: context,
            queue: .main
        ) { [weak self] _ in
            // Delivered on the main queue, so this is the main actor in all but name.
            MainActor.assumeIsolated { self?.refresh() }
        }

        refresh()
    }

    deinit {
        NotificationCenter.default.removeObserver(observer!)
    }

    /// One store per container, so that the app and every preview hand out the same instance for
    /// the same data. See ``SwiftUI/View/appModelContainer(_:)``.
    static func shared(for container: ModelContainer) -> TermStore {
        let key = ObjectIdentifier(container)

        if let existing = stores[key] { return existing }
        let store = TermStore(context: container.mainContext)

        stores[key] = store

        return store
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

    /// Fetches every term and tag again, now.
    func refresh() {
        let termDescriptor = FetchDescriptor<Term>(sortBy: [SortDescriptor(\.text)])
        let tagDescriptor = FetchDescriptor<Tag>(sortBy: [SortDescriptor(\.name)])

        terms = (try? context.fetch(termDescriptor)) ?? []
        tags = (try? context.fetch(tagDescriptor)) ?? []
        searchByText = nil
        version &+= 1
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
