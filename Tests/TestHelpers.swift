// TestHelpers.swift
// AppProbe Tests
//
// 测试辅助工具：HTTP 请求封装、测试视图构建、临时文件管理

import Foundation
import UIKit
import SQLite3
import Testing
@testable import AppProbe

// MARK: - HTTP Response Wrapper

struct HTTPResult {
    let statusCode: Int
    let data: Data
    let response: HTTPURLResponse?

    func json() throws -> [String: Any] {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TestError.invalidJSON
        }
        return dict
    }
}

enum TestError: Error {
    case invalidJSON
    case noResponse
    case serverNotRunning
}

// MARK: - HTTP Client

/// 简单的同步/异步 HTTP 客户端，用于向本地 AppProbe 服务器发请求
enum TestHTTPClient {

    /// 发送 GET 请求
    static func get(_ path: String, port: UInt) async throws -> HTTPResult {
        let url = URL(string: "http://localhost:\(port)\(path)")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TestError.noResponse
        }
        return HTTPResult(statusCode: httpResponse.statusCode, data: data, response: httpResponse)
    }

    /// 发送 POST 请求（JSON body）
    static func post(_ path: String, port: UInt, body: [String: Any]) async throws -> HTTPResult {
        let url = URL(string: "http://localhost:\(port)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TestError.noResponse
        }
        return HTTPResult(statusCode: httpResponse.statusCode, data: data, response: httpResponse)
    }

    /// 发送 POST 请求（无 body，参数通过 query string）
    static func post(_ path: String, port: UInt) async throws -> HTTPResult {
        let url = URL(string: "http://localhost:\(port)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TestError.noResponse
        }
        return HTTPResult(statusCode: httpResponse.statusCode, data: data, response: httpResponse)
    }

    /// 发送 DELETE 请求
    static func delete(_ path: String, port: UInt) async throws -> HTTPResult {
        let url = URL(string: "http://localhost:\(port)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TestError.noResponse
        }
        return HTTPResult(statusCode: httpResponse.statusCode, data: data, response: httpResponse)
    }
}

// MARK: - Test View Builder

/// 构建用于测试的 UIView 层级
@MainActor
enum TestViewBuilder {

    /// 创建测试视图树并添加到 keyWindow
    /// - Returns: 容器视图（用于 tearDown 时移除）
    @discardableResult
    static func createTestViews() -> UIView {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        container.tag = 999 // 容器标识
        container.backgroundColor = .white

        // UILabel with tag 100
        let label = UILabel(frame: CGRect(x: 20, y: 20, width: 200, height: 44))
        label.tag = 100
        label.text = "Test Label"
        label.font = .systemFont(ofSize: 17)
        label.textColor = .black
        label.textAlignment = .natural
        container.addSubview(label)

        // UIButton with tag 200
        let button = UIButton(type: .system)
        button.frame = CGRect(x: 20, y: 80, width: 200, height: 44)
        button.tag = 200
        button.setTitle("Test Button", for: .normal)
        container.addSubview(button)

        // UIImageView with tag 300
        let imageView = UIImageView(frame: CGRect(x: 20, y: 140, width: 100, height: 100))
        imageView.tag = 300
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .lightGray
        container.addSubview(imageView)

        // 添加到 keyWindow
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first {
            window.addSubview(container)
        }

        return container
    }

    /// 移除测试视图
    static func removeTestViews(_ container: UIView) {
        container.removeFromSuperview()
    }
}

// MARK: - Test Sandbox Helper

/// 管理测试用的沙盒临时文件
enum TestSandboxHelper {

    static let testDirectory = "Documents/_viewinspector_test"

    /// 创建测试用临时文件
    static func createTestFiles() {
        let fm = FileManager.default
        let root = NSHomeDirectory()
        let testDir = (root as NSString).appendingPathComponent(testDirectory)

        // 创建测试目录
        try? fm.createDirectory(atPath: testDir, withIntermediateDirectories: true)

        // 创建文本文件
        let textFile = (testDir as NSString).appendingPathComponent("test.txt")
        try? "Hello, AppProbe!".write(toFile: textFile, atomically: true, encoding: .utf8)

        // 创建 JSON 文件
        let jsonFile = (testDir as NSString).appendingPathComponent("config.json")
        try? "{\"key\": \"value\", \"number\": 42}".write(toFile: jsonFile, atomically: true, encoding: .utf8)

        // 创建测试 SQLite 数据库
        createTestDatabase(at: testDir)
    }

    /// 创建测试用 SQLite 数据库
    private static func createTestDatabase(at directory: String) {
        let dbPath = (directory as NSString).appendingPathComponent("test.db")
        var db: OpaquePointer?

        guard sqlite3_open(dbPath, &db) == SQLITE_OK else { return }
        defer { sqlite3_close(db) }

        let createSQL = """
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY,
                name TEXT NOT NULL,
                email TEXT
            );
            INSERT OR REPLACE INTO users (id, name, email) VALUES (1, 'Alice', 'alice@test.com');
            INSERT OR REPLACE INTO users (id, name, email) VALUES (2, 'Bob', 'bob@test.com');
            """

        sqlite3_exec(db, createSQL, nil, nil, nil)
    }

    /// 清理测试文件
    static func cleanup() {
        let root = NSHomeDirectory()
        let testDir = (root as NSString).appendingPathComponent(testDirectory)
        try? FileManager.default.removeItem(atPath: testDir)
    }
}
