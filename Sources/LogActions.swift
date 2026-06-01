// LogActions.swift
// AppProbe
//
// 日志查询 Actions：Recent

import Foundation
import OSLog
import os

private let logger = Logger(subsystem: "com.appprobe", category: "log-actions")

// MARK: - LogRecentAction

/// GET /log/recent — 查询最近日志
final class LogRecentAction: AIAction {
    let module = "log"
    let name = "recent"
    let httpMethod = "GET"
    let summary = "查询最近日志，支持按级别/子系统/分类/关键词过滤（iOS 15+，仅捕获 os_log/Logger 输出）"
    let parameters = [
        APIParameterDescriptor(name: "count", type: "Int", required: false, description: "返回条数，默认 50，最大 200"),
        APIParameterDescriptor(name: "level", type: "String", required: false, description: "最低日志级别：debug / info / notice / error / fault"),
        APIParameterDescriptor(name: "subsystem", type: "String", required: false, description: "按 subsystem 精确过滤"),
        APIParameterDescriptor(name: "category", type: "String", required: false, description: "按 category 精确过滤"),
        APIParameterDescriptor(name: "since", type: "String", required: false, description: "起始时间（Unix timestamp 秒 或 ISO8601）"),
        APIParameterDescriptor(name: "keyword", type: "String", required: false, description: "消息内容关键词搜索（大小写不敏感）"),
        APIParameterDescriptor(name: "systemLogs", type: "Bool", required: false, description: "是否包含系统日志，默认 false"),
    ]
    let example = APIExample(
        requestURL: "/log/recent?count=10&level=error",
        responseBody: #"{"hint":{"source":"OSLogStore (iOS 15+)","limitation":"仅能获取通过 os_log / Logger API 输出的日志。","unsupportedMethods":["print() 输出不保证捕获"]},"totalMatched":3,"returned":3,"oldestDate":"2026-05-21T10:00:00Z","newestDate":"2026-05-21T10:05:30Z","entries":[{"date":"2026-05-21T10:05:30Z","level":"error","subsystem":"com.myapp","category":"network","message":"Request timeout"}]}"#
    )

    func execute(params: [String: String]) -> ActionResponse {
        guard #available(iOS 15.0, *) else {
            let error = LogErrorResponse(error: "Log query requires iOS 15.0+", code: "unsupported_version")
            return .json(error)
        }

        let count = params["count"].flatMap { Int($0) } ?? 50
        let level = parseLogLevel(params["level"])
        let subsystem = params["subsystem"]
        let category = params["category"]
        let since = parseLogSince(params["since"])
        let keyword = params["keyword"]
        let includeSystemLogs = params["systemLogs"]?.lowercased() == "true"

        let result = LogInspector.shared.queryRecent(
            count: count, level: level, subsystem: subsystem,
            category: category, since: since, keyword: keyword,
            includeSystemLogs: includeSystemLogs
        )

        switch result {
        case .success(let response):
            return .json(response)
        case .failure(let error):
            return .json(error)
        }
    }
}
