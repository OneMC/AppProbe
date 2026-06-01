// LogInspector.swift
// AppProbe
//
// Console/Log 查询核心实现。使用 OSLogStore (iOS 15+) 查询当前进程日志。
// 支持按级别、子系统、分类、关键词过滤。
//
// 限制：仅能获取通过 os_log / Logger API 输出的日志。
// print()、NSLog 不保证可捕获。

import Foundation
import OSLog
import os

private let logger = Logger(subsystem: "com.appprobe", category: "log-inspector")

// MARK: - LogInspector

/// Console/Log 查询检查器
///
/// 使用 OSLogStore 查询当前进程的统一日志条目。
/// 仅在 iOS 15+ 可用，低版本返回明确错误。
@available(iOS 15.0, *)
final class LogInspector {

    static let shared = LogInspector()
    private init() {}

    /// 默认时间窗口（秒）：如果未指定 since，查询最近 5 分钟
    private let defaultTimeWindow: TimeInterval = 300

    /// 系统日志黑名单：这些 subsystem 的日志默认不返回
    private static let systemSubsystems: Set<String> = [
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

    /// 始终返回的 hint
    static let hint = LogHint(
        source: "OSLogStore (iOS 15+)",
        limitation: "仅能获取通过 os_log / Logger API 输出的日志。print()、NSLog 部分场景可捕获但不保证。如果查询结果为空，请排查：1) 目标代码是否使用了 os_log/Logger 而非 print；2) 日志是否确实在查询时间范围内产生；3) subsystem/category 参数是否拼写正确。",
        unsupportedMethods: [
            "print() 输出不保证捕获",
            "第三方日志库（CocoaLumberjack 等）需确认其底层是否走 os_log",
            "C/C++ 的 printf/stderr 不可捕获"
        ]
    )

    /// 查询最近日志
    ///
    /// - Parameters:
    ///   - count: 返回条数上限（默认 50，最大 200）
    ///   - level: 最低日志级别
    ///   - subsystem: 按 subsystem 精确过滤
    ///   - category: 按 category 精确过滤
    ///   - since: 起始时间
    ///   - keyword: 消息内容关键词搜索（大小写不敏感）
    ///   - includeSystemLogs: 是否包含系统日志（默认 false，过滤黑名单中的 subsystem）
    /// - Returns: 查询结果或错误
    func queryRecent(
        count: Int,
        level: OSLogEntryLog.Level?,
        subsystem: String?,
        category: String?,
        since: Date?,
        keyword: String?,
        includeSystemLogs: Bool = false
    ) -> Result<LogQueryResponse, LogErrorResponse> {
        let effectiveCount = min(max(count, 1), 200)
        let sinceDate = since ?? Date().addingTimeInterval(-defaultTimeWindow)

        let store: OSLogStore
        do {
            store = try OSLogStore(scope: .currentProcessIdentifier)
        } catch {
            logger.error("[queryRecent] OSLogStore 初始化失败: \(error.localizedDescription)")
            return .failure(LogErrorResponse(error: "Failed to open log store: \(error.localizedDescription)", code: "store_failed"))
        }

        let position = store.position(date: sinceDate)
        let entries: AnySequence<OSLogEntry>
        do {
            entries = try store.getEntries(at: position)
        } catch {
            logger.error("[queryRecent] 获取日志条目失败: \(error.localizedDescription)")
            return .failure(LogErrorResponse(error: "Failed to get entries: \(error.localizedDescription)", code: "query_failed"))
        }

        let dateFormatter = ISO8601DateFormatter()
        var matchedEntries: [LogEntry] = []

        for entry in entries {
            guard let logEntry = entry as? OSLogEntryLog else {
                continue
            }

            // 系统日志过滤（黑名单）
            if !includeSystemLogs && Self.systemSubsystems.contains(logEntry.subsystem) {
                continue
            }

            // 级别过滤
            if let minLevel = level, logEntry.level.rawValue < minLevel.rawValue {
                continue
            }

            // subsystem 过滤
            if let subsystem = subsystem, logEntry.subsystem != subsystem {
                continue
            }

            // category 过滤
            if let category = category, logEntry.category != category {
                continue
            }

            // keyword 过滤
            if let keyword = keyword,
               !logEntry.composedMessage.localizedCaseInsensitiveContains(keyword) {
                continue
            }

            matchedEntries.append(LogEntry(
                date: dateFormatter.string(from: logEntry.date),
                level: levelString(logEntry.level),
                subsystem: logEntry.subsystem,
                category: logEntry.category,
                message: logEntry.composedMessage
            ))

            // 收集满后提前终止遍历
            if matchedEntries.count >= effectiveCount {
                break
            }
        }

        let totalMatched = matchedEntries.count

        // 按时间倒序
        matchedEntries.reverse()

        let oldestDate = matchedEntries.last?.date
        let newestDate = matchedEntries.first?.date

        logger.info("[queryRecent] 查询完成, returned=\(matchedEntries.count)")

        return .success(LogQueryResponse(
            hint: Self.hint,
            totalMatched: totalMatched,
            returned: matchedEntries.count,
            oldestDate: oldestDate,
            newestDate: newestDate,
            entries: matchedEntries
        ))
    }

    /// 将 OSLogEntryLog.Level 转换为可读字符串
    private func levelString(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .undefined: return "undefined"
        case .debug: return "debug"
        case .info: return "info"
        case .notice: return "notice"
        case .error: return "error"
        case .fault: return "fault"
        @unknown default: return "unknown"
        }
    }
}

// MARK: - Level Parsing

/// 从字符串解析日志级别
@available(iOS 15.0, *)
func parseLogLevel(_ string: String?) -> OSLogEntryLog.Level? {
    guard let string = string?.lowercased() else { return nil }
    switch string {
    case "debug": return .debug
    case "info": return .info
    case "notice": return .notice
    case "error": return .error
    case "fault": return .fault
    default: return nil
    }
}

/// 从字符串解析 since 时间参数（支持 Unix timestamp 和 ISO8601）
func parseLogSince(_ string: String?) -> Date? {
    guard let string = string, !string.isEmpty else { return nil }

    // 尝试 Unix timestamp（秒）
    if let timestamp = TimeInterval(string) {
        return Date(timeIntervalSince1970: timestamp)
    }

    // 尝试 ISO8601
    let formatter = ISO8601DateFormatter()
    return formatter.date(from: string)
}
