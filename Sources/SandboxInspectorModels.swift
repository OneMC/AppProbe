// SandboxInspectorModels.swift
// AppProbe
//
// 沙盒文件管理 API 的数据模型定义。
// 包含文件信息、目录列表、文件内容、读取格式、
// 写入/删除请求响应、错误响应、SQL 查询结果等。

import Foundation

// MARK: - SandboxFileInfo

/// 沙盒文件/目录信息
struct SandboxFileInfo: Codable {
    let name: String
    let path: String
    let size: Int64
    let isDirectory: Bool
    let modificationDate: String
    let isReadable: Bool
}

// MARK: - SandboxListResult

/// 目录浏览结果
struct SandboxListResult: Codable {
    let currentPath: String
    let files: [SandboxFileInfo]
}

// MARK: - SandboxContentType

/// 文件内容类型（基于扩展名识别）
enum SandboxContentType: String, Codable {
    case text
    case json
    case plist
    case sqlite
    case binary
    case unknown
}

// MARK: - SandboxFileContent

/// 文件读取结果，根据格式可能包含文本内容、Base64 数据或下载链接
struct SandboxFileContent: Codable {
    let name: String
    let path: String
    let size: Int64
    let contentType: SandboxContentType
    let textContent: String?
    let base64Content: String?
    let downloadUrl: String?
    let message: String?
}

// MARK: - SandboxReadFormat

/// 文件读取格式参数
enum SandboxReadFormat: String {
    /// 自动判断：文本类小文件直接返回内容，SQLite 提示用 SQL 查询，大文件返回下载链接
    case auto
    /// 强制以 UTF-8 文本读取
    case text
    /// 强制以 JSON 文本读取（仅限 .json/.plist）
    case json
    /// 返回下载链接
    case download
}

// MARK: - SandboxWriteRequest / SandboxWriteResponse

/// 文件写入请求体
struct SandboxWriteRequest: Codable {
    let path: String
    let content: String
    let encoding: String?
    let append: Bool?
}

/// 文件写入响应体
struct SandboxWriteResponse: Codable {
    let success: Bool
    let path: String
    let bytesWritten: Int
    let message: String?
}

// MARK: - SandboxDeleteResponse

/// 文件删除响应体
struct SandboxDeleteResponse: Codable {
    let success: Bool
    let path: String
    let message: String?
}

// MARK: - SandboxErrorResponse

/// 沙盒 API 统一错误响应，同时遵循 Error 协议用于 Result 类型
struct SandboxErrorResponse: Codable, Error {
    let error: String
    let code: String
}

// MARK: - SQL Query Request / Result

/// SQLite 查询请求体
struct SandboxSQLRequest: Codable {
    let path: String
    let sql: String
}

/// SQLite 查询结果（列名 + 行数据 + 行数统计）
struct SandboxSQLResult: Codable {
    let columns: [String]
    let rows: [[String: String?]]
    let rowCount: Int
}

// MARK: - UserDefaults Models

/// UserDefaults 列举模式下的单条条目
struct UserDefaultsEntry: Codable {
    let key: String
    let type: String
    let value: String
}

/// UserDefaults 列举模式响应
struct UserDefaultsListResponse: Codable {
    let suite: String
    let count: Int
    let entries: [UserDefaultsEntry]
}

/// UserDefaults 精确获取模式响应
struct UserDefaultsGetResponse: Codable {
    let suite: String
    let key: String
    let type: String
    let value: AnyCodableValue?
    let found: Bool
}

/// UserDefaults 设置操作响应
struct UserDefaultsSetResponse: Codable {
    let success: Bool
    let key: String
    let type: String
    let value: String
    let message: String
}

/// UserDefaults 删除操作响应
struct UserDefaultsDeleteResponse: Codable {
    let success: Bool
    let key: String
    let message: String
}

/// 类型擦除的 Codable 值，用于包装 UserDefaults 中各类型的值
enum AnyCodableValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodableValue])
    case dictionary([String: AnyCodableValue])
    case data(String) // base64 encoded
    case null

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .dictionary(let v): try container.encode(v)
        case .data(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let v = try? container.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? container.decode(Int.self) {
            self = .int(v)
        } else if let v = try? container.decode(Double.self) {
            self = .double(v)
        } else if let v = try? container.decode(String.self) {
            self = .string(v)
        } else if let v = try? container.decode([AnyCodableValue].self) {
            self = .array(v)
        } else if let v = try? container.decode([String: AnyCodableValue].self) {
            self = .dictionary(v)
        } else {
            self = .null
        }
    }
}
