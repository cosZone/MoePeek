import Darwin
import Foundation
import ImageIO

struct WorkerResponse: Codable {
    var text: String
    var duration: TimeInterval
}

@main
enum OCRWorkerMain {
    static func main() async {
        // Do not leave a model-loading helper behind when the app quits or crashes.
        let parentPID = getppid()
        guard parentPID > 1 else { exit(1) }
        let parentMonitor = DispatchSource.makeProcessSource(
            identifier: parentPID, eventMask: .exit, queue: .global(qos: .utility)
        )
        parentMonitor.setEventHandler { exit(1) }
        parentMonitor.activate()
        defer { parentMonitor.cancel() }

        let arguments = CommandLine.arguments
        guard arguments.count == 2 else {
            FileHandle.standardError.write("usage: MoePeekOCRWorker <image-path>\n".data(using: .utf8)!)
            exit(64)
        }

        let imageURL = URL(fileURLWithPath: arguments[1])
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            FileHandle.standardError.write("invalid-image\n".data(using: .utf8)!)
            exit(65)
        }

        let started = Date()
        do {
            // A cold system may compile models for tens of seconds. Let it finish once;
            // the parent enforces the deadline by terminating this isolated process.
            let text = try await AppleOCREngine.recognizeText(in: cgImage)
            let response = WorkerResponse(text: text, duration: Date().timeIntervalSince(started))
            let encoded = try JSONEncoder().encode(response)
            FileHandle.standardOutput.write(encoded)
        } catch {
            FileHandle.standardError.write("\(error)\n".data(using: .utf8)!)
            exit(1)
        }
    }
}
