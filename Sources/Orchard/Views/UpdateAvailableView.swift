import AppKit
import SwiftUI

/// What the user picked in the update window.
enum UpdateChoice {
    case install
    case later
    case skip
}

/// The "Update Available" window: icon, one line on what's new, and the three choices in a row.
struct UpdateAvailableView: View {
    let newVersion: String
    let currentVersion: String?
    let canInstall: Bool
    let busy: Bool
    let releaseNotes: URL
    let choose: (UpdateChoice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Orchard \(newVersion) is available")
                        .font(.title3.weight(.semibold))
                    Text(detail)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Link("Release Notes", destination: releaseNotes)
                        .padding(.top, 2)
                }
            }
            HStack {
                Button("Skip This Version") { choose(.skip) }
                Spacer()
                Button("Later") { choose(.later) }
                    .keyboardShortcut(.cancelAction)
                Button(canInstall ? "Install and Relaunch" : "Download…") { choose(.install) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
        }
        .padding(24)
        .frame(width: 460)
    }

    private var detail: String {
        var text = currentVersion.map { "You have \($0)." } ?? ""
        if !canInstall {
            text += " Orchard can't replace itself where it's installed, so download it instead."
        } else if busy {
            text += " Installing stops the build that's running."
        }
        return text.trimmingCharacters(in: .whitespaces)
    }
}

/// Shows `UpdateAvailableView` in a small, non-modal window. Closing it counts as "Later".
@MainActor
final class UpdateWindow: NSObject, NSWindowDelegate {
    private static var open: UpdateWindow?
    private let window: NSWindow
    private var completion: ((UpdateChoice) -> Void)?

    private init(_ makeView: (@escaping (UpdateChoice) -> Void) -> UpdateAvailableView,
                 completion: @escaping (UpdateChoice) -> Void) {
        window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable],
                          backing: .buffered, defer: false)
        self.completion = completion
        super.init()
        let view = makeView { [weak self] choice in self?.finish(choice) }
        window.contentViewController = NSHostingController(rootView: view)
        window.title = "Software Update"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.delegate = self
    }

    static func show(_ makeView: (@escaping (UpdateChoice) -> Void) -> UpdateAvailableView,
                     completion: @escaping (UpdateChoice) -> Void) {
        let presenter = UpdateWindow(makeView, completion: completion)
        open = presenter
        presenter.window.center()
        presenter.window.level = .floating
        NSApp.activate()
        presenter.window.makeKeyAndOrderFront(nil)
    }

    private func finish(_ choice: UpdateChoice) {
        guard let completion else { return }
        self.completion = nil
        window.close()
        Self.open = nil
        completion(choice)
    }

    func windowWillClose(_ notification: Notification) { finish(.later) }
}
