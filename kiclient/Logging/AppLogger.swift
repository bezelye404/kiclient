import Foundation
import Combine
import Darwin

public enum LogLevel: String, CaseIterable, Codable, Sendable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

public enum LogCategory: String, CaseIterable, Codable, Sendable {
    case system = "SYSTEM"
    case player = "PLAYER"
    case chat = "CHAT"
    case network = "NETWORK"
    case auth = "AUTH"
}

public struct LogEntry: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let level: LogLevel
    public let category: LogCategory
    public let message: String

    public init(id: UUID = UUID(), timestamp: Date = Date(), level: LogLevel, category: LogCategory, message: String) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
    }

    public var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }
}

public final class AppLogger: ObservableObject, @unchecked Sendable {
    public static let shared = AppLogger()

    @Published public private(set) var entries: [LogEntry] = []
    private let maxEntries: Int
    private let lock = NSLock()

    public init(maxEntries: Int = 500) {
        self.maxEntries = maxEntries
    }

    public func log(_ level: LogLevel, category: LogCategory, _ message: String) {
        let entry = LogEntry(level: level, category: category, message: message)

        lock.lock()
        var updated = entries
        updated.append(entry)
        if updated.count > maxEntries {
            updated.removeFirst(updated.count - maxEntries)
        }
        lock.unlock()

        if Thread.isMainThread {
            self.entries = updated
        } else {
            DispatchQueue.main.async {
                self.entries = updated
            }
        }

        #if DEBUG
        print("[\(entry.formattedTime)] [\(category.rawValue)] [\(level.rawValue)] \(message)")
        #endif
    }

    public func debug(category: LogCategory, _ message: String) {
        log(.debug, category: category, message)
    }

    public func info(category: LogCategory, _ message: String) {
        log(.info, category: category, message)
    }

    public func warning(category: LogCategory, _ message: String) {
        log(.warning, category: category, message)
    }

    public func error(category: LogCategory, _ message: String) {
        log(.error, category: category, message)
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        if Thread.isMainThread {
            self.entries = []
        } else {
            DispatchQueue.main.async {
                self.entries = []
            }
        }
    }

    // MARK: - Live System Metrics

    public static func getMemoryUsageMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if kerr == KERN_SUCCESS {
            return Double(info.resident_size) / (1024.0 * 1024.0)
        }
        return 0.0
    }

    public static func getCPUUsagePercentage() -> Double {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        let kerr = task_threads(mach_task_self_, &threadList, &threadCount)
        guard kerr == KERN_SUCCESS, let threads = threadList else { return 0.0 }

        var totalUsage: Double = 0.0
        for i in 0..<Int(threadCount) {
            var threadInfo = thread_basic_info()
            var count = mach_msg_type_number_t(THREAD_INFO_MAX)
            let res = withUnsafeMutablePointer(to: &threadInfo) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    Darwin.thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
                }
            }
            if res == KERN_SUCCESS {
                if (threadInfo.flags & TH_FLAGS_IDLE) == 0 {
                    totalUsage += Double(threadInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
                }
            }
        }

        vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threads)), vm_size_t(Int(threadCount) * MemoryLayout<thread_t>.size))
        return totalUsage
    }
}
