// LogInspectorModels.swift
// AppProbe
//
// Console/Log 查询 API 的数据模型定义。
// 包含日志条目、查询结果、来源限制提示等。

import Foundation

// MARK: - Log Query Response

/// GET /log/recent 响应
struct LogQueryResponse: Codable {
    let hint: LogHint
    let totalMatched: Int
    let returned: Int
    let oldestDate: String?
    let newestDate: String?
    let entries: [LogEntry]
}

/// 日志来源限制提示（始终返回，帮助调用方理解数据局限性）
struct LogHint: Codable {
    let source: String
    let limitation: String
    let unsupportedMethods: [String]
}

/// 单条日志条目
struct LogEntry: Codable {
    let date: String
    let level: String
    let subsystem: String
    let category: String
    let message: String
}

// MARK: - Log Error Response

/// Log API 错误响应
struct LogErrorResponse: Codable, Error {
    let error: String
    let code: String
}
