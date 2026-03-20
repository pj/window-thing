import Foundation

public struct RunningAppInfo: Codable, Identifiable, Hashable {
    public let name: String
    public let bundleId: String?
    public var id: String { bundleId ?? name }

    public init(name: String, bundleId: String?) {
        self.name = name
        self.bundleId = bundleId
    }
}
