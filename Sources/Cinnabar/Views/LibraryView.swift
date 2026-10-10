import SwiftUI

struct LibraryView: View {
    @Environment(AppModel.self) private var model

    private let columns = [GridItem(.adaptive(minimum: 230, maximum: 320), spacing: 16)]

    var body: some View {
        Group {
            if model.library.isEmpty {
                empty
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(model.library) { item in
                            LibraryCard(item: item)
                        }
                    }
                    .padding(28)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "film")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Empty for now")
                .font(.system(size: 16, weight: .semibold))
            Text("Downloaded videos will show up here.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LibraryCard: View {
    @Environment(AppModel.self) private var model
    var item: LibraryItem
    @Stored private var hovering = false

    private var fileExists: Bool {
        FileManager.default.fileExists(atPath: item.filePath)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Thumbnail(url: item.thumbnailURL)
                .frame(height: 140)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    Text(item.qualityTitle)
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.72), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(8)
                }
                .overlay {
                    if !fileExists {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.black.opacity(0.45))
                        Text("File removed")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }

            Text(item.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)
                .frame(minHeight: 34, alignment: .topLeading)

            HStack {
                Text(Formatters.relative(item.createdAt))
                Spacer()
                if let bytes = item.bytes {
                    Text(Formatters.bytes(bytes))
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(hovering ? Theme.accent.opacity(0.55) : Color.primary.opacity(0.06), lineWidth: 1)
        )
        .opacity(fileExists ? 1 : 0.72)
        .onHover { hovering = $0 }
        .onTapGesture {
            guard fileExists else { return }
            model.openFile(item.filePath)
        }
        .contextMenu {
            if fileExists {
                Button("Open") { model.openFile(item.filePath) }
                Button("Show in Finder") { model.reveal(item.filePath) }
                Divider()
                Button("Move to Trash", role: .destructive) { model.trash(item) }
            }
            Button("Remove from library") { model.forget(item) }
        }
    }
}
