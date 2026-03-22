import SwiftUI

/// View displayed when opening the app for the first time.
struct OnboardingView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack {
            Spacer()

            Text("Welcome to YAFA").font(.largeTitle).padding(.bottom, 8)

            OnboardingParagraph(
                image: "repeat",
                title: "Spaced repetition",
                description: "Remember what you learn using [FSRS](https://github.com/open-spaced-repetition/fsrs4anki/wiki)."
            )

            Divider()

            OnboardingParagraph(
                image: "lock",
                title: "Private",
                description: "Data is stored locally, can be imported from CSV, and can be exported to CSV or JSON. iCloud synchronization is also supported."
            )

            Divider()

            OnboardingParagraph(
                image: "tag",
                title: "Tags",
                description: "Organize flashcards using tags."
            )

            Divider()

            OnboardingParagraph(
                image: "circlebadge.2",
                title: "Ease-of-use",
                description: "Standard, predictable iOS components make it easy to study, add, and modify flashcards."
            )

            Divider()

            OnboardingParagraph(
                image: "text.page.badge.magnifyingglass",
                title: "Open-source",
                description: "YAFA is free and [open-source](https://github.com/71/YAFA)."
            )

            Spacer()

            Button {
                onContinue()
            } label: {
                Text("Continue")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
        }
        .navigationTitle("Welcome")
        .padding(16)
    }
}

#Preview {
    OnboardingView(onContinue: {}).modelContainer(previewModelContainer())
}

private struct OnboardingParagraph: View {
    let image: String
    let title: LocalizedStringKey
    let description: LocalizedStringKey

    var body: some View {
        HStack {
            Image(systemName: image)
                .font(.title)
                .frame(width: 42, height: 42)

            VStack(alignment: .leading) {
                Text(title).font(.headline).padding(.bottom, 1)
                Text(description)
            }

            Spacer()
        }
    }
}
