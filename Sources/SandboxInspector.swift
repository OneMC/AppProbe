// SandboxInspector.swift
// AppProbe
//
// 沙盒文件管理核心实现。提供文件系统操作能力：
// - 目录浏览（listDirectory）
// - 文件读取（readFile），支持 auto/text/json/download 四种格式
// - 文件下载（downloadFile）
// - SQLite 只读查询（querySQLite），仅允许 SELECT 和 PRAGMA
// - 文件写入（writeFile），支持 UTF-8 和 Base64 编码
// - 文件删除（deleteFile），支持递归删除目录
//
// 安全机制：所有路径经过 resolvePath 校验，禁止路径穿越和沙盒外访问

import Foundation
import SQLite3
import os

private let logger = Logger(subsystem: "com.appprobe", category: "sandbox")

// MARK: - SandboxInspector

/// 沙盒文件管理核心类
///
/// 提供对 App 沙盒目录的文件系统操作，所有路径参数均为相对于沙盒根目录的相对路径。
/// 内置路径安全校验，阻止路径穿越攻击。
final class SandboxInspector {
    static let shared = SandboxInspector()

    /// 沙盒根目录 URL
    var sandboxRoot: URL { URL(fileURLWithPath: NSHomeDirectory()) }

    private init() {}

    // MARK: - Path Resolution

    /// 将相对路径解析为安全的沙盒内绝对 URL
    ///
    /// 安全检查：
    /// - 禁止包含 `..`（路径穿越）
    /// - 禁止绝对路径（以 `/` 开头）
    /// - 解析后的路径必须仍在沙盒根目录内
    ///
    /// - Parameter relativePath: 相对于沙盒根目录的路径
    /// - Returns: 解析后的 URL，校验失败返回 nil
    func resolvePath(_ relativePath: String) -> URL? {
        guard !relativePath.contains("..") else {
            logger.warning("[resolvePath] 路径穿越被阻止: \(relativePath)")
            return nil
        }
        guard !relativePath.hasPrefix("/") else {
            logger.warning("[resolvePath] 绝对路径被阻止: \(relativePath)")
            return nil
        }

        let resolved = sandboxRoot.appendingPathComponent(relativePath)
        let resolvedPath = resolved.standardizedFileURL.path
        let rootPath = sandboxRoot.standardizedFileURL.path

        guard resolvedPath.hasPrefix(rootPath) else {
            logger.warning("[resolvePath] 路径超出沙盒范围: \(relativePath)")
            return nil
        }

        logger.debug("[resolvePath] 路径解析成功: \(relativePath) -> \(resolvedPath)")
        return resolved
    }

    // MARK: - List Directory

    /// 列出指定目录中的文件和子目录
    ///
    /// 返回结果按目录优先排序（目录在前，文件在后）。
    /// 自动跳过隐藏文件（以 `.` 开头的文件）。
    func listDirectory(path: String) -> Result<SandboxListResult, SandboxErrorResponse> {
        guard let url = resolvePath(path) else {
            return .failure(SandboxErrorResponse(error: "Invalid path", code: "invalid_path"))
        }

        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            return .failure(SandboxErrorResponse(error: "Path not found", code: "not_found"))
        }
        guard fm.isReadableFile(atPath: url.path) else {
            return .failure(SandboxErrorResponse(error: "Path not readable", code: "not_readable"))
        }

        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        guard isDir else {
            return .failure(SandboxErrorResponse(error: "Not a directory", code: "not_directory"))
        }

        var files: [SandboxFileInfo] = []
        let dateFormatter = ISO8601DateFormatter()
        do {
            let items = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey], options: .skipsHiddenFiles)
            for item in items {
                let name = item.lastPathComponent
                let relativePath = path.isEmpty ? name : "\(path)/\(name)"
                let attrs = try? fm.attributesOfItem(atPath: item.path)
                let size = attrs?[.size] as? Int64 ?? 0
                let modDate = attrs?[.modificationDate] as? Date ?? Date()
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                let isReadable = fm.isReadableFile(atPath: item.path)

                let modDateString = dateFormatter.string(from: modDate)

                files.append(SandboxFileInfo(
                    name: name,
                    path: relativePath,
                    size: size,
                    isDirectory: isDir,
                    modificationDate: modDateString,
                    isReadable: isReadable
                ))
            }
        } catch {
            logger.error("[listDirectory] 目录列举失败: \(error.localizedDescription)")
            return .failure(SandboxErrorResponse(error: "Failed to list directory: \(error.localizedDescription)", code: "list_failed"))
        }

        files.sort { ($0.isDirectory ? 0 : 1) < ($1.isDirectory ? 0 : 1) }
        return .success(SandboxListResult(currentPath: path, files: files))
    }

    // MARK: - Read File

    /// 读取文件内容，根据 format 参数返回不同格式
    ///
    /// 文件类型识别基于扩展名，处理策略：
    /// - `auto`：文本类小文件直接返回内容，SQLite 提示用 SQL 查询，大文件返回下载链接
    /// - `text`：强制 UTF-8 文本读取
    /// - `json`：仅限 .json/.plist 文件
    /// - `download`：始终返回下载链接
    func readFile(path: String, format: SandboxReadFormat) -> Result<SandboxFileContent, SandboxErrorResponse> {
        guard let url = resolvePath(path) else {
            return .failure(SandboxErrorResponse(error: "Invalid path", code: "invalid_path"))
        }

        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            return .failure(SandboxErrorResponse(error: "File not found", code: "not_found"))
        }
        guard !fm.isDirectory(url) else {
            return .failure(SandboxErrorResponse(error: "Path is a directory, use /list", code: "is_directory"))
        }
        guard fm.isReadableFile(atPath: url.path) else {
            return .failure(SandboxErrorResponse(error: "File not readable", code: "not_readable"))
        }

        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        let attrs = try? fm.attributesOfItem(atPath: url.path)
        let size = attrs?[.size] as? Int64 ?? 0

        // 根据扩展名判断文件内容类型
        let contentType: SandboxContentType
        switch ext {
        case "json": contentType = .json
        case "plist": contentType = .plist
        case "db", "sqlite", "sqlite3": contentType = .sqlite
        case "txt", "md", "swift", "m", "h", "log", "csv", "xml", "html", "css", "js": contentType = .text
        default: contentType = .unknown
        }

        let isTextLike = [.text, .json, .plist].contains(contentType)
        let oneMB: Int64 = 1_048_576

        logger.debug("[readFile] 文件: \(name), 扩展名: \(ext), contentType: \(contentType.rawValue), size: \(size), format: \(format.rawValue)")

        switch format {
        case .text:
            guard isTextLike else {
                return .failure(SandboxErrorResponse(error: "File is not text-readable", code: "unsupported_media_type"))
            }
            guard let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .utf8) else {
                return .failure(SandboxErrorResponse(error: "Failed to read file as text", code: "read_failed"))
            }
            return .success(SandboxFileContent(
                name: name, path: path, size: size, contentType: contentType,
                textContent: text, base64Content: nil, downloadUrl: nil, message: nil
            ))

        case .json:
            guard ext == "json" || ext == "plist" else {
                return .failure(SandboxErrorResponse(error: "File is not JSON", code: "unsupported_media_type"))
            }
            guard let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .utf8) else {
                return .failure(SandboxErrorResponse(error: "Failed to read file", code: "read_failed"))
            }
            return .success(SandboxFileContent(
                name: name, path: path, size: size, contentType: contentType,
                textContent: text, base64Content: nil, downloadUrl: nil, message: nil
            ))

        case .download:
            return .success(SandboxFileContent(
                name: name, path: path, size: size, contentType: contentType,
                textContent: nil, base64Content: nil,
                downloadUrl: "/sandbox/download?path=\(path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path)",
                message: nil
            ))

        case .auto:
            if isTextLike && size < oneMB {
                guard let data = try? Data(contentsOf: url),
                      let text = String(data: data, encoding: .utf8) else {
                    return .failure(SandboxErrorResponse(error: "Failed to read file", code: "read_failed"))
                }
                return .success(SandboxFileContent(
                    name: name, path: path, size: size, contentType: contentType,
                    textContent: text, base64Content: nil, downloadUrl: nil, message: nil
                ))
            }

            if contentType == .sqlite {
                return .success(SandboxFileContent(
                    name: name, path: path, size: size, contentType: .sqlite,
                    textContent: nil, base64Content: nil,
                    downloadUrl: "/sandbox/download?path=\(path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path)",
                    message: "SQLite database. Use ?format=download to download, or /sandbox/sql to query."
                ))
            }

            if size < oneMB {
                guard let data = try? Data(contentsOf: url) else {
                    return .failure(SandboxErrorResponse(error: "Failed to read file", code: "read_failed"))
                }
                return .success(SandboxFileContent(
                    name: name, path: path, size: size, contentType: contentType,
                    textContent: nil, base64Content: data.base64EncodedString(),
                    downloadUrl: nil, message: nil
                ))
            }

            return .success(SandboxFileContent(
                name: name, path: path, size: size, contentType: contentType,
                textContent: nil, base64Content: nil,
                downloadUrl: "/sandbox/download?path=\(path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path)",
                message: "File is too large (\(size) bytes). Use ?format=download to download."
            ))
        }
    }

    // MARK: - Download File

    /// 下载文件原始数据
    ///
    /// 以二进制方式读取文件全部内容并返回 Data 对象。
    /// 不支持目录下载。
    func downloadFile(path: String) -> Result<Data, SandboxErrorResponse> {
        guard let url = resolvePath(path) else {
            return .failure(SandboxErrorResponse(error: "Invalid path", code: "invalid_path"))
        }
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            return .failure(SandboxErrorResponse(error: "File not found", code: "not_found"))
        }
        guard !fm.isDirectory(url) else {
            return .failure(SandboxErrorResponse(error: "Path is a directory", code: "is_directory"))
        }
        guard fm.isReadableFile(atPath: url.path) else {
            return .failure(SandboxErrorResponse(error: "File not readable", code: "not_readable"))
        }
        guard let data = try? Data(contentsOf: url) else {
            logger.error("[downloadFile] 读取文件数据失败: \(path)")
            return .failure(SandboxErrorResponse(error: "Failed to read file", code: "read_failed"))
        }
        logger.info("[downloadFile] 下载成功: \(path), 大小: \(data.count) bytes")
        return .success(data)
    }

    // MARK: - SQLite Query

    /// 对 SQLite 数据库执行只读 SQL 查询
    ///
    /// 安全限制：
    /// - 仅允许 SELECT 和 PRAGMA 语句
    /// - 数据库以 SQLITE_OPEN_READONLY 模式打开
    /// - 所有列值以 String 类型返回
    func querySQLite(path: String, sql: String) -> Result<SandboxSQLResult, SandboxErrorResponse> {
        guard let url = resolvePath(path) else {
            return .failure(SandboxErrorResponse(error: "Invalid path", code: "invalid_path"))
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .failure(SandboxErrorResponse(error: "Database file not found", code: "not_found"))
        }

        // 安全检查：仅允许 SELECT 和 PRAGMA 查询
        let upper = sql.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard upper.hasPrefix("SELECT") || upper.hasPrefix("PRAGMA") else {
            logger.warning("[querySQLite] 非法 SQL 语句被阻止: \(sql)")
            return .failure(SandboxErrorResponse(error: "Only SELECT and PRAGMA queries are allowed", code: "invalid_sql"))
        }

        // 以只读模式打开数据库
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            logger.error("[querySQLite] 数据库打开失败: \(path)")
            return .failure(SandboxErrorResponse(error: "Failed to open database", code: "db_open_failed"))
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db)!)
            logger.error("[querySQLite] SQL 预编译失败: \(msg)")
            return .failure(SandboxErrorResponse(error: "SQL error: \(msg)", code: "sql_error"))
        }
        defer { sqlite3_finalize(stmt) }

        let colCount = Int(sqlite3_column_count(stmt))
        var columns: [String] = []
        for i in 0..<colCount {
            guard let cName = sqlite3_column_name(stmt, Int32(i)) else {
                return .failure(SandboxErrorResponse(error: "Failed to read column name", code: "sql_error"))
            }
            let name = String(cString: cName)
            columns.append(name)
        }

        var rows: [[String: String?]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String: String?] = [:]
            for i in 0..<colCount {
                let colName = columns[i]
                if let cStr = sqlite3_column_text(stmt, Int32(i)) {
                    row[colName] = String(cString: cStr)
                } else {
                    row[colName] = nil
                }
            }
            rows.append(row)
        }

        logger.info("[querySQLite] 查询完成, 返回 \(rows.count) 行, \(columns.count) 列")
        return .success(SandboxSQLResult(columns: columns, rows: rows, rowCount: rows.count))
    }

    // MARK: - Write File

    /// 写入内容到沙盒文件
    ///
    /// - Parameters:
    ///   - path: 目标文件相对路径
    ///   - content: 写入内容（UTF-8 字符串或 Base64 编码数据）
    ///   - encoding: 编码方式，`utf8`（默认）或 `base64`
    ///   - append: 是否追加模式，默认覆盖写入。父目录不存在时会自动创建
    func writeFile(path: String, content: String, encoding: String?, append: Bool?) -> Result<SandboxWriteResponse, SandboxErrorResponse> {
        guard let url = resolvePath(path) else {
            return .failure(SandboxErrorResponse(error: "Invalid path", code: "invalid_path"))
        }

        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) && fm.isDirectory(url) {
            return .failure(SandboxErrorResponse(error: "Path is a directory", code: "is_directory"))
        }

        let parentDir = url.deletingLastPathComponent()
        if !fm.fileExists(atPath: parentDir.path) {
            // 父目录不存在时，检查最近已存在的祖先目录是否可写
            var ancestor = parentDir
            while !fm.fileExists(atPath: ancestor.path) {
                ancestor = ancestor.deletingLastPathComponent()
            }
            guard fm.isWritableFile(atPath: ancestor.path) else {
                return .failure(SandboxErrorResponse(error: "Path not writable", code: "not_writable"))
            }
            do {
                try fm.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil)
            } catch {
                return .failure(SandboxErrorResponse(error: "Failed to create parent directory: \(error.localizedDescription)", code: "write_failed"))
            }
        } else {
            guard fm.isWritableFile(atPath: parentDir.path) else {
                return .failure(SandboxErrorResponse(error: "Path not writable", code: "not_writable"))
            }
        }

        let isAppend = append ?? false
        let enc = encoding?.lowercased() ?? "utf8"
        let fileExistedBefore = fm.fileExists(atPath: url.path)
        logger.debug("[writeFile] 参数: path=\(path), encoding=\(enc), append=\(isAppend)")

        // 解码写入数据
        let data: Data
        if enc == "base64" {
            guard let decoded = Data(base64Encoded: content) else {
                logger.error("[writeFile] Base64 解码失败")
                return .failure(SandboxErrorResponse(error: "Invalid base64 content", code: "invalid_encoding"))
            }
            data = decoded
        } else {
            guard let utf8Data = content.data(using: .utf8) else {
                logger.error("[writeFile] UTF-8 编码失败")
                return .failure(SandboxErrorResponse(error: "Invalid UTF-8 content", code: "invalid_encoding"))
            }
            data = utf8Data
        }

        // 执行写入
        do {
            if isAppend && fm.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                if #available(iOS 13.4, *) {
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    try handle.close()
                } else {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try data.write(to: url)
            }
        } catch {
            logger.error("[writeFile] 写入失败: \(error.localizedDescription)")
            return .failure(SandboxErrorResponse(error: "Failed to write file: \(error.localizedDescription)", code: "write_failed"))
        }

        let message: String
        if isAppend {
            message = "Content appended"
        } else if fileExistedBefore {
            message = "File overwritten"
        } else {
            message = "File created"
        }
        logger.info("[writeFile] 写入成功: \(path), \(data.count) bytes, \(message)")
        return .success(SandboxWriteResponse(
            success: true, path: path, bytesWritten: data.count, message: message
        ))
    }

    // MARK: - Delete File/Directory

    /// 删除文件或目录
    ///
    /// 如果目标是目录，会递归删除其中所有内容。此操作不可逆。
    func deleteFile(path: String) -> Result<SandboxDeleteResponse, SandboxErrorResponse> {
        guard let url = resolvePath(path) else {
            return .failure(SandboxErrorResponse(error: "Invalid path", code: "invalid_path"))
        }

        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            return .failure(SandboxErrorResponse(error: "File or directory not found", code: "not_found"))
        }

        do {
            try fm.removeItem(at: url)
        } catch {
            logger.error("[deleteFile] 删除失败: \(error.localizedDescription)")
            return .failure(SandboxErrorResponse(error: "Failed to delete: \(error.localizedDescription)", code: "delete_failed"))
        }

        logger.info("[deleteFile] 删除成功: \(path)")
        return .success(SandboxDeleteResponse(
            success: true, path: path, message: "Deleted"
        ))
    }

    // MARK: - UserDefaults

    /// 列举 UserDefaults 中的所有键值对
    func listUserDefaults(suite: String?, prefix: String?, search: String?) -> Result<UserDefaultsListResponse, SandboxErrorResponse> {
        let defaults = resolveDefaults(suite: suite)
        let suiteName = suite ?? "standard"

        let allDict = defaults.dictionaryRepresentation()
        var entries: [UserDefaultsEntry] = []

        for (key, value) in allDict.sorted(by: { $0.key < $1.key }) {
            if let prefix = prefix, !key.hasPrefix(prefix) { continue }
            if let search = search, !key.localizedCaseInsensitiveContains(search) { continue }

            let typeName = userDefaultsTypeName(for: value)
            let valueSummary = userDefaultsValueSummary(for: value)
            entries.append(UserDefaultsEntry(key: key, type: typeName, value: valueSummary))
        }

        return .success(UserDefaultsListResponse(suite: suiteName, count: entries.count, entries: entries))
    }

    /// 获取 UserDefaults 中指定 key 的值
    func getUserDefault(key: String, suite: String?) -> UserDefaultsGetResponse {
        let defaults = resolveDefaults(suite: suite)
        let suiteName = suite ?? "standard"

        guard let value = defaults.object(forKey: key) else {
            return UserDefaultsGetResponse(suite: suiteName, key: key, type: "nil", value: nil, found: false)
        }

        let typeName = userDefaultsTypeName(for: value)
        let codableValue = convertToCodableValue(value)
        return UserDefaultsGetResponse(suite: suiteName, key: key, type: typeName, value: codableValue, found: true)
    }

    /// 设置 UserDefaults 值
    func setUserDefault(key: String, value: String, type: String, suite: String?) -> Result<UserDefaultsSetResponse, SandboxErrorResponse> {
        let defaults = resolveDefaults(suite: suite)

        switch type.lowercased() {
        case "string":
            defaults.set(value, forKey: key)
        case "int":
            guard let intValue = Int(value) else {
                return .failure(SandboxErrorResponse(error: "Cannot parse '\(value)' as Int", code: "invalid_encoding"))
            }
            defaults.set(intValue, forKey: key)
        case "double":
            guard let doubleValue = Double(value) else {
                return .failure(SandboxErrorResponse(error: "Cannot parse '\(value)' as Double", code: "invalid_encoding"))
            }
            defaults.set(doubleValue, forKey: key)
        case "bool":
            let boolValue = (value.lowercased() == "true" || value == "1")
            defaults.set(boolValue, forKey: key)
        default:
            return .failure(SandboxErrorResponse(error: "Unsupported type: \(type). Use string/int/double/bool", code: "invalid_encoding"))
        }

        return .success(UserDefaultsSetResponse(success: true, key: key, type: type, value: value, message: "Value set"))
    }

    /// 删除 UserDefaults 中的指定 key
    func deleteUserDefault(key: String, suite: String?) -> UserDefaultsDeleteResponse {
        let defaults = resolveDefaults(suite: suite)
        defaults.removeObject(forKey: key)
        return UserDefaultsDeleteResponse(success: true, key: key, message: "Key removed")
    }

    // MARK: - UserDefaults Helpers

    private func resolveDefaults(suite: String?) -> UserDefaults {
        if let suite = suite, !suite.isEmpty, suite != "standard" {
            return UserDefaults(suiteName: suite) ?? .standard
        }
        return .standard
    }

    private func userDefaultsTypeName(for value: Any) -> String {
        // 使用 CFGetTypeID 精确区分 Bool 和 Int（两者在 ObjC 中均为 NSNumber）
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return "Bool"
            }
            // 通过 objCType 区分 Int 和 Double
            let objCType = String(cString: number.objCType)
            switch objCType {
            case "d", "f": return "Double"
            default: return "Int"
            }
        }
        switch value {
        case is String: return "String"
        case is Data: return "Data"
        case is [Any]: return "Array"
        case is [String: Any]: return "Dictionary"
        default: return String(describing: type(of: value))
        }
    }

    private func userDefaultsValueSummary(for value: Any) -> String {
        switch value {
        case let boolValue as Bool:
            return boolValue ? "true" : "false"
        case let stringValue as String:
            if stringValue.count > 100 {
                return String(stringValue.prefix(100)) + "..."
            }
            return stringValue
        case let arrayValue as [Any]:
            return "[Array(\(arrayValue.count) items)]"
        case let dictValue as [String: Any]:
            return "[Dict(\(dictValue.count) keys)]"
        case let dataValue as Data:
            return "[Data(\(dataValue.count) bytes)]"
        default:
            return String(describing: value)
        }
    }

    private func convertToCodableValue(_ value: Any) -> AnyCodableValue {
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            let objCType = String(cString: number.objCType)
            switch objCType {
            case "d", "f": return .double(number.doubleValue)
            default: return .int(number.intValue)
            }
        }
        switch value {
        case let stringValue as String:
            return .string(stringValue)
        case let dataValue as Data:
            return .data(dataValue.base64EncodedString())
        case let arrayValue as [Any]:
            return .array(arrayValue.map { convertToCodableValue($0) })
        case let dictValue as [String: Any]:
            var result: [String: AnyCodableValue] = [:]
            for (k, v) in dictValue {
                result[k] = convertToCodableValue(v)
            }
            return .dictionary(result)
        default:
            return .string(String(describing: value))
        }
    }
}

// MARK: - FileManager Helper

private extension FileManager {
    func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}
