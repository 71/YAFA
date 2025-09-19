import SwiftData
import SwiftUI

/// A `List` of `Tags` which can be selected and unselected.
struct TagSelectionList: View {
    let selectedTags: [FlashcardTag]
    let addTag: (FlashcardTag) -> Void
    let removeTags: (IndexSet) -> Void

    @Query(sort: \FlashcardTag.name) private var allTags: [FlashcardTag]
    @State private var selectedTagsSet = Set<FlashcardTag>()
    @FocusState private var focusedTag: FlashcardTag?

    var body: some View {
        List {
            ForEach(selectedTags) { tag in
                TextField(
                    "Tag name", text: bindToProperty(of: tag, \.name)
                )
                .focused($focusedTag, equals: tag)
            }
            .onDelete { removeTags($0) }

            Menu {
                ForEach(allTags) { tag in
                    if !selectedTagsSet.contains(tag) {
                        Button {
                            addTag(tag)
                        } label: {
                            Text(tag.name)
                        }
                    }
                }

                Divider()

                Button {
                    let newTag = FlashcardTag(name: "New tag")

                    addTag(newTag)
                    focusedTag = newTag
                } label: {
                    Label("New tag", systemImage: "plus")
                }
            } label: {
                Text("Add tag")
            }
            .foregroundStyle(.tertiary)
        }
        .onChange(of: selectedTags, initial: true) {
            selectedTagsSet = Set(selectedTags)
        }
    }
}
