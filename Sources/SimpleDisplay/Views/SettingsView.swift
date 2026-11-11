import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(DisplayManagerViewModel.self) private var viewModel
    @Environment(LocaleManager.self) private var locale
    @AppStorage("hideDockIconWhenWindowsClosed") private var hideDockIconWhenWindowsClosed = true
    @State private var launchAtLogin: Bool = false
    @State private var loginItemNeedsApproval: Bool = false
    /// Prevents onChange from firing during initial onAppear value loading
    @State private var didLoadInitialValues: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(locale.t("settings"))
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.navigate(to: .displayList)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.isNavigating)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            VStack(spacing: 0) {
                // About card at top
                HStack(spacing: 14) {
                    AppIconView(size: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: "SimpleDisplay")
                            .font(.system(.body, weight: .semibold))
                        Text(verbatim: locale.t("version_format", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(16)

                // Settings rows
                VStack(spacing: 1) {
                    // Launch at login
                    settingsRow {
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle(isOn: $launchAtLogin) {
                                HStack(spacing: 10) {
                                    settingsIcon("power", color: .green)
                                    Text(locale.t("launch_at_login"))
                                        .font(.callout)
                                }
                            }
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .onChange(of: launchAtLogin) { _, newValue in
                                guard didLoadInitialValues else { return }
                                setLaunchAtLogin(newValue)
                            }

                            if loginItemNeedsApproval {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.orange)
                                    Text(locale.t("login_item_needs_approval"))
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                                .padding(.leading, 36)
                            }
                        }
                    }

                    settingsRow {
                        HStack(alignment: .top, spacing: 10) {
                            settingsIcon("macwindow", color: .purple)
                            VStack(alignment: .leading, spacing: 4) {
                                Toggle(locale.t("hide_dock_icon"), isOn: $hideDockIconWhenWindowsClosed)
                                    .toggleStyle(.checkbox)
                                    .font(.callout)
                                Text(locale.t("hide_dock_icon_help"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 20)
                            }
                        }
                    }

                    // Language
                    settingsRow {
                        HStack(spacing: 10) {
                            settingsIcon("globe", color: .cyan)
                            LanguageSwitcherView()
                        }
                    }

                    // Website
                    settingsRow {
                        if let url = URL(string: "https://simpledisplay.app") {
                            Link(destination: url) {
                                HStack(spacing: 10) {
                                    settingsIcon("globe", color: .blue)
                                    Text(locale.t("website"))
                                        .font(.callout)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text(verbatim: "simpledisplay.app")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }

                    // Contact
                    // Companion app: the remote desktop that SimpleDisplay's virtual
                    // displays were built for (same author, free software).
                    settingsRow {
                        if let url = URL(string: "https://remotedisplay.app") {
                            Link(destination: url) {
                                HStack(spacing: 10) {
                                    settingsIcon("rectangle.connected.to.line.below", color: .teal)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(locale.t("remote_display_title"))
                                            .font(.callout)
                                            .foregroundStyle(.primary)
                                        Text(locale.t("remote_display_subtitle"))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(verbatim: "remotedisplay.app")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    settingsRow {
                        if let url = URL(string: "mailto:info@simpledisplay.app") {
                            Link(destination: url) {
                                HStack(spacing: 10) {
                                    settingsIcon("envelope.fill", color: .indigo)
                                    Text(locale.t("contact"))
                                        .font(.callout)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text(verbatim: "info@simpledisplay.app")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 12)

                // Footer
                Text(verbatim: locale.t("footer_compat"))
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
                    .padding(.top, 14)
                    .padding(.bottom, 8)
            }
        }
        .onAppear {
            let status = SMAppService.mainApp.status
            launchAtLogin = status == .enabled
            loginItemNeedsApproval = status == .requiresApproval
            DispatchQueue.main.async {
                didLoadInitialValues = true
            }
        }
    }

    // MARK: - Components

    @ViewBuilder
    private func settingsRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
    }

    @ViewBuilder
    private func settingsIcon(_ name: String, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(color)
                .frame(width: 26, height: 26)
            Image(systemName: name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
        }
    }

    /// Returns UUIDs of currently online physical displays (not virtual).
     private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            let status = SMAppService.mainApp.status
            loginItemNeedsApproval = status == .requiresApproval
        } catch {
            viewModel.errorMessage = locale.t("failed_login_item", error.localizedDescription)
            launchAtLogin = !enabled
        }
    }
}
