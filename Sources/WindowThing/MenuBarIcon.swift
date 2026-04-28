import AppKit
import WindowThingCore

extension NSImage {
    /// Creates a menubar icon that looks like a widescreen display with two windows
    static func menuBarIcon(size: NSSize = NSSize(width: 18, height: 18)) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let padding: CGFloat = 1.5
            let screenRect = rect.insetBy(dx: padding, dy: padding + 1)

            // Monitor dimensions - widescreen aspect ratio
            let monitorWidth = screenRect.width
            let monitorHeight = screenRect.height * 0.75
            let monitorY = screenRect.minY + (screenRect.height - monitorHeight) * 0.55

            // Screen bezel (outer frame of monitor)
            let bezelRadius: CGFloat = 1.5
            let bezelRect = NSRect(
                x: screenRect.minX,
                y: monitorY,
                width: monitorWidth,
                height: monitorHeight
            )
            let bezelPath = NSBezierPath(roundedRect: bezelRect, xRadius: bezelRadius, yRadius: bezelRadius)
            bezelPath.lineWidth = 1.2
            bezelPath.stroke()

            // Inner screen area
            let screenInset: CGFloat = 2.0
            let innerScreenRect = bezelRect.insetBy(dx: screenInset, dy: screenInset)

            // Simple vertical split line down the middle
            let splitPath = NSBezierPath()
            splitPath.move(to: NSPoint(x: innerScreenRect.midX, y: innerScreenRect.minY))
            splitPath.line(to: NSPoint(x: innerScreenRect.midX, y: innerScreenRect.maxY))
            splitPath.lineWidth = 0.9
            splitPath.stroke()

            // Base - just a horizontal line below the monitor
            let baseWidth: CGFloat = monitorWidth * 0.65
            let baseY = monitorY - 3.0
            let basePath = NSBezierPath()
            basePath.move(to: NSPoint(x: bezelRect.midX - baseWidth/2, y: baseY))
            basePath.line(to: NSPoint(x: bezelRect.midX + baseWidth/2, y: baseY))
            basePath.lineWidth = 1.2
            basePath.stroke()

            return true
        }

        image.isTemplate = true
        return image
    }

    /// Creates a menubar icon with a more detailed split pattern
    static func menuBarIconWithColumns(size: NSSize = NSSize(width: 18, height: 18)) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let padding: CGFloat = 1.5
            let screenRect = rect.insetBy(dx: padding, dy: padding + 1)

            // Monitor dimensions
            let monitorWidth = screenRect.width
            let monitorHeight = screenRect.height * 0.75
            let monitorY = screenRect.minY + (screenRect.height - monitorHeight) * 0.6

            // Screen bezel
            let bezelRadius: CGFloat = 1.5
            let bezelRect = NSRect(
                x: screenRect.minX,
                y: monitorY,
                width: monitorWidth,
                height: monitorHeight
            )
            let bezelPath = NSBezierPath(roundedRect: bezelRect, xRadius: bezelRadius, yRadius: bezelRadius)
            bezelPath.lineWidth = 1.2
            bezelPath.stroke()

            // Inner screen area
            let screenInset: CGFloat = 1.8
            let innerScreenRect = bezelRect.insetBy(dx: screenInset, dy: screenInset)

            // Draw two split lines (thirds layout)
            let thirdWidth = innerScreenRect.width / 3
            for i in 1...2 {
                let x = innerScreenRect.minX + thirdWidth * CGFloat(i)
                let splitPath = NSBezierPath()
                splitPath.move(to: NSPoint(x: x, y: innerScreenRect.minY))
                splitPath.line(to: NSPoint(x: x, y: innerScreenRect.maxY))
                splitPath.lineWidth = 0.8
                splitPath.stroke()
            }

            // Monitor stand
            let standWidth: CGFloat = monitorWidth * 0.25
            let standHeight: CGFloat = 2.5
            let standPath = NSBezierPath()

            let standTop = monitorY
            let standBottom = standTop - standHeight
            let standCenterX = bezelRect.midX

            standPath.move(to: NSPoint(x: standCenterX - standWidth/2 + 1, y: standTop))
            standPath.line(to: NSPoint(x: standCenterX - standWidth/2, y: standBottom))
            standPath.line(to: NSPoint(x: standCenterX + standWidth/2, y: standBottom))
            standPath.line(to: NSPoint(x: standCenterX + standWidth/2 - 1, y: standTop))
            standPath.lineWidth = 1.0
            standPath.stroke()

            // Base
            let baseWidth: CGFloat = monitorWidth * 0.45
            let baseHeight: CGFloat = 1.5
            let baseRect = NSRect(
                x: standCenterX - baseWidth/2,
                y: standBottom - baseHeight,
                width: baseWidth,
                height: baseHeight
            )
            let basePath = NSBezierPath(roundedRect: baseRect, xRadius: 0.5, yRadius: 0.5)
            basePath.fill()

            return true
        }

        image.isTemplate = true
        return image
    }

    /// Creates a menu item icon representing a layout structure
    /// The icon shows a simplified view of how windows are arranged
    static func layoutIcon(for layout: Layout, displays: [Display], size: NSSize = NSSize(width: 16, height: 16)) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let padding: CGFloat = 1.0
            let screenRect = rect.insetBy(dx: padding, dy: padding)

            // Draw the monitor outline
            let bezelPath = NSBezierPath(roundedRect: screenRect, xRadius: 1.5, yRadius: 1.5)
            bezelPath.lineWidth = 1.0
            bezelPath.stroke()

            // Get the primary display's layout
            guard let screenSet = layout.screenSets.first,
                  let primaryLayout = screenSet.layouts[ScreenConfig.primaryKey] else {
                return true
            }

            // Inner area for drawing splits
            let innerRect = screenRect.insetBy(dx: 2.0, dy: 2.0)

            // Draw the layout structure
            drawLayoutNode(primaryLayout, in: innerRect)

            return true
        }

        image.isTemplate = true
        return image
    }

    /// Recursively draws a layout node structure
    private static func drawLayoutNode(_ node: LayoutNode, in rect: NSRect) {
        switch node.type {
        case .columns:
            if let children = node.columns {
                drawColumns(children, in: rect)
            }
        case .rows:
            if let children = node.rows {
                drawRows(children, in: rect)
            }
        case .pinned, .empty, .stack, .floatZoomed:
            // Single cell or unsupported types, nothing to draw inside
            break
        }
    }

    private static func drawColumns(_ children: [LayoutNode], in rect: NSRect) {
        guard children.count > 1, rect.width > 1, rect.height > 1 else { return }

        let defaultP = 100.0 / CGFloat(children.count)
        let total = children.reduce(CGFloat(0)) { $0 + CGFloat($1.percentage ?? Double(defaultP)) }
        guard total > 0 else { return }

        var x = rect.minX
        for (index, child) in children.enumerated() {
            let percentage = CGFloat(child.percentage ?? Double(defaultP))
            let width = rect.width * (percentage / total)

            if index > 0 {
                let separatorPath = NSBezierPath()
                separatorPath.move(to: NSPoint(x: x, y: rect.minY))
                separatorPath.line(to: NSPoint(x: x, y: rect.maxY))
                separatorPath.lineWidth = 0.8
                separatorPath.stroke()
            }

            if width > 2 {
                let columnRect = NSRect(x: x, y: rect.minY, width: width, height: rect.height)
                drawLayoutNode(child, in: columnRect.insetBy(dx: 0.5, dy: 0))
            }

            x += width
        }
    }

    private static func drawRows(_ children: [LayoutNode], in rect: NSRect) {
        guard children.count > 1, rect.width > 1, rect.height > 1 else { return }

        let defaultP = 100.0 / CGFloat(children.count)
        let total = children.reduce(CGFloat(0)) { $0 + CGFloat($1.percentage ?? Double(defaultP)) }
        guard total > 0 else { return }

        var y = rect.maxY
        for (index, child) in children.enumerated() {
            let percentage = CGFloat(child.percentage ?? Double(defaultP))
            let height = rect.height * (percentage / total)

            if index > 0 {
                let separatorPath = NSBezierPath()
                separatorPath.move(to: NSPoint(x: rect.minX, y: y))
                separatorPath.line(to: NSPoint(x: rect.maxX, y: y))
                separatorPath.lineWidth = 0.8
                separatorPath.stroke()
            }

            if height > 2 {
                let rowRect = NSRect(x: rect.minX, y: y - height, width: rect.width, height: height)
                drawLayoutNode(child, in: rowRect.insetBy(dx: 0, dy: 0.5))
            }

            y -= height
        }
    }
}
