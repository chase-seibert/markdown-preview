import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    convenience init(
        fontScale: FontScaleController,
        appearance: AppearanceController,
        dockVisibility: DockVisibilityController
    ) {
        let root = SettingsView(
            fontScale: fontScale,
            appearance: appearance,
            dockVisibility: dockVisibility
        )
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Markdown Preview Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 430, height: 290))
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
    }
}

private struct SettingsView: View {
    @ObservedObject var fontScale: FontScaleController
    @ObservedObject var appearance: AppearanceController
    @ObservedObject var dockVisibility: DockVisibilityController

    var body: some View {
        Form {
            LabeledContent("Appearance") {
                Picker(
                    "Appearance",
                    selection: Binding(
                        get: { appearance.selection },
                        set: { appearance.setAppearance($0) }
                    )
                ) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 230)
            }

            LabeledContent("Markdown text size") {
                HStack(spacing: 12) {
                    Button {
                        fontScale.decreaseFontSize(nil)
                    } label: {
                        Image(systemName: "textformat.size.smaller")
                    }
                    .help("Decrease Markdown text size")

                    Slider(
                        value: Binding(
                            get: { Double(fontScale.scale) },
                            set: { fontScale.setScale(CGFloat($0)) }
                        ),
                        in: Double(MarkdownRenderOptions.minimumScale)...Double(MarkdownRenderOptions.maximumScale),
                        step: 0.05
                    )
                    .frame(width: 170)

                    Button {
                        fontScale.increaseFontSize(nil)
                    } label: {
                        Image(systemName: "textformat.size.larger")
                    }
                    .help("Increase Markdown text size")

                    Text(fontScale.percentageLabel)
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }
            }

            LabeledContent("Dock") {
                Toggle(
                    "Show application icon",
                    isOn: Binding(
                        get: { dockVisibility.showsDockItem },
                        set: { dockVisibility.setShowsDockItem($0) }
                    )
                )
                .toggleStyle(.switch)
            }

            HStack {
                Spacer()
                Button("Reset") { fontScale.resetFontSize(nil) }
            }
        }
        .formStyle(.grouped)
        .padding(8)
        .frame(minWidth: 410, minHeight: 270)
    }
}
