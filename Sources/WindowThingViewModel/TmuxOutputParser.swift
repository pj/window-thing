import Foundation
import WindowThingCore

/// Pure parsing functions for tmux command output.
public enum TmuxOutputParser {

    // MARK: - Pane Listing

    /// Parse `tmux list-panes -F '#{pane_index}\t#{pane_width}\t#{pane_height}\t#{pane_active}\t#{pane_title}\t#{pane_id}'`
    public static func parsePaneListing(_ output: String) -> [SubPane] {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: true)
        var panes: [SubPane] = []
        for (i, line) in lines.enumerated() {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 5 else { continue }
            let isActive = fields[3] == "1"
            let title = String(fields[4])
            panes.append(SubPane(
                index: i + 1,  // 1-based for AppDriver convention
                title: title.isEmpty ? nil : title,
                isFocused: isActive
            ))
        }
        return panes
    }

    /// Extract the 1-based focused pane index from parsed panes.
    public static func focusedIndex(from panes: [SubPane]) -> Int? {
        panes.first(where: { $0.isFocused })?.index
    }

    // MARK: - Window Dimensions

    /// Parse `tmux display-message -p '#{window_width}\t#{window_height}'`
    public static func parseWindowDimensions(_ output: String) -> (width: Int, height: Int)? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "\t")
        guard parts.count == 2,
              let w = Int(parts[0]),
              let h = Int(parts[1]) else { return nil }
        return (w, h)
    }

    // MARK: - Layout String Parsing

    /// Parse tmux layout string into a LayoutNode tree.
    ///
    /// tmux layout format examples:
    /// - Single pane: `a]b0,200x60,0,0,0`
    /// - Two columns: `6a42,200x60,0,0{100x60,0,0,0,99x60,101,0,1}`
    /// - Two rows: `d3a0,200x60,0,0[200x30,0,0,0,200x29,0,31,1]`
    /// - Nested: `{100x60,0,0[100x30,0,0,0,100x29,0,31,1],99x60,101,0,2}`
    ///
    /// Structure: `checksum,WxH,X,Y` followed by either:
    /// - `,pane_id` (leaf)
    /// - `{child,child,...}` (horizontal/columns split)
    /// - `[child,child,...]` (vertical/rows split)
    public static func parseLayoutString(_ layout: String) -> LayoutNode? {
        var s = layout[...]

        // Strip optional "xxxx]" prefix (some tmux versions)
        if let bracket = s.firstIndex(of: "]") {
            let beforeBracket = s[s.startIndex..<bracket]
            // Only strip if everything before ] is hex-like (part of checksum)
            if beforeBracket.allSatisfy({ $0.isHexDigit }) {
                s = s[s.index(after: bracket)...]
            }
        }

        // Strip leading checksum: hex characters followed by comma, before WxH
        // Format: "xxxx,WxH,X,Y,..." — skip to after the first comma
        guard let firstComma = s.firstIndex(of: ",") else { return nil }
        let prefix = s[s.startIndex..<firstComma]
        // If the prefix doesn't contain 'x', it's a checksum — skip it
        if !prefix.contains("x") {
            s = s[s.index(after: firstComma)...]
        }
        // Otherwise the string already starts at WxH

        return parseNode(&s)?.node
    }

    // MARK: - Recursive Parser

    private struct ParsedNode {
        let node: LayoutNode
        let width: Int
        let height: Int
    }

    /// Parse a single node from the layout string, advancing the substring.
    private static func parseNode(_ s: inout Substring) -> ParsedNode? {
        // Parse dimensions: WxH,X,Y
        guard let dims = parseDimensions(&s) else { return nil }

        // Check what follows: '{' (columns), '[' (rows), ',' + pane_id (leaf)
        if s.first == "{" {
            // Columns (horizontal split)
            s = s.dropFirst() // skip '{'
            var children: [ParsedNode] = []
            while !s.isEmpty && s.first != "}" {
                if s.first == "," { s = s.dropFirst() }
                guard let child = parseNode(&s) else { break }
                children.append(child)
            }
            if s.first == "}" { s = s.dropFirst() }
            let totalWidth = children.reduce(0) { $0 + $1.width }
            let cols = children.map { child -> LayoutNode in
                let pct = totalWidth > 0 ? (Double(child.width) / Double(totalWidth)) * 100.0 : 100.0 / Double(children.count)
                return child.node.type == .empty
                    ? .empty(percentage: pct)
                    : withPercentage(child.node, pct)
            }
            return ParsedNode(node: .columns(cols), width: dims.width, height: dims.height)

        } else if s.first == "[" {
            // Rows (vertical split)
            s = s.dropFirst() // skip '['
            var children: [ParsedNode] = []
            while !s.isEmpty && s.first != "]" {
                if s.first == "," { s = s.dropFirst() }
                guard let child = parseNode(&s) else { break }
                children.append(child)
            }
            if s.first == "]" { s = s.dropFirst() }
            let totalHeight = children.reduce(0) { $0 + $1.height }
            let rows = children.map { child -> LayoutNode in
                let pct = totalHeight > 0 ? (Double(child.height) / Double(totalHeight)) * 100.0 : 100.0 / Double(children.count)
                return child.node.type == .empty
                    ? .empty(percentage: pct)
                    : withPercentage(child.node, pct)
            }
            return ParsedNode(node: .rows(rows), width: dims.width, height: dims.height)

        } else {
            // Leaf: consume ,pane_id
            if s.first == "," {
                s = s.dropFirst()
                // Skip pane_id (digits)
                while !s.isEmpty && s.first!.isWholeNumber { s = s.dropFirst() }
            }
            return ParsedNode(node: .empty(percentage: 100), width: dims.width, height: dims.height)
        }
    }

    private struct Dimensions {
        let width: Int
        let height: Int
        let x: Int
        let y: Int
    }

    /// Parse `WxH,X,Y` from the front of the substring.
    private static func parseDimensions(_ s: inout Substring) -> Dimensions? {
        // Expect: WxH,X,Y
        guard let xIdx = s.firstIndex(of: "x") else { return nil }
        guard let w = Int(s[s.startIndex..<xIdx]) else { return nil }
        s = s[s.index(after: xIdx)...]

        guard let comma1 = s.firstIndex(of: ",") else { return nil }
        guard let h = Int(s[s.startIndex..<comma1]) else { return nil }
        s = s[s.index(after: comma1)...]

        guard let comma2 = s.firstIndex(of: ",") else { return nil }
        guard let x = Int(s[s.startIndex..<comma2]) else { return nil }
        s = s[s.index(after: comma2)...]

        // Y ends at next comma, bracket, or end
        let yEnd = s.firstIndex(where: { $0 == "," || $0 == "{" || $0 == "[" || $0 == "}" || $0 == "]" }) ?? s.endIndex
        guard let y = Int(s[s.startIndex..<yEnd]) else { return nil }
        s = s[yEnd...]

        return Dimensions(width: w, height: h, x: x, y: y)
    }

    private static func withPercentage(_ node: LayoutNode, _ pct: Double) -> LayoutNode {
        LayoutNode(
            type: node.type,
            percentage: pct,
            pinned: node.pinned,
            columns: node.columns,
            rows: node.rows,
            windows: node.windows,
            stackRemaining: node.stackRemaining,
            layout: node.layout?.value,
            floats: node.floats,
            zoomed: node.zoomed
        )
    }
}
