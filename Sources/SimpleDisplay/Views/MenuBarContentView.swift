import SwiftUI

struct MenuBarContentView: View {
    @Environment(DisplayManagerViewModel.self) private var viewModel
    @Environment(LocaleManager.self) private var locale

    private var configuringDisplay: DisplayInfo? {
        guard case .configuringDisplay(let id) = viewModel.navigationState else { return nil }
        return viewModel.displays.first { $0.id == id }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Button {
                    viewModel.navigate(to: .settings)
                } label: {
                    AppIconView(size: 24)
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.isNavigating)

                Text(verbatim: locale.t("app_name"))
                    .font(.headline)
                Spacer()
                if viewModel.isBusy {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                } else {
                    Button {
                        viewModel.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Headless countdown: the last visible display was just turned off.
            // Whoever can still see this (a remote session) may keep it; nobody
            // confirming turns the screen back on.
            if let pending = viewModel.headlessPending {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "display.trianglebadge.exclamationmark")
                            .foregroundStyle(.red)
                        Text(verbatim: locale.t("headless_warning"))
                            .font(.caption)
                            .fontWeight(.medium)
                        Spacer()
                        Text(verbatim: locale.t("headless_countdown_format", pending.secondsLeft))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        Button(locale.t("headless_revert")) {
                            viewModel.revertHeadless()
                        }
                        .controlSize(.small)
                        Button(locale.t("headless_keep")) {
                            viewModel.confirmHeadless()
                        }
                        .controlSize(.small)
                        Spacer()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.red.opacity(0.1))

                Divider()
            }

            // Error banner
            if let error = viewModel.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(verbatim: error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    Spacer()
                    Button {
                        viewModel.errorMessage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.orange.opacity(0.1))
                .task(id: error) {
                    try? await Task.sleep(for: .seconds(8))
                    if viewModel.errorMessage == error {
                        viewModel.errorMessage = nil
                    }
                }

                Divider()
            }

            // Busy indicator
            if viewModel.isBusy, let message = viewModel.busyMessage {
                HStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.mini)
                    Text(verbatim: message)
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .transition(.move(edge: .top).combined(with: .opacity))

                Divider()
            }

            switch viewModel.navigationState {
            case .settings:
                SettingsView()
                    .environment(viewModel)
                    .environment(locale)

            case .addVirtualDisplay:
                VirtualDisplayEditorView(editing: nil)
                    .environment(viewModel)
                    .environment(locale)

            case .configuringDisplay:
                if let display = configuringDisplay, display.isVirtual {
                    VirtualDisplayEditorView(editing: display, saved: viewModel.virtualConfig(for: display))
                        .environment(viewModel)
                        .environment(locale)
                } else {
                    displayListContent
                }

            case .displayList:
                displayListContent
            }
        }
        .background(PopoverWindowReader { viewModel.popoverWindow = $0 })
        .frame(width: 500)
        .onAppear {
            // Fix TextField focus in MenuBarExtra .window style
            NSApp.activate(ignoringOtherApps: true)
            // Re-sync with the live display topology each time the popover opens,
            // so any state left stale by an async reconfiguration self-corrects.
            if !viewModel.isBusy { viewModel.refresh() }
        }
    }

    // MARK: - Display List

    @ViewBuilder
    private var displayListContent: some View {
        if viewModel.displays.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "display.trianglebadge.exclamationmark")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(locale.t("no_displays"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            // Note: minHeight is required because SwiftUI MenuBarExtra (.window) can
            // size the popover to 0 height when the ScrollView's lazy content reports
            // no intrinsic size at first evaluation, leaving the rows invisible.
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(viewModel.displays) { display in
                        DisplayRowView(display: display)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
            }
            .frame(minHeight: 200, maxHeight: 450)
        }

        Divider()

        // Footer
        HStack(spacing: 10) {
            Button {
                viewModel.navigate(to: .settings)
            } label: {
                Image(systemName: "gearshape")
                    .font(.callout)
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.isNavigating)

            Divider()
                .frame(height: 16)

            Button {
                viewModel.navigate(to: .addVirtualDisplay)
            } label: {
                Label(locale.t("virtual_display"), systemImage: "plus.rectangle.on.rectangle")
                    .font(.callout)
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.isBusy || viewModel.isNavigating)

            Spacer()

            Button(locale.t("quit")) {
                viewModel.quitFromPopover()
            }
            .buttonStyle(.borderless)
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
