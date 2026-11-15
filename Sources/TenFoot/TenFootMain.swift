import AppKit

@main
@MainActor
enum TenFootMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        // NSApplication holds its delegate weakly; keep ours alive while the app runs.
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
