// UserDefaultsAPITests.swift
// AppProbe Tests
//
// UserDefaults 读写 API 集成测试：
// - GET /userDefaults（列举/获取）
// - POST /userDefaults/set（设置）
// - POST /userDefaults/delete（删除）

import Foundation
import Testing
@testable import AppProbe

@Suite("UserDefaults API Tests")
@MainActor
struct UserDefaultsAPITests {

    let port: UInt

    init() async throws {
        AppProbeServer.shared.start()
        guard AppProbeServer.shared.isRunning else {
            throw TestError.serverNotRunning
        }
        self.port = AppProbeServer.shared.port

        // 写入测试数据
        UserDefaults.standard.set("test_value", forKey: "_aidebug_test_string")
        UserDefaults.standard.set(42, forKey: "_aidebug_test_int")
        UserDefaults.standard.set(true, forKey: "_aidebug_test_bool")
    }

    @Test("列举所有 UserDefaults key")
    func testListAll() async throws {
        let result = try await TestHTTPClient.get("/userDefaults", port: port)

        #expect(result.statusCode == 200)

        let json = try result.json()
        #expect(json["suite"] as? String == "standard")
        #expect(json["count"] as? Int != nil)
        #expect((json["count"] as? Int ?? 0) > 0)

        let entries = json["entries"] as? [[String: Any]]
        #expect(entries != nil)
        #expect((entries?.count ?? 0) > 0)

        // 每个条目有 key/type/value
        if let entry = entries?.first {
            #expect(entry["key"] as? String != nil)
            #expect(entry["type"] as? String != nil)
            #expect(entry["value"] as? String != nil)
        }
    }

    @Test("按 prefix 过滤")
    func testListByPrefix() async throws {
        let result = try await TestHTTPClient.get(
            "/userDefaults?prefix=_aidebug_test_",
            port: port
        )

        #expect(result.statusCode == 200)

        let json = try result.json()
        let entries = json["entries"] as? [[String: Any]]
        #expect(entries != nil)
        #expect((entries?.count ?? 0) >= 3)

        if let entries = entries {
            for entry in entries {
                let key = entry["key"] as? String ?? ""
                #expect(key.hasPrefix("_aidebug_test_"))
            }
        }
    }

    @Test("按 search 关键词过滤")
    func testListBySearch() async throws {
        let result = try await TestHTTPClient.get(
            "/userDefaults?search=_aidebug_test_string",
            port: port
        )

        #expect(result.statusCode == 200)

        let json = try result.json()
        let entries = json["entries"] as? [[String: Any]]
        #expect(entries != nil)
        #expect((entries?.count ?? 0) >= 1)
    }

    @Test("精确获取指定 key")
    func testGetByKey() async throws {
        let result = try await TestHTTPClient.get(
            "/userDefaults?key=_aidebug_test_string",
            port: port
        )

        #expect(result.statusCode == 200)

        let json = try result.json()
        #expect(json["key"] as? String == "_aidebug_test_string")
        #expect(json["found"] as? Bool == true)
        #expect(json["type"] as? String == "String")
    }

    @Test("获取不存在的 key 返回 found=false")
    func testGetNonexistentKey() async throws {
        let result = try await TestHTTPClient.get(
            "/userDefaults?key=_aidebug_nonexistent_xyz_123",
            port: port
        )

        #expect(result.statusCode == 200)

        let json = try result.json()
        #expect(json["found"] as? Bool == false)
    }

    @Test("设置 string 类型值")
    func testSetString() async throws {
        let result = try await TestHTTPClient.post(
            "/userDefaults/set?key=_aidebug_set_test&value=hello&type=string",
            port: port
        )

        #expect(result.statusCode == 200)

        let json = try result.json()
        #expect(json["success"] as? Bool == true)
        #expect(json["key"] as? String == "_aidebug_set_test")
        #expect(json["type"] as? String == "string")

        // 验证实际写入
        #expect(UserDefaults.standard.string(forKey: "_aidebug_set_test") == "hello")

        // 清理
        UserDefaults.standard.removeObject(forKey: "_aidebug_set_test")
    }

    @Test("设置 int 类型值")
    func testSetInt() async throws {
        let result = try await TestHTTPClient.post(
            "/userDefaults/set?key=_aidebug_set_int&value=99&type=int",
            port: port
        )

        #expect(result.statusCode == 200)

        let json = try result.json()
        #expect(json["success"] as? Bool == true)

        #expect(UserDefaults.standard.integer(forKey: "_aidebug_set_int") == 99)

        UserDefaults.standard.removeObject(forKey: "_aidebug_set_int")
    }

    @Test("设置 bool 类型值")
    func testSetBool() async throws {
        let result = try await TestHTTPClient.post(
            "/userDefaults/set?key=_aidebug_set_bool&value=true&type=bool",
            port: port
        )

        #expect(result.statusCode == 200)

        let json = try result.json()
        #expect(json["success"] as? Bool == true)

        #expect(UserDefaults.standard.bool(forKey: "_aidebug_set_bool") == true)

        UserDefaults.standard.removeObject(forKey: "_aidebug_set_bool")
    }

    @Test("删除 key")
    func testDelete() async throws {
        // 先设置一个值
        UserDefaults.standard.set("to_delete", forKey: "_aidebug_delete_test")

        let result = try await TestHTTPClient.post(
            "/userDefaults/delete?key=_aidebug_delete_test",
            port: port
        )

        #expect(result.statusCode == 200)

        let json = try result.json()
        #expect(json["success"] as? Bool == true)
        #expect(json["key"] as? String == "_aidebug_delete_test")

        // 验证已删除
        #expect(UserDefaults.standard.object(forKey: "_aidebug_delete_test") == nil)
    }

    @Test("set 缺少必要参数返回错误")
    func testSetMissingParams() async throws {
        let result = try await TestHTTPClient.post(
            "/userDefaults/set?key=test",
            port: port
        )

        #expect(result.statusCode == 400)
    }
}
