import Foundation

/// Result of a shell command execution.
public struct ShellResult: Sendable, Equatable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32

    public init(stdout: String, stderr: String = "", exitCode: Int32 = 0) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }

    public var succeeded: Bool { exitCode == 0 }
}

/// Protocol for executing shell commands. Real implementations run processes;
/// test implementations return canned responses.
public protocol ShellExecutor: Sendable {
    func run(_ command: String, arguments: [String]) async throws -> ShellResult
}
