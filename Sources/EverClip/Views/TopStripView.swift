import SwiftUI
import EverClipCore

/// The pinned horizontal strip of the most-recent items across the top.
struct TopStripView: View {
    let items: [ClipItem]
    var thumbnailProvider: (ClipItem) -> String?
    var onActivate: (ClipItem) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    TopStripCard(
                        item: item,
                        index: index,
                        thumbnailPath: thumbnailProvider(item),
                        onActivate: { onActivate(item) }
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(height: 78)
    }
}

private struct TopStripCard: View {
    let item: ClipItem
    let index: Int
    let thumbnailPath: String?
    var onActivate: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: item.kind.symbolName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(item.kind.tint)
                Spacer()
                if index < 9 {
                    Text("⌘\(index + 1)")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }

            if item.kind.isBinary, let path = thumbnailPath, let image = ThumbnailCache.shared.image(atPath: path) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 30)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                Text(caption)
                    .font(.system(size: 10))
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 30, alignment: .top)
            }
        }
        .padding(8)
        .frame(width: 104, height: 62)
        .background(hovering ? Color.primary.opacity(0.10) : Color.primary.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(hovering ? 0.14 : 0.06))
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onActivate)
        .help(caption)
    }

    private var caption: String {
        switch item.kind {
        case .image, .screenshot: return item.kind.badgeLabel
        case .file:
            let names = item.fileURLs.map { ($0 as NSString).lastPathComponent }
            return names.isEmpty ? (item.preview ?? "File") : names.joined(separator: ", ")
        default: return item.preview ?? item.text ?? ""
        }
    }
}
