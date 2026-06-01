// SandboxAPITests.swift
// AppProbe Tests
//
// 沙盒文件管理 API 的集成测试：
// - GET /sandbox/list
// - GET /sandbox/file
// - GET /sandbox/download
// - POST /sandbox/write
// - GET /sandbox/sql
// - POST /sandbox/delete
// - 安全校验（路径穿越、非法 SQL）

import Foundation
import UIKit
import Testing
@testable import AppProbe

@Suite("Sandbox API Tests")
@MainActor
struct SandboxAPITests {

    let port: UInt

    init() async throws {
        // 启动服务器
        AppProbeServer.shared.start()
        guard AppProbeServer.shared.isRunning else {
            throw TestError.serverNotRunning
        }
        self.port = AppProbeServer.shared.port

        // 创建测试文件
        TestSandboxHelper.createTestFiles()

        // 等待服务器就绪
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
    }

    // MARK: - GET /sandbox/list

    @Test("GET /sandbox/list 浏览根目录")
    func testListRootDirectory() async throws {
        let result = try await TestHTTPClient.get("/sandbox/list", port: port)

        #expect(result.statusCode == 200)

        let json = try result.json()
        #expect(json["currentPath"] as? String == "")

        let files = json["files"] as? [[String: Any]]
        #expect(files != nil)
        #expect((files?.count ?? 0) > 0)

        // 应该包含 Documents 目录
        let hasDocuments = files?.contains(where: { ($0["name"] as? String) == "Documents" }) ?? false
        #expect(hasDocuments)
    }

    @Test("GET /sandbox/list?path= 浏览子目录")
    func testListSubdirectory() async throws {
        let result = try await TestHTTPClient.get(
            "/sandbox/list?path=\(TestSandboxHelper.testDirectory.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)",
            port: port
        )

        #expect(result.statusCode == 200)

        let json = try result.json()
        let files = json["files"] as? [[String: Any]]
        #expect(files != nil)

        // 应该包含 test.txt
        let hasTestFile = files?.contains(where: { ($0["name"] as? String) == "test.txt" }) ?? false
        #expect(hasTestFile)

        // 应该包含 config.json
        let hasConfig = files?.contains(where: { ($0["name"] as? String) == "config.json" }) ?? false
        #expect(hasConfig)

        // 应该包含 test.db
        let hasDB = files?.contains(where: { ($0["name"] as? String) == "test.db" }) ?? false
        #expect(hasDB)
    }

    @Test("GET /sandbox/list 不存在的目录返回 404")
    func testListNotFound() async throws {
        let result = try await TestHTTPClient.get(
            "/sandbox/list?path=nonexistent_directory_xyz",
            port: port
        )

        #expect(result.statusCode == 404)
    }

    // MARK: - GET /sandbox/file

    @Test("GET /sandbox/file 读取文本文件")
    func testReadTextFile() async throws {
        let path = "\(TestSandboxHelper.testDirectory)/test.txt"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let result = try await TestHTTPClient.get(
            "/sandbox/file?path=\(path)&format=text",
            port: port
        )

        #expect(result.statusCode == 200)

        let json = try result.json()
        #expect(json["name"] as? String == "test.txt")
        #expect(json["textContent"] as? String == "Hello, AppProbe!")
        #expect(json["contentType"] as? String == "text")
    }

    @Test("GET /sandbox/file 读取 JSON 文件")
    func testReadJSONFile() async throws {
        let path = "\(TestSandboxHelper.testDirectory)/config.json"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let result = try await TestHTTPClient.get(
            "/sandbox/file?path=\(path)&format=json",
            port: port
        )

        #expect(result.statusCode == 200)

        let json = try result.json()
        #expect(json["name"] as? String == "config.json")
        #expect(json["contentType"] as? String == "json")

        // textContent 应该是有效的 JSON 字符串
        let content = json["textContent"] as? String
        #expect(content != nil)
        #expect(content?.contains("\"key\"") == true)
    }

    @Test("GET /sandbox/file auto 格式识别 SQLite")
    func testReadSQLiteAuto() async throws {
        let path = "\(TestSandboxHelper.testDirectory)/test.db"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let result = try await TestHTTPClient.get(
            "/sandbox/file?path=\(path)&format=auto",
            port: port
        )

        #expect(result.statusCode == 200)

        let json = try result.json()
        #expect(json["contentType"] as? String == "sqlite")
        #expect(json["downloadUrl"] as? String != nil)
        #expect(json["message"] as? String != nil)
    }

    @Test("GET /sandbox/file 不存在的文件返回 404")
    func testReadFileNotFound() async throws {
        let result = try await TestHTTPClient.get(
            "/sandbox/file?path=nonexistent_file.txt",
            port: port
        )

        #expect(result.statusCode == 404)
    }

    // MARK: - GET /sandbox/download

    @Test("GET /sandbox/download 下载文件")
    func testDownloadFile() async throws {
        let path = "\(TestSandboxHelper.testDirectory)/test.txt"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let result = try await TestHTTPClient.get(
            "/sandbox/download?path=\(path)",
            port: port
        )

        #expect(result.statusCode == 200)

        // 验证内容
        let content = String(data: result.data, encoding: .utf8)
        #expect(content == "Hello, AppProbe!")

        // 验证 Content-Disposition header
        let disposition = result.response?.value(forHTTPHeaderField: "Content-Disposition")
        #expect(disposition?.contains("test.txt") == true)
    }

    // MARK: - POST /sandbox/write

    @Test("POST /sandbox/write 写入新文件")
    func testWriteFile() async throws {
        let writePath = "\(TestSandboxHelper.testDirectory)/written.txt"
        let encodedPath = writePath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let content = "Written by test".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!

        let result = try await TestHTTPClient.post(
            "/sandbox/write?path=\(encodedPath)&content=\(content)&append=false",
            port: port
        )

        #expect(result.statusCode == 200)

        let json = try result.json()
        #expect(json["success"] as? Bool == true)
        #expect(json["bytesWritten"] as? Int == "Written by test".utf8.count)

        // 验证文件确实被写入
        let readResult = try await TestHTTPClient.get(
            "/sandbox/file?path=\(encodedPath)&format=text",
            port: port
        )
        let readJson = try readResult.json()
        #expect(readJson["textContent"] as? String == "Written by test")
    }

    @Test("POST /sandbox/write 追加模式")
    func testWriteAppend() async throws {
        let writePath = "\(TestSandboxHelper.testDirectory)/append_test.txt"
        let encodedPath = writePath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!

        // 先写入
        let content1 = "First".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        _ = try await TestHTTPClient.post(
            "/sandbox/write?path=\(encodedPath)&content=\(content1)&append=false",
            port: port
        )

        // 追加
        let content2 = " Second".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let result = try await TestHTTPClient.post(
            "/sandbox/write?path=\(encodedPath)&content=\(content2)&append=true",
            port: port
        )

        #expect(result.statusCode == 200)

        // 验证内容
        let readResult = try await TestHTTPClient.get(
            "/sandbox/file?path=\(encodedPath)&format=text",
            port: port
        )
        let readJson = try readResult.json()
        #expect(readJson["textContent"] as? String == "First Second")
    }

    // MARK: - GET /sandbox/sql

    @Test("GET /sandbox/sql SELECT 查询")
    func testSQLiteQuery() async throws {
        let dbPath = "\(TestSandboxHelper.testDirectory)/test.db"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let sql = "SELECT * FROM users ORDER BY id"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!

        let result = try await TestHTTPClient.get(
            "/sandbox/sql?path=\(dbPath)&sql=\(sql)",
            port: port
        )

        #expect(result.statusCode == 200)

        let json = try result.json()
        let columns = json["columns"] as? [String]
        #expect(columns?.contains("id") == true)
        #expect(columns?.contains("name") == true)
        #expect(columns?.contains("email") == true)

        let rowCount = json["rowCount"] as? Int
        #expect(rowCount == 2)

        let rows = json["rows"] as? [[String: Any]]
        #expect(rows?.count == 2)

        // 验证第一行数据
        let firstRow = rows?.first
        #expect(firstRow?["name"] as? String == "Alice")
        #expect(firstRow?["email"] as? String == "alice@test.com")
    }

    @Test("GET /sandbox/sql PRAGMA 查询")
    func testSQLitePragma() async throws {
        let dbPath = "\(TestSandboxHelper.testDirectory)/test.db"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let sql = "PRAGMA table_info(users)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!

        let result = try await TestHTTPClient.get(
            "/sandbox/sql?path=\(dbPath)&sql=\(sql)",
            port: port
        )

        #expect(result.statusCode == 200)

        let json = try result.json()
        let rowCount = json["rowCount"] as? Int
        #expect((rowCount ?? 0) > 0)
    }

    @Test("GET /sandbox/sql 非法 SQL 被拒绝")
    func testInvalidSQLRejected() async throws {
        let dbPath = "\(TestSandboxHelper.testDirectory)/test.db"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let sql = "DROP TABLE users"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!

        let result = try await TestHTTPClient.get(
            "/sandbox/sql?path=\(dbPath)&sql=\(sql)",
            port: port
        )

        #expect(result.statusCode == 403)

        let json = try result.json()
        #expect(json["code"] as? String == "invalid_sql")
    }

    @Test("GET /sandbox/sql INSERT 被拒绝")
    func testInsertSQLRejected() async throws {
        let dbPath = "\(TestSandboxHelper.testDirectory)/test.db"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let sql = "INSERT INTO users (name, email) VALUES ('Eve', 'eve@test.com')"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!

        let result = try await TestHTTPClient.get(
            "/sandbox/sql?path=\(dbPath)&sql=\(sql)",
            port: port
        )

        #expect(result.statusCode == 403)

        let json = try result.json()
        #expect(json["code"] as? String == "invalid_sql")
    }

    // MARK: - POST /sandbox/delete

    @Test("POST /sandbox/delete 删除文件")
    func testDeleteFile() async throws {
        // 先写入一个临时文件
        let filePath = "\(TestSandboxHelper.testDirectory)/to_delete.txt"
        let encodedPath = filePath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let content = "delete me".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        _ = try await TestHTTPClient.post(
            "/sandbox/write?path=\(encodedPath)&content=\(content)",
            port: port
        )

        // 删除
        let result = try await TestHTTPClient.post(
            "/sandbox/delete?path=\(encodedPath)",
            port: port
        )

        #expect(result.statusCode == 200)

        let json = try result.json()
        #expect(json["success"] as? Bool == true)

        // 确认已删除
        let readResult = try await TestHTTPClient.get(
            "/sandbox/file?path=\(encodedPath)",
            port: port
        )
        #expect(readResult.statusCode == 404)
    }

    @Test("POST /sandbox/delete 不存在的文件返回 404")
    func testDeleteNotFound() async throws {
        let result = try await TestHTTPClient.post(
            "/sandbox/delete?path=nonexistent_file_xyz.txt",
            port: port
        )

        #expect(result.statusCode == 404)
    }

    // MARK: - 安全校验

    @Test("路径穿越 (..) 被拒绝")
    func testPathTraversalRejected() async throws {
        let result = try await TestHTTPClient.get(
            "/sandbox/list?path=Documents/../../../etc",
            port: port
        )

        #expect(result.statusCode == 403)

        let json = try result.json()
        #expect(json["code"] as? String == "invalid_path")
    }

    @Test("绝对路径被拒绝")
    func testAbsolutePathRejected() async throws {
        let result = try await TestHTTPClient.get(
            "/sandbox/file?path=/etc/passwd",
            port: port
        )

        #expect(result.statusCode == 403)

        let json = try result.json()
        #expect(json["code"] as? String == "invalid_path")
    }

    @Test("POST /sandbox/write 路径穿越被拒绝")
    func testWritePathTraversalRejected() async throws {
        let path = "../../../tmp/evil.txt"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let content = "should not be written"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!

        let result = try await TestHTTPClient.post(
            "/sandbox/write?path=\(path)&content=\(content)",
            port: port
        )

        #expect(result.statusCode == 403)
    }
}
