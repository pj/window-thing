import AppKit
import Foundation

/// Application icons, looked up once instead of on every render.
///
/// Resolving an icon means asking Launch Services where an app lives and then
/// reading the icon out of its bundle — measured at about 3ms a time. The window
/// choosers show every running application in every pane, so a single pass of
/// the render loop was doing dozens of those: roughly 220ms for 23 apps across
/// three panes, on the main thread, every time anything in the overlay changed.
///
/// Icons do not meaningfully change while the app is running, so they are held
/// for the lifetime of the process. Failed lookups are remembered too — an app
/// that has no icon to find is otherwise re-searched just as expensively on
/// every pass.
public final class AppIconCache {

    public static let shared = AppIconCache()

    /// `NSImage?` values, so a miss is cached as emphatically as a hit.
    private var byBundleId: [String: NSImage?] = [:]
    private var byName: [String: NSImage?] = [:]
    private var byPID: [pid_t: NSImage?] = [:]

    private let lock = NSLock()

    /// How many lookups actually reached Launch Services. Everything else was a
    /// cache hit; tests assert on this because the whole point is the count.
    private(set) var resolutions = 0

    private var terminationObserver: NSObjectProtocol?

    public init(observingTermination: Bool = true) {
        guard observingTermination else { return }
        // Process ids are reused, so an entry for a dead app could otherwise be
        // handed out for whatever launches next.
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication else { return }
            self?.forget(pid: app.processIdentifier)
        }
    }

    deinit {
        if let terminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(terminationObserver)
        }
    }

    /// The icon for an application identified by bundle id, falling back to a
    /// match on its displayed name.
    public func icon(bundleId: String?, appName: String) -> NSImage? {
        if let bundleId {
            lock.lock()
            if let cached = byBundleId[bundleId] {
                lock.unlock()
                return cached
            }
            lock.unlock()

            // Outside the lock: this is the slow part, and holding a lock across
            // it would serialise every other caller behind it.
            let resolved = NSWorkspace.shared
                .urlForApplication(withBundleIdentifier: bundleId)
                .map { NSWorkspace.shared.icon(forFile: $0.path) }

            lock.lock()
            byBundleId[bundleId] = resolved
            resolutions += 1
            lock.unlock()

            if let resolved { return resolved }
        }

        lock.lock()
        if let cached = byName[appName] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let resolved = NSWorkspace.shared.runningApplications
            .first { $0.localizedName == appName }?.icon

        lock.lock()
        byName[appName] = resolved
        resolutions += 1
        lock.unlock()

        return resolved
    }

    /// The icon for a running process.
    public func icon(pid: pid_t) -> NSImage? {
        lock.lock()
        if let cached = byPID[pid] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let resolved = NSRunningApplication(processIdentifier: pid)?.icon

        lock.lock()
        byPID[pid] = resolved
        resolutions += 1
        lock.unlock()

        return resolved
    }

    /// Forget everything. Process ids are reused, so a long-lived cache could
    /// otherwise show a dead app's icon for a new one.
    public func clear() {
        lock.lock()
        byBundleId.removeAll()
        byName.removeAll()
        byPID.removeAll()
        lock.unlock()
    }

    /// Drop icons for processes that are no longer running, which is the only
    /// entry that can go stale within a session.
    public func forget(pid: pid_t) {
        lock.lock()
        byPID[pid] = nil
        lock.unlock()
    }
}
