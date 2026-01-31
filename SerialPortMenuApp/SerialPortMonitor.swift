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

        // ポート変化があった場合は高速ポーリングモードに移行
        recordActivity()

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
