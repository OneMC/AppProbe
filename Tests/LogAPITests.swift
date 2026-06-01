// LogAPITests.swift
// AppProbe Tests
//
// Console/Log 查询 API 集成测试：
// - 不同日志输出方式的捕获能力验证
// - 系统日志过滤功能验证
// - 过滤参数验证
//
// 结论摘要（OSLogStore + currentProcessIdentifier scope）：
// ✅ 可捕获：Logger API、os_log 函数、NSLog
// ❌ 不可捕获：print()、C 的 printf/fprintf(stderr)

import Foundation
import os
import Testing
@testable import AppProbe

// MARK: - 日志输出方式覆盖测试

@Suite("Log Capture Methods")
@MainActor
struct LogCaptureMethodTests {

    let port: UInt

    init() async throws {
        AppProbeServer.shared.start()
        guard AppProbeServer.shared.isRunning else {
            throw TestError.serverNotRunning
        }
        self.port = AppProbeServer.shared.port
    }

    // MARK: ✅ Logger API（os.Logger, iOS 14+）

    @Test("Logger API 日志可被捕获")
    func testLoggerAPICapturable() async throws {
        let uniqueMarker = "LOGGER_API_\(UUID().uuidString.prefix(8))"
        let testLogger = Logger(subsystem: "com.appprobe.test.capture", category: "logger-api")
        testLogger.info("\(uniqueMarker)")

        try await Task.sleep(nanoseconds: 300_000_000)

        let result = try await TestHTTPClient.get(
            "/log/recent?keyword=\(uniqueMarker)&count=50&systemLogs=true",
            port: port
        )
        #expect(result.statusCode == 200)

        let json = try result.json()
        let entries = json["entries"] as? [[String: Any]] ?? []

        // Logger API 输出应可被 OSLogStore 捕获
        #expect(entries.count > 0, "✅ Logger API: 应可被捕获")

        if let entry = entries.first {
            #expect(entry["subsystem"] as? String == "com.appprobe.test.capture")
            #expect(entry["category"] as? String == "logger-api")
        }
    }

    // MARK: ✅ Logger API 各级别

    @Test("Logger API 所有级别均可捕获")
    func testLoggerAllLevels() async throws {
        let marker = "LEVELS_\(UUID().uuidString.prefix(8))"
        let testLogger = Logger(subsystem: "com.appprobe.test.levels", category: "all-levels")

        testLogger.debug("\(marker)_debug")
        testLogger.info("\(marker)_info")
        testLogger.notice("\(marker)_notice")
        testLogger.error("\(marker)_error")
        testLogger.fault("\(marker)_fault")

        try await Task.sleep(nanoseconds: 300_000_000)

        let result = try await TestHTTPClient.get(
            "/log/recent?keyword=\(marker)&count=50&systemLogs=true",
            port: port
        )
        let json = try result.json()
        let entries = json["entries"] as? [[String: Any]] ?? []

        // debug 级别在 release 构建中可能不持久化，但 info 及以上应该都能捕获
        let levels = Set(entries.compactMap { $0["level"] as? String })
        #expect(levels.contains("info"), "✅ info 级别可捕获")
        #expect(levels.contains("notice"), "✅ notice 级别可捕获")
        #expect(levels.contains("error"), "✅ error 级别可捕获")
        #expect(levels.contains("fault"), "✅ fault 级别可捕获")
    }

    // MARK: ✅ os_log 函数（传统 C 风格 API）

    @Test("os_log 函数日志可被捕获")
    func testOsLogFunctionCapturable() async throws {
        let uniqueMarker = "OS_LOG_FUNC_\(UUID().uuidString.prefix(8))"
        let customLog = OSLog(subsystem: "com.appprobe.test.capture", category: "os-log-func")
        os_log(.info, log: customLog, "%{public}@", uniqueMarker)

        try await Task.sleep(nanoseconds: 300_000_000)

        let result = try await TestHTTPClient.get(
            "/log/recent?keyword=\(uniqueMarker)&count=50&systemLogs=true",
            port: port
        )
        let json = try result.json()
        let entries = json["entries"] as? [[String: Any]] ?? []

        #expect(entries.count > 0, "✅ os_log 函数: 应可被捕获")

        if let entry = entries.first {
            #expect(entry["subsystem"] as? String == "com.appprobe.test.capture")
            #expect(entry["category"] as? String == "os-log-func")
        }
    }

    // MARK: ✅ NSLog

    @Test("NSLog 日志可被捕获（subsystem 为空）")
    func testNSLogCapturable() async throws {
        let uniqueMarker = "NSLOG_\(UUID().uuidString.prefix(8))"
        NSLog("%@", uniqueMarker)

        try await Task.sleep(nanoseconds: 300_000_000)

        let result = try await TestHTTPClient.get(
            "/log/recent?keyword=\(uniqueMarker)&count=50&systemLogs=true",
            port: port
        )
        let json = try result.json()
        let entries = json["entries"] as? [[String: Any]] ?? []

        // NSLog 通过 os_log 底层输出，subsystem 为空字符串
        #expect(entries.count > 0, "✅ NSLog: 应可被捕获")

        if let entry = entries.first {
            #expect(entry["subsystem"] as? String == "", "NSLog 的 subsystem 为空字符串")
        }
    }

    // MARK: ❌ print()

    @Test("print() 输出不可被捕获")
    func testPrintNotCapturable() async throws {
        let uniqueMarker = "PRINT_\(UUID().uuidString.prefix(8))"
        print(uniqueMarker)

        try await Task.sleep(nanoseconds: 300_000_000)

        let result = try await TestHTTPClient.get(
            "/log/recent?keyword=\(uniqueMarker)&count=50&systemLogs=true",
            port: port
        )
        let json = try result.json()
        let entries = json["entries"] as? [[String: Any]] ?? []

        // print() 走 stdout，OSLogStore 不捕获
        #expect(entries.count == 0, "❌ print(): 不可被 OSLogStore 捕获")
    }

    // MARK: ❌ debugPrint()

    @Test("debugPrint() 输出不可被捕获")
    func testDebugPrintNotCapturable() async throws {
        let uniqueMarker = "DEBUGPRINT_\(UUID().uuidString.prefix(8))"
        debugPrint(uniqueMarker)

        try await Task.sleep(nanoseconds: 300_000_000)

        let result = try await TestHTTPClient.get(
            "/log/recent?keyword=\(uniqueMarker)&count=50&systemLogs=true",
            port: port
        )
        let json = try result.json()
        let entries = json["entries"] as? [[String: Any]] ?? []

        // debugPrint() 同样走 stdout
        #expect(entries.count == 0, "❌ debugPrint(): 不可被 OSLogStore 捕获")
    }

    // MARK: ❌ fputs/stderr（C 层输出）

    @Test("fputs stderr 输出不可被捕获")
    func testFputsStderrNotCapturable() async throws {
        let uniqueMarker = "FPUTS_\(UUID().uuidString.prefix(8))"
        fputs(uniqueMarker + "\n", stderr)

        try await Task.sleep(nanoseconds: 300_000_000)

        let result = try await TestHTTPClient.get(
            "/log/recent?keyword=\(uniqueMarker)&count=50&systemLogs=true",
            port: port
        )
        let json = try result.json()
        let entries = json["entries"] as? [[String: Any]] ?? []

        // C 层 stderr 输出不经过 unified logging
        #expect(entries.count == 0, "❌ fputs(stderr): 不可被 OSLogStore 捕获")
    }
}

// MARK: - 系统日志过滤测试

@Suite("System Log Filtering")
@MainActor
struct SystemLogFilteringTests {

    let port: UInt

    init() async throws {
        AppProbeServer.shared.start()
        guard AppProbeServer.shared.isRunning else {
            throw TestError.serverNotRunning
        }
        self.port = AppProbeServer.shared.port

        // 写入 App 自有日志
        let appLogger = Logger(subsystem: "com.appprobe.test.app", category: "app-logic")
        appLogger.info("App log entry for filter test")

        try await Task.sleep(nanoseconds: 200_000_000)
    }

    @Test("默认过滤系统日志：结果不包含黑名单 subsystem")
    func testDefaultFiltersSystemLogs() async throws {
        let result = try await TestHTTPClient.get(
            "/log/recent?count=100",
            port: port
        )
        #expect(result.statusCode == 200)

        let json = try result.json()
        let entries = json["entries"] as? [[String: Any]] ?? []

        let systemSubsystems: Set<String> = [
            "com.apple.CoreData",
            "com.apple.network",
            "com.apple.CFNetwork",
            "com.apple.UIKit",
            "com.apple.Foundation",
            "com.apple.CoreAnimation",
            "com.apple.runningboard",
            "com.apple.RunningBoardServices",
            "com.apple.Metal",
            "com.apple.avfaudio",
            "com.apple.SystemConfiguration",
            "com.apple.TCC",
            "com.apple.defaults",
            "com.apple.BackgroundTaskAgent",
        ]

        // 默认请求不应包含任何黑名单中的 subsystem
        for entry in entries {
            let subsystem = entry["subsystem"] as? String ?? ""
            #expect(!systemSubsystems.contains(subsystem),
                    "默认模式不应返回系统 subsystem: \(subsystem)")
        }
    }

    @Test("默认模式保留 App 自有日志")
    func testDefaultKeepsAppLogs() async throws {
        let result = try await TestHTTPClient.get(
            "/log/recent?subsystem=com.appprobe.test.app&count=50",
            port: port
        )
        #expect(result.statusCode == 200)

        let json = try result.json()
        let entries = json["entries"] as? [[String: Any]] ?? []

        #expect(entries.count > 0, "App 自有日志应保留")
    }

    @Test("默认模式保留 NSLog（空 subsystem 不过滤）")
    func testDefaultKeepsNSLog() async throws {
        let marker = "NSLOG_FILTER_\(UUID().uuidString.prefix(8))"
        NSLog("%@", marker)

        try await Task.sleep(nanoseconds: 300_000_000)

        let result = try await TestHTTPClient.get(
            "/log/recent?keyword=\(marker)&count=50",
            port: port
        )
        let json = try result.json()
        let entries = json["entries"] as? [[String: Any]] ?? []

        #expect(entries.count > 0, "NSLog（空 subsystem）在默认模式下不被过滤")
    }

    @Test("systemLogs=true 时包含系统日志")
    func testSystemLogsParamIncludesAll() async throws {
        // 对比 systemLogs=true 和默认的返回数量
        let withSystem = try await TestHTTPClient.get(
            "/log/recent?count=200&systemLogs=true",
            port: port
        )
        let withoutSystem = try await TestHTTPClient.get(
            "/log/recent?count=200",
            port: port
        )

        let jsonWith = try withSystem.json()
        let jsonWithout = try withoutSystem.json()

        let totalWith = jsonWith["totalMatched"] as? Int ?? 0
        let totalWithout = jsonWithout["totalMatched"] as? Int ?? 0

        // 包含系统日志时，匹配总数应 >= 不包含时
        #expect(totalWith >= totalWithout,
                "systemLogs=true 的结果数量应 >= 默认过滤后的数量")
    }

    @Test("显式指定 subsystem 过滤时，系统日志黑名单不生效")
    func testExplicitSubsystemBypassesBlacklist() async throws {
        // 当用户明确传了 subsystem 参数时，即使该 subsystem 在黑名单中也应该能查到
        // （因为 subsystem 精确过滤优先级更高）
        let result = try await TestHTTPClient.get(
            "/log/recent?subsystem=com.apple.CoreData&count=50&systemLogs=true",
            port: port
        )
        #expect(result.statusCode == 200)

        let json = try result.json()
        let entries = json["entries"] as? [[String: Any]] ?? []

        // 如果有 CoreData 日志，应该能通过 systemLogs=true + subsystem 精确拿到
        for entry in entries {
            #expect(entry["subsystem"] as? String == "com.apple.CoreData")
        }
    }
}

// MARK: - 原有功能回归测试

@Suite("Log API Regression")
@MainActor
struct LogAPIRegressionTests {

    let port: UInt

    init() async throws {
        AppProbeServer.shared.start()
        guard AppProbeServer.shared.isRunning else {
            throw TestError.serverNotRunning
        }
        self.port = AppProbeServer.shared.port

        let testLogger = Logger(subsystem: "com.appprobe.test", category: "regression")
        testLogger.info("Regression test log entry")
        testLogger.error("Regression test error entry")

        try await Task.sleep(nanoseconds: 200_000_000)
    }

    @Test("GET /log/recent 返回正确结构")
    func testRecentLogsStructure() async throws {
        let result = try await TestHTTPClient.get("/log/recent?count=10", port: port)

        #expect(result.statusCode == 200)

        let json = try result.json()

        // hint 字段始终存在
        let hint = json["hint"] as? [String: Any]
        #expect(hint != nil)
        #expect(hint?["source"] as? String != nil)
        #expect(hint?["limitation"] as? String != nil)
        let unsupported = hint?["unsupportedMethods"] as? [String]
        #expect(unsupported != nil)
        #expect((unsupported?.count ?? 0) > 0)

        // 基本响应结构
        #expect(json["totalMatched"] as? Int != nil)
        #expect(json["returned"] as? Int != nil)
        #expect(json["entries"] as? [[String: Any]] != nil)
    }

    @Test("按 level 过滤")
    func testFilterByLevel() async throws {
        let result = try await TestHTTPClient.get(
            "/log/recent?level=error&count=50",
            port: port
        )
        #expect(result.statusCode == 200)

        let json = try result.json()
        let entries = json["entries"] as? [[String: Any]] ?? []
        let validLevels = ["error", "fault"]

        for entry in entries {
            let level = entry["level"] as? String ?? ""
            #expect(validLevels.contains(level), "Unexpected level: \(level)")
        }
    }

    @Test("按 keyword 过滤")
    func testFilterByKeyword() async throws {
        let result = try await TestHTTPClient.get(
            "/log/recent?keyword=Regression%20test&count=50",
            port: port
        )
        #expect(result.statusCode == 200)

        let json = try result.json()
        let entries = json["entries"] as? [[String: Any]] ?? []

        for entry in entries {
            let message = (entry["message"] as? String ?? "").lowercased()
            #expect(message.contains("regression test"))
        }
    }

    @Test("count 参数限制返回条数")
    func testCountLimit() async throws {
        let result = try await TestHTTPClient.get("/log/recent?count=2", port: port)
        #expect(result.statusCode == 200)

        let json = try result.json()
        let returned = json["returned"] as? Int ?? 0
        #expect(returned <= 2)
    }

    @Test("日志条目包含完整字段")
    func testEntryFields() async throws {
        let result = try await TestHTTPClient.get(
            "/log/recent?subsystem=com.appprobe.test&count=5",
            port: port
        )
        #expect(result.statusCode == 200)

        let json = try result.json()
        let entries = json["entries"] as? [[String: Any]] ?? []

        if let entry = entries.first {
            #expect(entry["date"] as? String != nil)
            #expect(entry["level"] as? String != nil)
            #expect(entry["subsystem"] as? String != nil)
            #expect(entry["category"] as? String != nil)
            #expect(entry["message"] as? String != nil)
        }
    }
}
