import SwiftUI
import EverClipCore

/// A single history row: leading icon/thumbnail, preview text, metadata, and
/// pin/delete actions that appear on hover.
struct ClipRowView: View {
    let item: ClipItem
    let isSelected: Bool
    let thumbnailPath: String?
    var onActivate: () -> Void
    var onTogglePin: () -> Void
    var onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            leading
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(displayTitle)
                    .font(.system(size: 12.5))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    TypeBadge(kind: item.kind)
                    if let source = item.sourceAppName, !source.isEmpty {
                        Text(source).lineLimit(1)
                    }
                    Text("·")
                    Text(Theme.relativeTime(item.updatedAt))
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            if hovering || isSelected || item.isFavorite {
                HStack(spacing: 2) {
                    IconButton(
                        systemName: item.isFavorite ? "star.fill" : "star",
                        tint: item.isFavorite ? .yellow : .secondary,
                        help: item.isFavorite ? "Unpin" : "Pin to Favorites",
                        action: onTogglePin
                    )
                    if hovering || isSelected {
                        IconButton(systemName: "trash", tint: .secondary, help: "Delete", action: onDelete)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rowCornerRadius, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onActivate)
    }

    @ViewBuilder private var leading: some View {
        if item.kind.isBinary, let path = thumbnailPath, let image = ThumbnailCache.shared.image(atPath: path) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                item.kind.tint.opacity(0.16)
                Image(systemName: item.kind.symbolName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(item.kind.tint)
            }
        }
    }

    private var background: Color {
        if isSelected { return Theme.accent.opacity(0.20) }
        if hovering { return Color.primary.opacity(0.06) }
        return .clear
    }

    private var displayTitle: String {
        switch item.kind {
        case .image, .screenshot:
            if let w = item.pixelWidth, let h = item.pixelHeight {
                return "\(item.kind.badgeLabel) · \(w)×\(h)"
            }
            return item.kind.badgeLabel
        case .file:
            let names = item.fileURLs.map { ($0 as NSString).lastPathComponent }
            return names.isEmpty ? (item.preview ?? "File") : names.joined(separator: ", ")
        default:
            return item.preview ?? item.text ?? ""
        }
    }
}

/// The small colored type chip.
struct TypeBadge: View {
    let kind: ClipKind
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: kind.symbolName).font(.system(size: 8, weight: .semibold))
            Text(kind.badgeLabel)
        }
        .font(.system(size: 9.5, weight: .medium))
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(kind.tint.opacity(0.18))
        .foregroundStyle(kind.tint)
        .clipShape(Capsule())
    }
}

/// A borderless icon button used for row actions.
struct IconButton: View {
    let systemName: String
    var tint: Color = .secondary
    var help: String = ""
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(hovering ? Color.primary.opacity(0.10) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}
