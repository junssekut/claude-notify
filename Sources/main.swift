import Cocoa
import UserNotifications

let NOTIF_NAME = Notification.Name("com.claude.notify.send")
let BUNDLE_ID = "com.junskii.claudenotify"

/// Lock lives under Application Support, not /tmp. macOS reaps stale /tmp files,
/// and a missing lock file silently breaks single-instance detection: fcntl locks
/// are held on the inode, so once the path is gone a client recreates it, acquires
/// the lock on a fresh inode, and wrongly concludes no daemon is running.
let LOCK_FILE: String = {
    let dir = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/ClaudeNotify", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("daemon.lock").path
}()

// Single instance lock using file lock
class SingleInstance {
    private var fileDescriptor: Int32 = -1

    func tryLock() -> Bool {
        fileDescriptor = open(LOCK_FILE, O_CREAT | O_RDWR, 0o644)
        if fileDescriptor == -1 { return false }

        var lock = flock()
        lock.l_start = 0
        lock.l_len = 0
        lock.l_type = Int16(F_WRLCK)
        lock.l_whence = Int16(SEEK_SET)

        if fcntl(fileDescriptor, F_SETLK, &lock) == -1 {
            close(fileDescriptor)
            fileDescriptor = -1
            return false
        }

        // Write PID to file
        ftruncate(fileDescriptor, 0)
        let pid = "\(getpid())"
        write(fileDescriptor, pid, pid.count)

        return true
    }

    // Closing the descriptor releases the fcntl lock. The file itself is left in
    // place deliberately: unlinking it lets a later client recreate the path as a
    // new inode and take the lock while this daemon still holds the old one.
    func unlock() {
        if fileDescriptor != -1 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
    }

    deinit {
        unlock()
    }
}

let singleInstance = SingleInstance()

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var statusItem: NSStatusItem!
    var history: [(id: String, message: String, title: String, bundleId: String?)] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevent macOS from auto-terminating the app
        ProcessInfo.processInfo.disableAutomaticTermination("Menu bar daemon")

        setupMenuBar()
        setupNotificationCenter()
        listenForCommands()
    }

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if statusItem.button != nil {
            updateIcon(hasPending: false)
        }

        updateMenu()
    }

    func updateIcon(hasPending: Bool) {
        if let button = statusItem.button {
            let symbolName = hasPending ? "bubble.left.fill" : "bubble.left"
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Claude Notify")
            button.image?.isTemplate = true
        }
    }

    func updateMenu() {
        let menu = NSMenu()

        if history.isEmpty {
            let item = NSMenuItem(title: "No notifications", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            menu.addItem(NSMenuItem(title: "\(history.count) notification(s)", action: nil, keyEquivalent: ""))
            menu.addItem(NSMenuItem.separator())

            for notif in history.prefix(5) {
                let truncated = String(notif.message.prefix(40)) + (notif.message.count > 40 ? "..." : "")
                let item = NSMenuItem(title: truncated, action: #selector(openFromMenu(_:)), keyEquivalent: "")
                item.representedObject = notif
                item.target = self
                menu.addItem(item)
            }

            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Clear all", action: #selector(clearAll), keyEquivalent: "c"))
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    func updateBadge() {
        updateIcon(hasPending: !history.isEmpty)
        updateMenu()
    }

    @objc func openFromMenu(_ sender: NSMenuItem) {
        guard let notif = sender.representedObject as? (id: String, message: String, title: String, bundleId: String?) else { return }

        if let bundleId = notif.bundleId, !bundleId.isEmpty {
            openApp(bundleId: bundleId)
        }

        history.removeAll { $0.id == notif.id }
        updateBadge()
    }

    @objc func clearAll() {
        history.removeAll()
        updateBadge()
    }

    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }

    func listenForCommands() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleCommand(_:)),
            name: NOTIF_NAME,
            object: nil
        )
    }

    @objc func handleCommand(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let message = userInfo["message"] as? String else { return }

        let title = userInfo["title"] as? String ?? "Claude Code"
        let bundleId = userInfo["activate"] as? String
        let sound = userInfo["sound"] as? Bool ?? true

        let args = NotificationArgs(title: title, message: message, sound: sound, activate: bundleId)
        sendNotification(args: args)
    }

    func setupNotificationCenter() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification auth error: \(error)")
            }
        }
    }

    func sendNotification(args: NotificationArgs) {
        let content = UNMutableNotificationContent()
        content.title = args.title
        content.body = args.message
        content.sound = args.sound ? .default : nil
        content.userInfo = ["bundleId": args.activate ?? ""]

        let id = UUID().uuidString
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)

        history.insert((id: id, message: args.message, title: args.title, bundleId: args.activate), at: 0)
        DispatchQueue.main.async { self.updateBadge() }

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Notification error: \(error)")
            }
        }

        // Play sound directly (UNNotificationSound.default doesn't always work)
        if args.sound {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
            task.arguments = ["/System/Library/Sounds/Glass.aiff"]
            try? task.run()
        }
    }

    func openApp(bundleId: String) {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    // Show notification even when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    // Handle notification click
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let notifId = response.notification.request.identifier
        let userInfo = response.notification.request.content.userInfo

        if let index = history.firstIndex(where: { $0.id == notifId }) {
            let notif = history.remove(at: index)
            if let bundleId = notif.bundleId, !bundleId.isEmpty {
                openApp(bundleId: bundleId)
            }
            DispatchQueue.main.async { self.updateBadge() }
        } else if let bundleId = userInfo["bundleId"] as? String, !bundleId.isEmpty {
            openApp(bundleId: bundleId)
        }

        completionHandler()
    }
}

struct NotificationArgs {
    var title = "Claude Code"
    var message = ""
    var sound = true
    var activate: String?
}

// Send command to running daemon via DistributedNotificationCenter
func sendToDaemon(args: NotificationArgs) {
    var userInfo: [String: Any] = [
        "message": args.message,
        "title": args.title,
        "sound": args.sound
    ]
    if let activate = args.activate {
        userInfo["activate"] = activate
    }

    DistributedNotificationCenter.default().postNotificationName(
        NOTIF_NAME,
        object: nil,
        userInfo: userInfo,
        deliverImmediately: true
    )
}

/// Start the daemon through Launch Services, forwarding this invocation's
/// arguments so the new instance posts the notification itself. Returns false
/// when there is no .app bundle to launch, e.g. running the bare binary.
func relaunchAsDaemon(args: NotificationArgs) -> Bool {
    let bundleURL = Bundle.main.bundleURL
    guard Bundle.main.bundleIdentifier != nil, bundleURL.pathExtension == "app" else {
        return false
    }

    var forwarded = ["--daemon", "-t", args.title, "-m", args.message]
    if let activate = args.activate, !activate.isEmpty {
        forwarded += ["-a", activate]
    }
    if !args.sound {
        forwarded.append("--no-sound")
    }

    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    task.arguments = ["-a", bundleURL.path, "--args"] + forwarded
    do {
        try task.run()
    } catch {
        return false
    }
    task.waitUntilExit()
    return task.terminationStatus == 0
}

// Parse arguments
var notifArgs = NotificationArgs()
var daemonMode = false

// Launch Services may append -psn_… when opening an app bundle; ignore it.
var args: [String] = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-psn_") }

// A bare launch passes no arguments (`open ClaudeNotify.app`), which is the
// documented way to start the daemon. Without this the parser falls through to
// the usage error below and exits 1.
if args.isEmpty {
    daemonMode = true
}

while !args.isEmpty {
    let arg = args.removeFirst()
    switch arg {
    case "-d", "--daemon":
        daemonMode = true
    case "-t", "--title":
        if !args.isEmpty { notifArgs.title = args.removeFirst() }
    case "-m", "--message":
        if !args.isEmpty { notifArgs.message = args.removeFirst() }
    case "--no-sound":
        notifArgs.sound = false
    case "-a", "--activate":
        if !args.isEmpty { notifArgs.activate = args.removeFirst() }
    case "-h", "--help":
        print("""
        Usage:
          claude-notify --daemon              Start menu bar daemon
          claude-notify -m <msg> [-a <app>]   Send notification

        Options:
          -d, --daemon         Run as menu bar daemon
          -t, --title <text>   Notification title (default: "Claude Code")
          -m, --message <text> Notification message
          -a, --activate <id>  Bundle ID to activate on click
          --no-sound           Disable sound
        """)
        exit(0)
    default:
        if notifArgs.message.isEmpty {
            notifArgs.message = arg
        }
    }
}

if daemonMode || !notifArgs.message.isEmpty {
    // Try to acquire lock (single instance)
    let canStartDaemon = singleInstance.tryLock()

    if !canStartDaemon {
        // Another daemon is running
        if !notifArgs.message.isEmpty {
            sendToDaemon(args: notifArgs)
        }
        exit(0)
    }

    // No daemon is running. A client must not promote itself: a binary exec'd
    // directly carries no Launch Services identity, and macOS needs that to
    // resolve the app icon shown on the notification. Hand off to a daemon
    // started through Launch Services instead.
    if !daemonMode {
        singleInstance.unlock()
        if relaunchAsDaemon(args: notifArgs) {
            exit(0)
        }
        // No .app bundle to launch (bare binary): serve the notification here.
        _ = singleInstance.tryLock()
    }

    // Start as menu bar app
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate

    if !notifArgs.message.isEmpty {
        // Send notification after app starts
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            delegate.sendNotification(args: notifArgs)
        }
    }

    app.run()
} else {
    print("Error: use --daemon or provide -m <message>")
    exit(1)
}
