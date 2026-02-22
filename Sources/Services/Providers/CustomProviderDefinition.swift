import Defaults
import Foundation

struct CustomProviderDefinition: Codable, Hashable, Defaults.Serializable {
    let id: String
    var name: String
    var defaultBaseURL: String
    var defaultModel: String

    init(name: String, defaultBaseURL: String, defaultModel: String) {
        self.id = "custom_\(UUID().uuidString.lowercased())"
        self.name = name
        self.defaultBaseURL = defaultBaseURL
        self.defaultModel = defaultModel
    }
}
