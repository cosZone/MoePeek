import Foundation
import Testing
@testable import MoePeek

@MainActor
@Suite struct OpenAIConnectionManagerTests {
    @Test func requestyConnectionAcceptsModelsWithMinimumTokenBudget() async {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let manager = OpenAIConnectionManager(session: session)

        await manager.testConnection(
            baseURL: "https://router.requesty.ai/v1",
            apiKey: "test-key",
            model: "openai/gpt-4o-mini"
        )

        guard case .success = manager.testResult else {
            Issue.record("A valid Requesty configuration failed: \(String(describing: manager.testResult))")
            return
        }
        #expect(!manager.isTestingConnection)
    }

    @Test func requestyAuthenticationFailureRemainsVisible() async {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let manager = OpenAIConnectionManager(session: session)

        await manager.testConnection(
            baseURL: "https://router.requesty.ai/v1",
            apiKey: "invalid-test-key",
            model: "openai/gpt-4o-mini"
        )

        #expect(manager.testResult == .failure(message: "HTTP 401: Invalid API key"))
        #expect(!manager.isTestingConnection)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RequestyTestURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class RequestyTestURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with _: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let url = try #require(request.url)
            #expect(url.absoluteString == "https://router.requesty.ai/v1/chat/completions")
            #expect(request.httpMethod == "POST")
            let bodyData: Data
            if let data = request.httpBody {
                bodyData = data
            } else {
                let stream = try #require(request.httpBodyStream)
                stream.open()
                defer { stream.close() }
                var data = Data()
                var buffer = [UInt8](repeating: 0, count: 1024)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    guard count > 0 else { break }
                    data.append(contentsOf: buffer.prefix(count))
                }
                bodyData = data
            }
            let body = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
            #expect(body["model"] as? String == "openai/gpt-4o-mini")
            #expect(body["stream"] as? Bool == false)
            let maxTokens = try #require(body["max_tokens"] as? Int)

            let status: Int
            let responseBody: String
            if request.value(forHTTPHeaderField: "Authorization") != "Bearer test-key" {
                status = 401
                responseBody = #"{"error":{"message":"Invalid API key"}}"#
            } else if maxTokens < 16 {
                status = 400
                responseBody = #"{"error":{"message":"max_tokens must be at least 16"}}"#
            } else {
                status = 200
                responseBody = #"{"choices":[{"message":{"content":"Hi!"}}]}"#
            }
            let response = try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(responseBody.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
