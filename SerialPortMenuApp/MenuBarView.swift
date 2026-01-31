import AppKit
import Foundation
import Combine

class MenuBarManager: NSObject, ObservableObject {
    private var statusItem: NSStatusItem?
    private var monitor: SerialPortMonitor?
    private var cancellables = Set<AnyCancellable>()

    // Custom popup window for notifications
    private var popupWindow: NSWindow?
    private var popupWorkItem: DispatchWorkItem?

    override init() {
        super.init()

        // Create status item in menu bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            // Use SF Symbol for serial port icon
            button.image = NSImage(systemSymbolName: "cable.connector", accessibilityDescription: "Serial Ports")
            button.image?.isTemplate = true
        }

        // Start monitoring serial ports
        monitor = SerialPortMonitor()
        monitor?.$serialPorts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ports in
                self?.updateMenu(ports: ports)
            }
            .store(in: &cancellables)

        // Listen for port change notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(portAdded(_:)),
            name: .serialPortAdded,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(portRemoved(_:)),
            name: .serialPortRemoved,
            object: nil
        )

        // Initial menu update
        updateMenu(ports: monitor?.serialPorts ?? [])
    }

    private func updateMenu(ports: [String]) {
        guard let statusItem = statusItem else { return }

        let menu = NSMenu()

        if ports.isEmpty {
            let noPortsItem = NSMenuItem(title: "No serial ports", action: nil, keyEquivalent: "")
            noPortsItem.isEnabled = false
            menu.addItem(noPortsItem)
        } else {
            for port in ports {
                // Extract just the device name (e.g., "cu.usbserial-xxx")
                let displayName = (port as NSString).lastPathComponent
                let item = NSMenuItem(title: displayName, action: #selector(copyPort(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = port
                // Add tooltip with full path
                item.toolTip = port
                menu.addItem(item)
            }
        }

        // Add separator
        menu.addItem(NSMenuItem.separator())

        // Add refresh button
        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshPorts), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        // Add quit button
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu

        // Update button title to show port count
        if let button = statusItem.button {
            if ports.isEmpty {
                button.title = ""
            } else {
                button.title = "\(ports.count)"
            }
        }
    }

    @objc private func portAdded(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let displayName = userInfo["displayName"] as? String else {
            return
        }
        showPopup(title: "Serial Port Connected", message: displayName, icon: "plus.circle.fill")
    }

    @objc private func portRemoved(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let displayName = userInfo["displayName"] as? String else {
            return
        }
        showPopup(title: "Serial Port Disconnected", message: displayName, icon: "minus.circle.fill")
    }

    private func showPopup(title: String, message: String, icon: String) {
        // Close any existing popup first
        hidePopup()

        // Cancel any pending popup dismissal
        popupWorkItem?.cancel()

        // Create a floating popup window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 80),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false  // Important: prevent app termination
        window.hidesOnDeactivate = false

        // Create content view with blur effect
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 80))
        contentView.wantsLayer = true

        // Add visual effect view (blur)
        let effectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 300, height: 80))
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 12
        contentView.addSubview(effectView)

        // Create icon image
        let iconImageView = NSImageView(frame: NSRect(x: 15, y: 25, width: 30, height: 30))
        if let iconImage = NSImage(systemSymbolName: icon, accessibilityDescription: nil) {
            iconImageView.image = iconImage
            switch icon {
            case "plus.circle.fill":
                iconImageView.contentTintColor = .systemGreen
            case "doc.on.clipboard.fill":
                iconImageView.contentTintColor = .systemBlue
            default:
                iconImageView.contentTintColor = .systemRed
            }
        }
        effectView.addSubview(iconImageView)

        // Create title label
        let titleField = NSTextField(labelWithString: title)
        titleField.frame = NSRect(x: 55, y: 45, width: 230, height: 20)
        titleField.font = NSFont.boldSystemFont(ofSize: 14)
        titleField.textColor = .white
        titleField.isEditable = false
        titleField.isSelectable = false
        titleField.drawsBackground = false
        titleField.lineBreakMode = .byTruncatingTail
        effectView.addSubview(titleField)

        // Create message label
        let messageField = NSTextField(labelWithString: message)
        messageField.frame = NSRect(x: 55, y: 20, width: 230, height: 18)
        messageField.font = NSFont.systemFont(ofSize: 12)
        messageField.textColor = .textColor
        messageField.isEditable = false
        messageField.isSelectable = false
        messageField.drawsBackground = false
        messageField.lineBreakMode = .byTruncatingTail
        effectView.addSubview(messageField)

        window.contentView = contentView

        // Position window at top right of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowFrame = window.frame
            window.setFrameTopLeftPoint(
                NSPoint(
                    x: screenFrame.maxX - windowFrame.width - 20,
                    y: screenFrame.maxY - 20
                )
            )
        }

        // Store reference and show window
        popupWindow = window
        window.orderFrontRegardless()

        // Auto-dismiss after 3 seconds
        let workItem = DispatchWorkItem { [weak self] in
            self?.hidePopup()
        }
        popupWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: workItem)
    }

    private func hidePopup() {
        popupWindow?.close()
        popupWindow = nil
    }

    @objc private func copyPort(_ sender: NSMenuItem) {
        guard let portPath = sender.representedObject as? String else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(portPath, forType: .string)

        print("Copied to clipboard: \(portPath)")

        let displayName = (portPath as NSString).lastPathComponent
        showPopup(title: "Copied to Clipboard", message: displayName, icon: "doc.on.clipboard.fill")
    }

    @objc private func refreshPorts() {
        monitor?.checkForPortChanges()
    }

    @objc private func quitApp() {
        hidePopup()
        NSApplication.shared.terminate(nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }
}
