import Foundation
import WindowThingCore

// MARK: - Tmux Target

/// Identifies a specific tmux session and window.
public struct TmuxTarget: Sendable, Equatable {
    public let session: String
    public let window: Int

    public var targetString: String { "\(session):\(window)" }

    public init(session: String, window: Int) {
        self.session = session
        self.window = window
    }

    /// Parse from "session:window" format.
    public init?(string: String) {
        let parts = string.split(separator: ":", maxSplits: 1)
        guard parts.count == 2,
              let w = Int(parts[1]) else { return nil }
        self.session = String(parts[0])
        self.window = w
    }
}

// MARK: - Errors

public enum TmuxError: Error, Equatable {
    case notRunning
    case sessionNotFound(String)
    case commandFailed(String)
    case parseError(String)
}

// MARK: - Tmux Driver

/// AppDriver implementation for tmux. Manages pane layouts within a tmux window
/// by executing tmux CLI commands through a ShellExecutor.
public final class TmuxDriver: AppDriver, @unchecked Sendable {
    public let driverType = "tmux"

    private let shell: ShellExecutor
    private let tmuxPath: String
    private let target: TmuxTarget

    public init(shell: ShellExecutor, target: TmuxTarget, tmuxPath: String = "/usr/bin/tmux") {
        self.shell = shell
        self.target = target
        self.tmuxPath = tmuxPath
    }

    /// Create a driver from a SublayoutConfig target string, falling back to the first active session.
    public convenience init(shell: ShellExecutor, targetString: String?, tmuxPath: String = "/usr/bin/tmux") async throws {
        if let ts = targetString, let t = TmuxTarget(string: ts) {
            self.init(shell: shell, target: t, tmuxPath: tmuxPath)
        } else {
            // Auto-detect: use first session, window 0
            let result = try await shell.run(tmuxPath, arguments: ["list-sessions", "-F", "#{session_name}"])
            guard result.succeeded else { throw TmuxError.notRunning }
            let sessions = result.stdout.split(separator: "\n", omittingEmptySubsequences: true)
            guard let first = sessions.first else { throw TmuxError.notRunning }
            self.init(shell: shell, target: TmuxTarget(session: String(first), window: 0), tmuxPath: tmuxPath)
        }
    }

    // MARK: - AppDriver

    public func queryPaneState() async throws -> AppPaneState {
        // Get pane listing
        let listResult = try await tmux(
            "list-panes", "-t", target.targetString,
            "-F", "#{pane_index}\t#{pane_width}\t#{pane_height}\t#{pane_active}\t#{pane_title}\t#{pane_id}"
        )
        guard listResult.succeeded else {
            if listResult.stderr.contains("session not found") {
                throw TmuxError.sessionNotFound(target.session)
            }
            throw TmuxError.commandFailed(listResult.stderr)
        }
        let panes = TmuxOutputParser.parsePaneListing(listResult.stdout)

        // Get layout string
        let layoutResult = try await tmux(
            "display-message", "-t", target.targetString, "-p", "#{window_layout}"
        )
        let layout: LayoutNode
        if layoutResult.succeeded,
           let parsed = TmuxOutputParser.parseLayoutString(layoutResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) {
            layout = parsed
        } else {
            // Fallback: single pane
            layout = .empty()
        }

        return AppPaneState(
            layout: layout,
            panes: panes,
            focusedIndex: TmuxOutputParser.focusedIndex(from: panes)
        )
    }

    public func applySublayout(_ layout: LayoutNode) async throws {
        // Get current state to check if rebuild is needed
        let current = try await queryPaneState()
        if current.layout == layout { return }

        // Get current pane IDs
        let paneIdsResult = try await tmux(
            "list-panes", "-t", target.targetString, "-F", "#{pane_id}"
        )
        guard paneIdsResult.succeeded else {
            throw TmuxError.commandFailed(paneIdsResult.stderr)
        }
        let paneIds = paneIdsResult.stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)

        // Kill all panes except the first
        for paneId in paneIds.dropFirst().reversed() {
            _ = try await tmux("kill-pane", "-t", paneId)
        }

        // Get window dimensions for percentage calculations
        let dimsResult = try await tmux(
            "display-message", "-t", target.targetString, "-p", "#{window_width}\t#{window_height}"
        )
        guard dimsResult.succeeded,
              let dims = TmuxOutputParser.parseWindowDimensions(dimsResult.stdout) else {
            throw TmuxError.parseError("Could not get window dimensions")
        }

        // Build the layout starting from the surviving pane
        guard let firstPaneId = paneIds.first else {
            throw TmuxError.commandFailed("No panes found")
        }
        try await buildLayout(node: layout, targetPaneId: firstPaneId, width: dims.width, height: dims.height)
    }

    public func focusPane(at index: Int) async throws {
        let tmuxIndex = index - 1  // Convert 1-based to 0-based
        let result = try await tmux("select-pane", "-t", "\(target.targetString).\(tmuxIndex)")
        guard result.succeeded else {
            throw TmuxError.commandFailed(result.stderr)
        }
    }

    public func focusedPaneIndex() async throws -> Int? {
        let state = try await queryPaneState()
        return state.focusedIndex
    }

    // MARK: - Layout Building

    private func buildLayout(node: LayoutNode, targetPaneId: String, width: Int, height: Int) async throws {
        switch node.type {
        case .columns:
            guard let cols = node.columns, cols.count > 1 else { return }
            try await buildSplitLayout(
                children: cols,
                targetPaneId: targetPaneId,
                totalSize: width,
                isHorizontal: true
            )

        case .rows:
            guard let rows = node.rows, rows.count > 1 else { return }
            try await buildSplitLayout(
                children: rows,
                targetPaneId: targetPaneId,
                totalSize: height,
                isHorizontal: false
            )

        default:
            break  // Leaf node, nothing to do
        }
    }

    private func buildSplitLayout(
        children: [LayoutNode],
        targetPaneId: String,
        totalSize: Int,
        isHorizontal: Bool
    ) async throws {
        let flag = isHorizontal ? "-h" : "-v"
        var paneIds = [targetPaneId]

        // Calculate sizes for each child
        let totalPct = children.reduce(0.0) { $0 + ($1.percentage ?? (100.0 / Double(children.count))) }
        var sizes: [Int] = children.map { child in
            let pct = child.percentage ?? (100.0 / Double(children.count))
            return Int(Double(totalSize) * pct / totalPct)
        }
        // Adjust last size to account for rounding
        let allocated = sizes.dropLast().reduce(0, +)
        sizes[sizes.count - 1] = totalSize - allocated

        // Split to create additional panes (first child uses the existing pane)
        for i in 1..<children.count {
            // Calculate the remaining size for the split percentage
            let remainingSize = sizes[i..<sizes.count].reduce(0, +)
            let splitSize = sizes[i]
            let splitPct = remainingSize > 0 ? Int((Double(splitSize) / Double(remainingSize)) * 100) : 50

            let splitResult = try await tmux(
                "split-window", flag,
                "-t", paneIds[i - 1],
                "-l", "\(splitPct)%",
                "-d",  // Don't switch focus
                "-PF", "#{pane_id}"
            )
            guard splitResult.succeeded else {
                throw TmuxError.commandFailed(splitResult.stderr)
            }
            let newPaneId = splitResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            paneIds.append(newPaneId)
        }

        // Resize panes to exact sizes
        let sizeFlag = isHorizontal ? "-x" : "-y"
        for (i, paneId) in paneIds.enumerated() {
            _ = try await tmux("resize-pane", "-t", paneId, sizeFlag, "\(sizes[i])")
        }

        // Recurse into children that have nested structure
        for (i, child) in children.enumerated() {
            if child.type == .columns || child.type == .rows {
                let childWidth = isHorizontal ? sizes[i] : totalSize
                let childHeight = isHorizontal ? totalSize : sizes[i]
                try await buildLayout(
                    node: child,
                    targetPaneId: paneIds[i],
                    width: childWidth,
                    height: childHeight
                )
            }
        }
    }

    // MARK: - Helpers

    private func tmux(_ args: String...) async throws -> ShellResult {
        try await shell.run(tmuxPath, arguments: args)
    }
}
