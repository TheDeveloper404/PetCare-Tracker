import SwiftUI
import ImageIO

enum CareTheme {
    static let tint = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.38, green: 0.85, blue: 0.82, alpha: 1)
            : UIColor(red: 0, green: 0.4, blue: 0.42, alpha: 1)
    })
}

struct InlineError: View {
    let message: String?
    var body: some View {
        if let message {
            Label(message, systemImage: "exclamationmark.circle")
                .foregroundStyle(.red)
                .font(.callout)
                .accessibilityAddTraits(.isStaticText)
        }
    }
}

struct PetAvatar: View {
    let pet: Pet
    let photos: PhotoStore
    var size: CGFloat = 48
    @State private var loadedImage: UIImage?
    var body: some View {
        Group {
            if let loadedImage {
                Image(uiImage: loadedImage).resizable().scaledToFill()
            } else { placeholder }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityHidden(true)
        .task(id: pet.photoName) {
            loadedImage = nil
            guard let url = photos.url(for: pet.photoName) else { return }
            let image = await Task.detached(priority: .utility) {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: 300,
                        kCGImageSourceCreateThumbnailWithTransform: true
                      ] as CFDictionary) else { return UIImage?.none }
                return UIImage(cgImage: thumbnail)
            }.value
            if !Task.isCancelled { loadedImage = image }
        }
    }
    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 16).fill(CareTheme.tint.opacity(0.12))
            .overlay { Image(systemName: "pawprint.fill").font(.title2).foregroundStyle(CareTheme.tint) }
    }
}

struct PetRow: View {
    let pet: Pet
    let photos: PhotoStore
    var body: some View {
        HStack(spacing: 16) {
            PetAvatar(pet: pet, photos: photos)
            VStack(alignment: .leading, spacing: 4) {
                Text(pet.name).font(.headline)
                Text(L10n.text(pet.species)).font(.subheadline).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 4)
    }
}

struct DayPicker: View {
    let title: String
    @Binding var iso: String
    var body: some View {
        DatePicker(selection: Binding(get: { CalendarDay(iso: iso)?.date() ?? Date() },
                                      set: { iso = CalendarDay($0).iso }), displayedComponents: .date) {
            Text(L10n.text(title))
        }
    }
}

struct EmptyCareView: View {
    let title: String
    let message: String
    let symbol: String
    let actionTitle: String
    let action: () -> Void
    var body: some View {
        ContentUnavailableView {
            Label(L10n.text(title), systemImage: symbol)
        } description: { Text(L10n.text(message)) } actions: {
            Button(L10n.text(actionTitle), action: action).buttonStyle(.borderedProminent)
        }
    }
}

struct FileShare: Identifiable {
    let id = UUID()
    let url: URL
}

struct ActivitySheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in try? FileManager.default.removeItem(at: url) }
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
