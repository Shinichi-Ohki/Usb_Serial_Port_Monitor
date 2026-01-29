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

    // 動的ポーリング設定
    private var lastActivityTime: Date = Date()  // 最後のポート変化時刻
    private let highSpeedPollingDuration: TimeInterval = 3600  // 高速ポーリング維持時間（1時間）
    private let fastPollingInterval: TimeInterval = 1.0  // 高速ポーリング間隔（1秒）
    private let slowPollingInterval: TimeInterval = 5.0  // 低速ポーリング間隔（5秒）

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

        // 動的ポーリングを開始
        scheduleNextPoll()
    }

    func stopMonitoring() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    // 現在のポーリング間隔を計算
    private var currentPollingInterval: TimeInterval {
        let timeSinceActivity = Date().timeIntervalSince(lastActivityTime)
        return timeSinceActivity < highSpeedPollingDuration ? fastPollingInterval : slowPollingInterval
    }

    // 次のポーリングをスケジュール
    private func scheduleNextPoll() {
        pollingTimer?.invalidate()

        let interval = currentPollingInterval
        pollingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.checkForPortChanges()
            self?.scheduleNextPoll()  // 次のポーリングをスケジュール
        }
    }

    // ポート変化を記録して高速ポーリングモードに移行
    private func recordActivity() {
        lastActivityTime = Date()
    }

    func checkForPortChanges() {
        var currentPorts: Set<String> = []

        // Scan /dev/cu.* for ports
        if let devPaths = FileManager.default.enumerator(atPath: "/dev") {
            while let path = devPaths.nextObject() as? String {
                if path.hasPrefix("cu.") {
                    currentPorts.insert("/dev/\(path)")
                }
            }
        }

        // Use IOKit to get more detailed info
        let masterPort = mach_port_t(0)
        let classesToMatch = IOServiceMatching(kIOSerialBSDServiceValue)

        if let matching = classesToMatch {
            var iter: io_iterator_t = 0
            let result = IOServiceGetMatchingServices(masterPort, matching, &iter)

            if result == KERN_SUCCESS {
                var service: io_object_t
                service = IOIteratorNext(iter)

                while service != 0 {
                    var deviceFilePathCF: CFString?
                    let deviceFilePathKey = kIOCalloutDeviceKey as CFString
                    let propertyResult = IORegistryEntryCreateCFProperty(
                        service,
                        deviceFilePathKey,
                        kCFAllocatorDefault,
                        0
                    )

                    if let propertyResult = propertyResult {
                        deviceFilePathCF = (propertyResult.takeRetainedValue() as! CFString)
                    }

                    if let devicePath = deviceFilePathCF as String? {
                        currentPorts.insert(devicePath)
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

        // ポート変化があった場合は高速ポーリングモードに移行
        if !addedPorts.isEmpty || !removedPorts.isEmpty {
            recordActivity()
        }

        for port in addedPorts {
            let displayName = (port as NSString).lastPathComponent
            print("Port added: \(displayName)")
            knownPorts.insert(port)

            // 新規ポートには接続順序を割り当て
            connectionOrder[port] = nextOrder
            nextOrder += 1

            updateSerialPorts()

            NotificationCenter.default.post(
                name: .serialPortAdded,
                object: self,
                userInfo: ["port": port, "displayName": displayName]
            )
        }

        for port in removedPorts {
            let displayName = (port as NSString).lastPathComponent
            print("Port removed: \(displayName)")
            knownPorts.remove(port)

            // 削除時に順序も削除
            connectionOrder.removeValue(forKey: port)

            updateSerialPorts()

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
