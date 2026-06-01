// SandboxActions.swift
// AppProbe
//
// 沙盒文件管理 Actions：List、File、Download、SQL、Write、Delete

import Foundation
import os

private let logger = Logger(subsystem: "com.appprobe", category: "sandbox-actions")

// MARK: - Sandbox Helper

/// 沙盒错误码 → HTTP 状态码
private func sandboxErrorStatusCode(_ code: String) -> Int {
    switch code {
    case "invalid_path", "invalid_sql", "not_writable", "not_readable": return 403
    case "not_found": return 404
    case "is_directory", "invalid_encoding", "not_directory": return 400
    case "unsupported_media_type": return 415
    case "file_too_large": return 413
    default: return 500
    }
}

/// 包装 SandboxInspector 结果为 ActionResponse（保留完整错误 JSON 结构）
private func sandboxResult<T: Codable>(_ result: Result<T, SandboxErrorResponse>) -> ActionResponse {
    switch result {
    case .success(let value):
        return .json(value)
    case .failure(let error):
        return .jsonWithStatus(error, statusCode: sandboxErrorStatusCode(error.code))
    }
}

// MARK: - SandboxListAction

final class SandboxListAction: AIAction {
    let module = "sandbox"
    let name = "list"
    let httpMethod = "GET"
    let summary = "浏览沙盒目录，列出文件和子目录"
    let parameters = [
        APIParameterDescriptor(name: "path", type: "String", required: false, description: "相对于沙盒根目录的路径，不传则浏览根目录"),
    ]
    let example = APIExample(
        requestURL: "/sandbox/list?path=Documents",
        responseBody: #"{"currentPath":"Documents","files":[{"name":"data.json","path":"Documents/data.json","size":256,"isDirectory":false,"modificationDate":"2026-01-01T00:00:00Z","isReadable":true}]}"#
    )

    func execute(params: [String: String]) -> ActionResponse {
        let path = params["path"] ?? ""
        return sandboxResult(SandboxInspector.shared.listDirectory(path: path))
    }
}

// MARK: - SandboxFileAction

final class SandboxFileAction: AIAction {
    let module = "sandbox"
    let name = "file"
    let httpMethod = "GET"
    let summary = "读取沙盒文件内容，支持多种格式（auto/text/json/download）"
    let parameters = [
        APIParameterDescriptor(name: "path", type: "String", required: true, description: "文件相对路径"),
        APIParameterDescriptor(name: "format", type: "String", required: false, description: "读取格式：auto（默认）、text、json、download"),
    ]
    let example = APIExample(
        requestURL: "/sandbox/file?path=Documents/config.json&format=json",
        responseBody: #"{"name":"config.json","path":"Documents/config.json","size":64,"contentType":"json","textContent":"{\"key\":\"value\"}","base64Content":null,"downloadUrl":null,"message":null}"#
    )

    func execute(params: [String: String]) -> ActionResponse {
        guard let path = params["path"] else {
            return .error(code: 400, message: "Missing 'path' parameter")
        }
        let format = SandboxReadFormat(rawValue: params["format"] ?? "auto") ?? .auto
        return sandboxResult(SandboxInspector.shared.readFile(path: path, format: format))
    }
}

// MARK: - SandboxDownloadAction

final class SandboxDownloadAction: AIAction {
    let module = "sandbox"
    let name = "download"
    let httpMethod = "GET"
    let summary = "下载沙盒文件（二进制流，Content-Type: application/octet-stream）"
    let parameters = [
        APIParameterDescriptor(name: "path", type: "String", required: true, description: "文件相对路径"),
    ]
    let example = APIExample(
        requestURL: "/sandbox/download?path=Documents/data.db",
        responseBody: #"{"note":"此端点返回二进制文件流，不是 JSON。响应头包含 Content-Disposition 指定文件名。"}"#
    )

    func execute(params: [String: String]) -> ActionResponse {
        guard let path = params["path"] else {
            return .error(code: 400, message: "Missing 'path' parameter")
        }
        let result = SandboxInspector.shared.downloadFile(path: path)
        switch result {
        case .success(let data):
            let fileName = (path as NSString).lastPathComponent
            return .raw(data: data, contentType: "application/octet-stream",
                        headers: ["Content-Disposition": "attachment; filename=\"\(fileName)\""])
        case .failure(let error):
            return .jsonWithStatus(error, statusCode: sandboxErrorStatusCode(error.code))
        }
    }
}

// MARK: - SandboxSQLAction

final class SandboxSQLAction: AIAction {
    let module = "sandbox"
    let name = "sql"
    let httpMethod = "GET"
    let summary = "对沙盒中的 SQLite 数据库执行只读查询（仅 SELECT/PRAGMA）"
    let parameters = [
        APIParameterDescriptor(name: "path", type: "String", required: true, description: "数据库文件相对路径"),
        APIParameterDescriptor(name: "sql", type: "String", required: true, description: "SQL 查询语句（仅允许 SELECT 和 PRAGMA）"),
    ]
    let example = APIExample(
        requestURL: "/sandbox/sql?path=Documents/test.db&sql=SELECT%20*%20FROM%20users%20LIMIT%205",
        responseBody: #"{"columns":["id","name","email"],"rows":[{"id":"1","name":"Alice","email":"alice@test.com"}],"rowCount":1}"#
    )

    func execute(params: [String: String]) -> ActionResponse {
        guard let path = params["path"], let sql = params["sql"] else {
            return .error(code: 400, message: "Missing 'path' or 'sql' query parameter")
        }
        return sandboxResult(SandboxInspector.shared.querySQLite(path: path, sql: sql))
    }
}

// MARK: - SandboxWriteAction

final class SandboxWriteAction: AIAction {
    let module = "sandbox"
    let name = "write"
    let httpMethod = "POST"
    let summary = "写入内容到沙盒文件（支持覆盖和追加模式）"
    let parameters = [
        APIParameterDescriptor(name: "path", type: "String", required: true, description: "目标文件相对路径"),
        APIParameterDescriptor(name: "content", type: "String", required: true, description: "写入内容"),
        APIParameterDescriptor(name: "encoding", type: "String", required: false, description: "编码方式：utf8（默认）或 base64"),
        APIParameterDescriptor(name: "append", type: "Bool", required: false, description: "是否追加模式，默认 false（覆盖）"),
    ]
    let example = APIExample(
        requestURL: "/sandbox/write?path=Documents/log.txt&content=hello&append=true",
        responseBody: #"{"success":true,"path":"Documents/log.txt","bytesWritten":5,"message":"File created"}"#
    )

    func execute(params: [String: String]) -> ActionResponse {
        guard let path = params["path"], let content = params["content"] else {
            return .error(code: 400, message: "Missing 'path' or 'content' query parameter")
        }
        let encoding = params["encoding"]
        let append = params["append"].map { $0.lowercased() == "true" }
        return sandboxResult(SandboxInspector.shared.writeFile(path: path, content: content,
                                                               encoding: encoding, append: append))
    }
}

// MARK: - SandboxDeleteAction

final class SandboxDeleteAction: AIAction {
    let module = "sandbox"
    let name = "delete"
    let httpMethod = "POST"
    let summary = "删除沙盒中的文件或目录（目录会被递归删除）"
    let parameters = [
        APIParameterDescriptor(name: "path", type: "String", required: true, description: "要删除的文件或目录的相对路径"),
    ]
    let example = APIExample(
        requestURL: "/sandbox/delete?path=Documents/temp.txt",
        responseBody: #"{"success":true,"path":"Documents/temp.txt","message":"Deleted"}"#
    )

    func execute(params: [String: String]) -> ActionResponse {
        guard let path = params["path"] else {
            return .error(code: 400, message: "Missing 'path' parameter")
        }
        return sandboxResult(SandboxInspector.shared.deleteFile(path: path))
    }
}
