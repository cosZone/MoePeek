import AppKit
import Foundation
import MoePeekOCRCore

struct WorkerResponse: Codable {
    var text: String
    var duration: TimeInterval
}

private enum Environment {
    static var keys: Set<String> {
        Set(ProcessInfo.processInfo.environment.keys)
    }
}

@main
enum OCRWorkerMain {
    static func main() async {
        let warmup = Environment.keys.contains("MOEPEEK_OCR_WARMUP")
        let recognitionTimeout: TimeInterval = warmup ? 40 : 5
        let arguments = CommandLine.arguments
        guard arguments.count == 2 else {
            FileHandle.standardError.write("usage: MoePeekOCRWorker <image-path>\n".data(using: .utf8)!)
            exit(64)
        }

        let imageURL = URL(fileURLWithPath: arguments[1])
        guard let image = NSImage(contentsOf: imageURL),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            FileHandle.standardError.write("invalid-image\n".data(using: .utf8)!)
            exit(65)
        }

        let started = Date()
        do {
            let text = try await AppleOCREngine.recognizeText(
                in: cgImage,
                recognitionTimeout: recognitionTimeout
            )
            let response = WorkerResponse(text: text, duration: Date().timeIntervalSince(started))
            let encoded = try JSONEncoder().encode(response)
            FileHandle.standardOutput.write(encoded)
        } catch {
            FileHandle.standardError.write("\(error)\n".data(using: .utf8)!)
            exit(1)
        }
    }
}
