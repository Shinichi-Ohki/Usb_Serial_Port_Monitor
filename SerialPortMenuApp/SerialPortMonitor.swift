import Foundation
import IOKit
import IOKit.serial

// Notification names for port changes
extension Notification.Name {
    static let serialPortAdded = Notification.Name("serialPortAdded")
    static let serialPortRemoved = Notification.Name("serialPortRemoved")
}

class SerialPortMonitor: ObservableObject {
    @Published var serialPorts: [String] = []

    private var pollingTimer: Timer?
    private var knownPorts: Set<String> = []
    private var connectionOrder: [String: Int] = [:]  // ポート名 -> 接続順序
    private var nextOrder = 0  // 次の接続順序
    private var isFirstScan = true  // 初回スキャンフラグ

    // IOKit通知
    private var notificationPort: IONotificationPortRef?
    private var matchedIterator: io_iterator_t = 0
    private var terminatedIterator: io_iterator_t = 0

    // フォールバックポーリング（IOKit通知の補完用）
    private let fallbackPollingInterval: TimeInterval = 30.0

    init() {
        print("SerialPortMonitor init")
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    func startMonitoring() {
        print("SerialPortMonitor startMonitoring")
        // Initial scan
        checkForPortChanges()

        // IOKit通知をセットアップ
        setupIOKitNotifications()

        // フォールバックポーリング（万一IOKit通知を取りこぼした場合の保険）
        pollingTimer = Timer.scheduledTimer(withTimeInterval: fallbackPollingInterval, repeats: true) { [weak self] _ in
            self?.checkForPortChanges()
        }
    }

    func stopMonitoring() {
        pollingTimer?.invalidate()
        pollingTimer = nil

        if matchedIterator != 0 {
            IOObjectRelease(matchedIterator)
            matchedIterator = 0
        }
        if terminatedIterator != 0 {
            IOObjectRelease(terminatedIterator)
            terminatedIterator = 0
        }
        if let port = notificationPort {
            IONotificationPortDestroy(port)
            notificationPort = nil
        }
    }

    // MARK: - IOKit通知

    private func setupIOKitNotifications() {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
            print("Failed to create IONotificationPort")
            return
        }
        notificationPort = port

        // RunLoopに登録
        let runLoopSource = IONotificationPortGetRunLoopSource(port).takeUnretainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        // 接続通知 (kIOMatchedNotification)
        if let matching = IOServiceMatching(kIOSerialBSDServiceValue) {
            let kr = IOServiceAddMatchingNotification(
                port,
                kIOMatchedNotification,
                matching,
                { (refcon, iterator) in
                    let monitor = Unmanaged<SerialPortMonitor>.fromOpaque(refcon!).takeUnretainedValue()
                    // イテレータを空にする（これをしないと次の通知が来ない）
                    monitor.drainIterator(iterator)
                    monitor.checkForPortChanges()
                },
                selfPtr,
                &matchedIterator
            )
            if kr == KERN_SUCCESS {
                // 初回: イテレータを空にしてarmする
                drainIterator(matchedIterator)
                print("IOKit matched notification registered")
            } else {
                print("Failed to register matched notification: \(kr)")
            }
        }

        // 切断通知 (kIOTerminatedNotification)
        if let matching = IOServiceMatching(kIOSerialBSDServiceValue) {
            let kr = IOServiceAddMatchingNotification(
                port,
                kIOTerminatedNotification,
                matching,
                { (refcon, iterator) in
                    let monitor = Unmanaged<SerialPortMonitor>.fromOpaque(refcon!).takeUnretainedValue()
                    monitor.drainIterator(iterator)
                    monitor.checkForPortChanges()
                },
                selfPtr,
                &terminatedIterator
            )
            if kr == KERN_SUCCESS {
                drainIterator(terminatedIterator)
                print("IOKit terminated notification registered")
            } else {
                print("Failed to register terminated notification: \(kr)")
            }
        }
    }

    /// イテレータを空になるまで回す（通知を再armするために必須）
    private func drainIterator(_ iterator: io_iterator_t) {
        var service = IOIteratorNext(iterator)
        while service != 0 {
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
    }

    func checkForPortChanges() {
        var currentPorts: Set<String> = []

        // IOKitでシリアルポートを検出
        let classesToMatch = IOServiceMatching(kIOSerialBSDServiceValue)

        if let matching = classesToMatch {
            var iter: io_iterator_t = 0
            let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter)

            if result == KERN_SUCCESS {
                var service: io_object_t = IOIteratorNext(iter)

                while service != 0 {
                    let deviceFilePathKey = kIOCalloutDeviceKey as CFString
                    if let propertyResult = IORegistryEntryCreateCFProperty(
                        service,
                        deviceFilePathKey,
                        kCFAllocatorDefault,
                        0
                    ) {
                        if let devicePath = propertyResult.takeRetainedValue() as? String {
                            currentPorts.insert(devicePath)
                        }
                    }

                    IOObjectRelease(service)
                    service = IOIteratorNext(iter)
                }
                IOObjectRelease(iter)
            }
        }

        // Find added and removed ports
        let addedPorts = currentPorts.subtracting(knownPorts)
        let removedPorts = knownPorts.subtracting(currentPorts)

        // 変化がなければ何もしない
        guard !addedPorts.isEmpty || !removedPorts.isEmpty else { return }

        // knownPortsを更新
        for port in addedPorts {
            knownPorts.insert(port)
            connectionOrder[port] = nextOrder
            nextOrder += 1
        }
        for port in removedPorts {
            knownPorts.remove(port)
            connectionOrder.removeValue(forKey: port)
        }

        // メニューを1回だけ更新
        updateSerialPorts()

        // 初回スキャンでは通知を出さない
        if isFirstScan {
            isFirstScan = false
            return
        }

        // 通知を送信
        for port in addedPorts {
            let displayName = (port as NSString).lastPathComponent
            print("Port added: \(displayName)")
            NotificationCenter.default.post(
                name: .serialPortAdded,
                object: self,
                userInfo: ["port": port, "displayName": displayName]
            )
        }

        for port in removedPorts {
            let displayName = (port as NSString).lastPathComponent
            print("Port removed: \(displayName)")
            NotificationCenter.default.post(
                name: .serialPortRemoved,
                object: self,
                userInfo: ["port": port, "displayName": displayName]
            )
        }
    }

    private func updateSerialPorts() {
        // 接続順序があるポートとないポートに分ける
        var orderedPorts: [(port: String, order: Int)] = []
        var unorderedPorts: [String] = []

        for port in knownPorts {
            if let order = connectionOrder[port] {
                orderedPorts.append((port, order))
            } else {
                unorderedPorts.append(port)
            }
        }

        // 接続順序があるポートは順序順に
        orderedPorts.sort { $0.order < $1.order }

        // 接続順序がないポート（既存ポート）はアルファベット順
        unorderedPorts.sort()

        // 既存ポート（アルファベット順）+ 新規ポート（接続順）
        var result = unorderedPorts.map { $0 }
        result.append(contentsOf: orderedPorts.map { $0.port })

        serialPorts = result
    }
}
