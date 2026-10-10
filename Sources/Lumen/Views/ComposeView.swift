import SwiftUI
import UniformTypeIdentifiers

struct ComposeView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var linkFocused: Bool
    @Stored private var dropActive = false

    var body: some View {
        @Bindable var model = model

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Save video")
                        .font(.system(size: 32, weight: .semibold))
                        .tracking(-0.6)
                    Text("Paste a YouTube link and Lumen will download it in the quality you choose.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }

                if model.engineStatus.ytdlp == nil {
                    SetupCard()
                } else {
                    linkField
                    if model.engineStatus.ffmpeg == nil {
                        ffmpegNotice
                    }
                }

                if let message = model.errorBanner {
                    ErrorBanner(
                        message: message,
                        dismiss: { model.errorBanner = nil },
                        reveal: message.contains("LuLu") ? { model.revealEngine() } : nil
                    )
                }

                if model.isResolving, model.preview == nil {
                    resolvingCard
                }

                if let preview = model.preview {
                    PreviewCard(preview: preview)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if !model.jobs.isEmpty {
                    queue
                } else if model.preview == nil, !model.isResolving, model.engineStatus.ytdlp != nil {
                    hints
                }
            }
            .padding(.horizontal, 36)
            .padding(.top, 28)
            .padding(.bottom, 40)
            .frame(maxWidth: 880, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.automatic)
        .animation(.spring(duration: 0.4), value: model.preview?.id)
        .animation(.spring(duration: 0.35), value: model.jobs.map(\.id))
        .onAppear { linkFocused = true }
        .onDrop(of: [UTType.url, UTType.plainText], isTargeted: $dropActive) { providers in
            loadDrop(providers)
        }
        .overlay {
            if dropActive {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
                    .background(Theme.accent.opacity(0.05), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .padding(16)
                    .allowsHitTesting(false)
            }
        }
    }

    private var linkField: some View {
        @Bindable var model = model

        return HStack(spacing: 10) {
            Image(systemName: "link")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .symbolEffect(.pulse, isActive: model.isResolving)

            TextField("https://www.youtube.com/watch?v=…", text: $model.urlText)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .medium))
                .focused($linkFocused)
                .onSubmit { Task { await model.resolve() } }
                .onChange(of: model.urlText) { _, _ in
                    model.urlDidChange()
                }

            if model.pasteHint, model.urlText.isEmpty {
                Button("Paste", action: model.pasteAndResolve)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }

            if !model.urlText.isEmpty {
                Button {
                    model.urlText = ""
                    model.preview = nil
                    model.errorBanner = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear")
            }

            Button {
                Task { await model.resolve() }
            } label: {
                if model.isResolving {
                    ProgressView().controlSize(.small).frame(width: 48)
                } else {
                    Text("Find")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(minWidth: 48)
                }
            }
            .modifier(PrimaryButtonModifier())
            .disabled(model.isResolving || model.urlText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(dropActive ? Theme.accent.opacity(0.8) : Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var ffmpegNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 6) {
                Text("Without ffmpeg you get one ready-made file, usually up to 720p. 1080p and 4K need ffmpeg.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Install ffmpeg", action: model.install)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .disabled(model.isInstalling)
                if model.isInstalling {
                    Text(model.installMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var resolvingCard: some View {
        HStack(alignment: .top, spacing: 18) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .frame(width: 248, height: 140)
                .overlay { ProgressView() }
            VStack(alignment: .leading, spacing: 10) {
                capsule(width: 260)
                capsule(width: 150)
                Text("Looking up the video…")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text("If LuLu asks for permission, click Allow.")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .modifier(CardModifier())
    }

    private func capsule(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.primary.opacity(0.08))
            .frame(width: width, height: 14)
    }

    private var queue: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Queue")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if model.activeCount > 0 {
                    Text(model.activeCount == 1
                         ? String(localized: "1 in progress")
                         : String(format: String(localized: "%d in progress"), model.activeCount))
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
            ForEach(model.jobs) { job in
                JobRow(job: job)
            }
        }
    }

    private var hints: some View {
        FeatureHintRow {
            FeatureHint(symbol: "4k.tv", title: String(localized: "Up to 4K"), text: String(localized: "Or audio only, if you don't need the picture."))
            FeatureHint(symbol: "square.stack.3d.down.right", title: String(localized: "Queue"), text: String(localized: "A few videos download one after another."))
            FeatureHint(symbol: "folder", title: String(localized: "In your folder"), text: String(localized: "The file opens with a double-click."))
        }
        .padding(.top, 8)
    }

    private func loadDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        let type = provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) ? UTType.url.identifier : UTType.plainText.identifier
        provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
            let raw: String?
            if let url = item as? URL {
                raw = url.absoluteString
            } else if let string = item as? String {
                raw = string
            } else if let data = item as? Data {
                raw = String(data: data, encoding: .utf8)
            } else {
                raw = nil
            }
            guard let raw else { return }
            Task { @MainActor in
                model.acceptDrop(raw)
            }
        }
        return true
    }
}

private struct PreviewCard: View {
    @Environment(AppModel.self) private var model
    var preview: PreviewModel

    var body: some View {
        @Bindable var model = model

        HStack(alignment: .top, spacing: 18) {
            Thumbnail(url: preview.thumbnail, symbolSize: 22)
                .frame(width: 248, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if let duration = preview.durationText {
                        Text(duration)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.72), in: Capsule())
                            .foregroundStyle(.white)
                            .padding(8)
                    }
                }

            VStack(alignment: .leading, spacing: 12) {
                Text(preview.title)
                    .font(.system(size: 18, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(meta)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(preview.qualities) { quality in
                            QualityChip(
                                title: quality.title,
                                selected: model.selectedQuality == quality
                            ) {
                                model.selectedQuality = quality
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)

                HStack(alignment: .center, spacing: 14) {
                    Button(action: model.download) {
                        Label("Download", systemImage: "arrow.down")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 4)
                    }
                    .modifier(PrimaryButtonModifier())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(model.selectedQuality.containerName) · \(model.selectedQuality.title)")
                        if let estimate = preview.estimates[model.selectedQuality] {
                            Text(String(format: String(localized: "about %@"), Formatters.bytes(estimate)))
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .modifier(CardModifier())
    }

    private var meta: String {
        [preview.channel, preview.views].compactMap { $0 }.joined(separator: "  ·  ")
    }
}

private struct QualityChip: View {
    var title: String
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(selected ? Theme.accentFill : Color.primary.opacity(0.06), in: Capsule())
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

private struct JobRow: View {
    @Environment(AppModel.self) private var model
    var job: DownloadJob

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Thumbnail(url: job.thumbnail, symbolSize: 12)
                    .frame(width: 72, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(job.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text("\(job.quality.title) · \(job.detail)")
                        .font(.system(size: 12))
                        .foregroundStyle(isFailed ? Color.red : Color.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                if case .running = job.state {
                    Text("\(Int((job.fraction * 100).rounded()))%")
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                trailing
            }

            if job.state == .running || job.state == .finishing {
                ProgressView(value: min(max(job.fraction, 0), 1))
                    .tint(Theme.accent)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var isFailed: Bool {
        if case .failed = job.state { return true }
        return false
    }

    @ViewBuilder
    private var trailing: some View {
        switch job.state {
        case .queued, .running, .finishing:
            Button {
                model.cancel(job.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 26, height: 26)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Cancel download")
        case .completed:
            if let path = job.filePath {
                Button("Show") { model.reveal(path) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            dismiss
        case .failed:
            Button("Retry") { model.retry(job.id) }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)
            dismiss
        case .cancelled:
            dismiss
        }
    }

    private var dismiss: some View {
        Button {
            model.dismiss(job.id)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .help("Remove from queue")
    }
}
