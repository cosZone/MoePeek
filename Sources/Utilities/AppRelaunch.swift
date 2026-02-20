import AppKit

enum AppRelaunch {
    @MainActor
    static func relaunch() {
        let bundlePath = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", "sleep 0.3; open \"\(bundlePath)\""]
        try? task.run()
        NSApplication.shared.terminate(nil)
    }
}
