import PhotosUI
import SwiftUI

/// A term's picture, shown under its text wherever the term appears -- the editor and the study
/// prompt alike.
///
/// Sized to fill the width it is given, capped at ``TermImageView/maxHeight`` so a portrait photo
/// stays within the screen rather than pushing the rest of the form or the answer buttons off it.
/// `.scaledToFit()` inside that frame is what keeps a wide picture from being cropped: the cap only
/// bites when the picture is tall enough to hit it.
struct TermImageView: View {
    let data: Data

    /// How tall the picture is allowed to grow before it is capped, relative to the body font -- so
    /// a picture takes a consistent share of the screen whatever the reader's text size.
    @ScaledMetric(relativeTo: .body) private var maxHeight: CGFloat = 240

    var body: some View {
        if let image = UIImage(data: data) {
            // No corner radius: a fixed one looks fine against a portrait photo's full height, but
            // against a wide, letterboxed one -- a banner a few dozen points tall -- the same
            // radius reads as a pill rather than a softened corner. Getting it to scale with
            // whatever height `.scaledToFit()` actually renders at needs a `GeometryReader` reading
            // the picture's own aspect ratio, which is a lot of machinery for a rounded corner.
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: maxHeight)
        }
    }
}

/// Everything a screen needs to offer a term's picture actions: the picker sheet they present, and
/// the pending selection driving it.
///
/// One instance is shared by the toolbar button (offered while the term has none) and the tap menu
/// on the picture itself (offered once it does), so there is exactly one picker sheet and one
/// in-flight `PhotosPickerItem` per screen rather than each control keeping its own.
@Observable
@MainActor
final class TermPictureController {
    let term: Term

    var pickerPresented = false

    /// The item mid-selection in the picker sheet, or just chosen from it. `fileprivate` rather
    /// than `private`: `termPicturePicker(_:)` needs to bind `.photosPicker`'s selection straight
    /// to it.
    fileprivate var pickerItem: PhotosPickerItem? {
        didSet { load(pickerItem) }
    }

    init(term: Term) {
        self.term = term
    }

    private func load(_ item: PhotosPickerItem?) {
        guard let item else { return }

        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                term.image = data
                term.touch()
            }

            // Checked against the item this load started for, rather than cleared
            // unconditionally: picking a second picture before the first finishes loading starts a
            // second `load`, and the first one finishing later must not clear a selection which is
            // no longer its own.
            if self.pickerItem?.itemIdentifier == item.itemIdentifier {
                self.pickerItem = nil
            }
        }
    }

    /// Accepts what a `PasteButton` handed back, taking the first image pasted.
    func paste(_ items: [PastedImage]) {
        guard let pasted = items.first else { return }

        term.image = pasted.data
        term.touch()
    }

    func remove() {
        term.image = nil
        term.touch()
    }
}

extension View {
    /// Presents the picture controller's picker sheet, wherever in the view it was triggered from.
    ///
    /// Takes the controller optionally so the screen which owns it -- created once a term is known,
    /// see `TermEditor.pictureController` -- can apply this before that happens rather than having
    /// to unwrap it at every call site.
    func termPicturePicker(_ controller: TermPictureController?) -> some View {
        photosPicker(
            isPresented: Binding {
                controller?.pickerPresented ?? false
            } set: {
                controller?.pickerPresented = $0
            },
            selection: Binding {
                controller?.pickerItem
            } set: {
                controller?.pickerItem = $0
            },
            matching: .images
        )
    }
}

/// The toolbar button offered while a term has no picture yet: opens a menu of where to get one
/// from.
///
/// A menu rather than jumping straight to the photo library: pasting a picture is just as common a
/// starting point as picking one, and a toolbar button can only launch one action on a plain tap.
/// The button's own icon is what says "add a picture" -- its two items are named by *where they get
/// one from*, not repeating that, so opening the menu is one tap and choosing one of them is the
/// next, rather than a submenu's submenu.
struct AddPictureToolbarItem: View {
    let controller: TermPictureController

    var body: some View {
        Menu {
            Button("Add Picture", systemImage: "photo") {
                controller.pickerPresented = true
            }
            .tint(.primary)

            // The real `PasteButton` rather than a plain button reading `UIPasteboard.general`
            // directly: it reads the pasteboard without the consent alert a plain read would
            // raise, the same way the photo picker above needs no library permission by running
            // out of process.
            PasteButton(payloadType: PastedImage.self, onPaste: controller.paste)
                .tint(.primary)
        } label: {
            Image(systemName: "photo.badge.plus")
                .accessibilityLabel(Text("Add Picture"))
        }
    }
}

/// The menu a tap on the picture itself offers: replace it, paste over it, or remove it.
///
/// A `Menu` rather than a `.contextMenu`: the picture has no other single-tap action of its own to
/// give up, so opening on a tap -- not a long press -- is what makes the menu discoverable at all.
/// Requires the term to already have a picture, since that picture is the label tapped to open it.
///
/// `.confirmationDialog` was tried in its place, to avoid `Menu` dimming and shrinking the picture
/// while the menu is open -- but a `PasteButton` does not render inside one, and its own
/// positioning anchored to the top of the screen rather than sliding up from the bottom. Not worth
/// either trade for a cosmetic fix, so this is a plain `Menu` after all.
struct TermImageMenu: View {
    let controller: TermPictureController
    let image: Data

    var body: some View {
        Menu {
            Button("Replace Picture", systemImage: "photo") {
                controller.pickerPresented = true
            }
            .tint(.primary)

            PasteButton(payloadType: PastedImage.self, onPaste: controller.paste)
                .tint(.primary)

            Button("Remove Picture", systemImage: "trash", role: .destructive) {
                controller.remove()
            }
            .tint(.red)
        } label: {
            TermImageView(data: image)
        }
        .buttonStyle(.plain)
        .tint(.primary)
    }
}

/// An image pasted from the pasteboard, as raw bytes.
///
/// `PasteButton` matches most reliably against a `Transferable` type rather than against a raw
/// `NSItemProvider` and a `UTType` to check it against by hand. Wrapping `Data` in a type declared
/// to import only `.image` is also what keeps the button from also offering to "paste" copied text
/// as though it were a picture, which a bare `payloadType: Data.self` would do since `Data` itself
/// is `Transferable` for arbitrary bytes.
struct PastedImage: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { PastedImage(data: $0) }
    }
}

#Preview("Toolbar") {
    let container = previewModelContainer()
    let term = previewTerm("한국어", in: container)

    NavigationStack {
        Text("Term")
            .toolbar {
                AddPictureToolbarItem(controller: TermPictureController(term: term))
            }
    }
}
