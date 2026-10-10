import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("Folder") {
                LabeledContent("Current") {
                    Text(model.destination.path)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                HStack {
                    Button("Choose…", action: model.chooseFolder)
                    Button("Open", action: model.openDestination)
                }
            }

            Section("Components") {
                toolRow("yt-dlp", url: model.engineStatus.ytdlp)
                toolRow("ffmpeg", url: model.engineStatus.ffmpeg)
                toolRow("ffprobe", url: model.engineStatus.ffprobe)

                HStack {
                    Button(model.isInstalling ? String(localized: "Installing…") : String(localized: "Install missing"), action: model.install)
                        .disabled(model.isInstalling || (model.engineStatus.ytdlp != nil && model.engineStatus.ffmpeg != nil))
                    Button("Update", action: model.updateComponents)
                        .disabled(model.isInstalling || model.activeCount > 0)
                    Button("Remove", action: model.removeComponents)
                        .disabled(model.isInstalling || model.activeCount > 0 || !model.hasManagedComponents)
                }
                Button("Check again", action: model.refreshEngine)
                    .disabled(model.isInstalling)

                Text("Only Cinnabar's own copies are removed or replaced. ffmpeg installed with Homebrew stays.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if model.isInstalling || !model.installMessage.isEmpty {
                    Text(model.installMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                if let installError = model.installError {
                    Text(installError)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }
            }

            Section {
                Text("Only save videos you're allowed to download.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 680)
        .frame(minHeight: 520)
        .padding(.vertical, 12)
        .onAppear { model.refreshEngine() }
    }

    private func toolRow(_ name: String, url: URL?) -> some View {
        LabeledContent(name) {
            if let url {
                Text(url.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            } else {
                Text("not found")
                    .foregroundStyle(.orange)
            }
        }
    }
}
