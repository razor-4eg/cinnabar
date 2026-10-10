import SwiftUI

struct Thumbnail: View {
    var url: URL?
    var symbolSize: CGFloat = 18

    var body: some View {
        Color.primary.opacity(0.06)
            .overlay {
                if let url {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            placeholder
                        default:
                            ProgressView().controlSize(.small)
                        }
                    }
                } else {
                    placeholder
                }
            }
            .clipped()
    }

    private var placeholder: some View {
        Image(systemName: "play.fill")
            .font(.system(size: symbolSize, weight: .semibold))
            .foregroundStyle(.tertiary)
    }
}

struct ErrorBanner: View {
    var message: String
    var dismiss: () -> Void
    var reveal: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .padding(.top, 1)
                Text(message)
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            if let reveal {
                Button("Show file for LuLu", action: reveal)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct SetupCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.accent.opacity(0.12))
                        .frame(width: 48, height: 48)
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Prepare the download")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Cinnabar downloads the video with yt-dlp and builds the file with ffmpeg. Both tools are free and stay inside the app folder.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 12) {
                Button(action: model.install) {
                    Label(model.isInstalling ? String(localized: "Installing…") : String(localized: "Install"), systemImage: "square.and.arrow.down")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 4)
                }
                .modifier(PrimaryButtonModifier())
                .disabled(model.isInstalling)

                if model.isInstalling {
                    ProgressView().controlSize(.small)
                    Text(model.installMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if let installError = model.installError {
                Text(installError)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Only save videos you're allowed to download.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .modifier(CardModifier())
    }
}

struct FeatureHintRow<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @Stored private var height: CGFloat = 0

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            content()
        }
        .environment(\.featureHintHeight, height)
        .onPreferenceChange(FeatureHintHeightKey.self) { height = $0 }
    }
}

struct FeatureHint: View {
    @Environment(\.featureHintHeight) private var sharedHeight
    var symbol: String
    var title: String
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 22, height: 22, alignment: .leading)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: FeatureHintHeightKey.self, value: proxy.size.height)
            }
        }
        .frame(maxWidth: .infinity, minHeight: sharedHeight, alignment: .topLeading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct FeatureHintHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct FeatureHintHeightEnvironmentKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

private extension EnvironmentValues {
    var featureHintHeight: CGFloat {
        get { self[FeatureHintHeightEnvironmentKey.self] }
        set { self[FeatureHintHeightEnvironmentKey.self] = newValue }
    }
}
