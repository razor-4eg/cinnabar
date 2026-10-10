import AppKit
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        HStack(spacing: 0) {
            Sidebar(section: $model.section)
                .frame(width: 236)
                .background(Theme.sidebar)

            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)

            ZStack(alignment: .topTrailing) {
                Theme.canvas
                Circle()
                    .fill(Theme.accent.opacity(0.16))
                    .frame(width: 420, height: 420)
                    .blur(radius: 110)
                    .offset(x: 140, y: -190)
                    .allowsHitTesting(false)

                Group {
                    switch model.section {
                    case .compose:
                        ComposeView()
                    case .library:
                        LibraryView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 920, minHeight: 640)
        .background(Theme.canvas)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Choose another folder…", action: model.chooseFolder)
                    Button("Show in Finder", action: model.openDestination)
                } label: {
                    Label(model.destination.lastPathComponent, systemImage: "folder")
                        .labelStyle(.titleAndIcon)
                }
                .menuIndicator(.hidden)
                .help(model.destination.path)
            }
            ToolbarItem(placement: .primaryAction) {
                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
            }
        }
        .toolbar(removing: .sidebarToggle)
        .onAppear {
            model.refreshEngine()
            model.refreshPasteHint()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshEngine()
            model.refreshPasteHint()
        }
    }
}

private struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @Binding var section: AppSection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Theme.mark)
                        .frame(width: 32, height: 32)
                        .shadow(color: Color(red: 0.7, green: 0.1, blue: 0.12).opacity(0.35), radius: 8, y: 4)
                    Image(systemName: "arrow.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Lumen")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Downloads")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 28)
            .padding(.bottom, 22)

            VStack(spacing: 4) {
                SideItem(
                    title: String(localized: "New download"),
                    symbol: "plus.circle",
                    isSelected: section == .compose
                ) { section = .compose }

                SideItem(
                    title: String(localized: "Library"),
                    symbol: "film",
                    isSelected: section == .library,
                    badge: model.library.count
                ) { section = .library }
            }
            .padding(.horizontal, 10)

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                ToolStatus(name: "yt-dlp", ready: model.engineStatus.ytdlp != nil)
                ToolStatus(name: "ffmpeg", ready: model.engineStatus.ffmpeg != nil)
                if !model.engineStatus.isReady || model.engineStatus.ffmpeg == nil {
                    Button(action: model.install) {
                        Text(model.isInstalling ? String(localized: "Installing…") : String(localized: "Install"))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                    .disabled(model.isInstalling)
                    .padding(.top, 2)
                }
            }
            .padding(16)

            Text(versionText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
        }
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return "Lumen \(version)"
    }
}

private struct SideItem: View {
    var title: String
    var symbol: String
    var isSelected: Bool
    var badge: Int?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 20)
                    .foregroundStyle(isSelected ? Theme.accent : .secondary)
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                Spacer(minLength: 0)
                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(0.07) : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct ToolStatus: View {
    var name: String
    var ready: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(ready ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
            Text(name)
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Text(ready ? String(localized: "ready") : String(localized: "missing"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}
