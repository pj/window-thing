import Foundation
import CoreGraphics

public struct WindowFrame: Codable, Equatable, Sendable {
    public var x: CGFloat
    public var y: CGFloat
    public var width: CGFloat
    public var height: CGFloat

    public var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    public init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(from rect: CGRect) {
        self.x = rect.origin.x
        self.y = rect.origin.y
        self.width = rect.size.width
        self.height = rect.size.height
    }
}

public struct Window: Identifiable, Equatable, Sendable {
    public let id: CGWindowID
    public let title: String
    public let application: String
    public let bundleId: String?
    public var frame: WindowFrame
    public let pid: pid_t

    public init(id: CGWindowID, title: String, application: String, bundleId: String?, frame: WindowFrame, pid: pid_t) {
        self.id = id
        self.title = title
        self.application = application
        self.bundleId = bundleId
        self.frame = frame
        self.pid = pid
    }

    public static func == (lhs: Window, rhs: Window) -> Bool {
        lhs.id == rhs.id
    }
}

public struct Display: Identifiable, Codable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let frame: WindowFrame
    public let isMain: Bool

    public var displayName: String {
        name.isEmpty ? "Display \(id)" : name
    }

    public init(id: Int, name: String, frame: WindowFrame, isMain: Bool) {
        self.id = id
        self.name = name
        self.frame = frame
        self.isMain = isMain
    }
}

public struct Application: Identifiable, Equatable, Sendable {
    public let id: pid_t
    public let name: String
    public let bundleId: String?
    public var focusedWindow: Window?

    public init(id: pid_t, name: String, bundleId: String?, focusedWindow: Window? = nil) {
        self.id = id
        self.name = name
        self.bundleId = bundleId
        self.focusedWindow = focusedWindow
    }
}
