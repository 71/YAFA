import SwiftData
import SwiftUI

struct TagSelectionList: View {
    let selectedTags: [FlashcardTag]
    let addTag: (FlashcardTag) -> Void
    let removeTags: (IndexSet) -> Void

    @Query(sort: \FlashcardTag.name) private var allTags: [FlashcardTag]
    @State private var selectedTagsSet = Set<FlashcardTag>()

    var body: some View {
        List {
            ForEach(selectedTags) { tag in
                TextField(
                    "Tag name", text: bindToProperty(of: tag, \.name)
                )
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
                    addTag(FlashcardTag(name: "New tag"))
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
