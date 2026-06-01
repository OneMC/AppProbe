// AppProbeAPITests.swift
// AppProbe Tests
//
// 视图检查 API 的集成测试：
// - GET /status
// - GET /view/hierarchy (tag/class/address/无参数)
// - GET /view/highlight (tag/address)
// - GET /view/screenshot

import Foundation
import UIKit
import Testing
@testable import AppProbe

@Suite("AppProbe API Tests")
@MainActor
struct AppProbeAPITests {

    let port: UInt

    /// 测试视图容器
    let container: UIView

    init() async throws {
        // 启动服务器
        AppProbeServer.shared.start()
        guard AppProbeServer.shared.isRunning else {
            throw TestError.serverNotRunning
        }
        self.port = AppProbeServer.shared.port

        // 创建测试视图
        self.container = TestViewBuilder.createTestViews()

        // 等待视图渲染完成
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
    }

    // MARK: - GET /status

    @Test("GET /status 返回正确的状态信息")
    func testStatusEndpoint() async throws {
        let result = try await TestHTTPClient.get("/status", port: port)

        #expect(result.statusCode == 200)

        let json = try result.json()
        #expect(json["status"] as? String == "ok")
        #expect(json["serverVersion"] as? String == "1.0.0")
        #expect(json["windowCount"] as? Int != nil)
        #expect((json["windowCount"] as? Int ?? 0) > 0)
    }

    // MARK: - GET /view/hierarchy

    @Test("GET /view/hierarchy?tag= 通过 tag 找到视图")
    func testInspectByTag() async throws {
        let result = try await TestHTTPClient.get("/view/hierarchy?tag=100", port: port)

        #expect(result.statusCode == 200)

        let json = try result.json()
        #expect(json["found"] as? Bool == true)

        // 验证 target 信息
        let target = json["target"] as? [String: Any]
        #expect(target != nil)
        #expect(target?["className"] as? String == "UILabel")
        #expect(target?["tag"] as? Int == 100)
        #expect(target?["isHidden"] as? Bool == false)

        // 验证层级树
        let hierarchy = json["hierarchy"] as? [String: Any]
        #expect(hierarchy != nil)
        #expect(hierarchy?["depth"] as? Int != nil)

        // 验证搜索信息
        let searched = json["searched"] as? [String: Any]
        #expect(searched != nil)
        #expect(searched?["tag"] as? Int == 100)
        #expect((searched?["totalViewsScanned"] as? Int ?? 0) > 0)
    }

    @Test("GET /view/hierarchy?class= 通过类名找到视图")
    func testInspectByClass() async throws {
        let result = try await TestHTTPClient.get("/view/hierarchy?class=UILabel", port: port)

        #expect(result.statusCode == 200)

        let json = try result.json()
        #expect(json["found"] as? Bool == true)

        let target = json["target"] as? [String: Any]
        #expect(target?["className"] as? String == "UILabel")
    }

    @Test("GET /view/hierarchy?tag= 未找到视图返回 404")
    func testInspectNotFound() async throws {
        let result = try await TestHTTPClient.get("/view/hierarchy?tag=88888", port: port)

        #expect(result.statusCode == 404)

        let json = try result.json()
        #expect(json["found"] as? Bool == false)
        #expect(json["error"] as? String != nil)
        #expect((json["error"] as? String)?.contains("not found") == true)

        // 验证搜索信息
        let searched = json["searched"] as? [String: Any]
        #expect(searched != nil)
        #expect(searched?["tag"] as? Int == 88888)
        #expect((searched?["totalViewsScanned"] as? Int ?? 0) > 0)
    }

    @Test("GET /view/hierarchy 无参数返回 keyWindow 完整层级")
    func testInspectFullHierarchy() async throws {
        let result = try await TestHTTPClient.get("/view/hierarchy", port: port)

        #expect(result.statusCode == 200)

        let json = try result.json()
        #expect(json["found"] as? Bool == true)

        // 无参数时 target 为 nil，hierarchy 包含完整层级
        let hierarchy = json["hierarchy"] as? [String: Any]
        #expect(hierarchy != nil)
        #expect(hierarchy?["depth"] as? Int != nil)
        #expect((hierarchy?["subviewCount"] as? Int ?? 0) > 0)
    }

    @Test("GET /view/hierarchy?includeSubviews=false 不包含层级树")
    func testInspectWithoutSubviews() async throws {
        let result = try await TestHTTPClient.get("/view/hierarchy?tag=100&includeSubviews=false", port: port)

        #expect(result.statusCode == 200)

        let json = try result.json()
        #expect(json["found"] as? Bool == true)

        // hierarchy 应为 null
        let hierarchy = json["hierarchy"]
        #expect(hierarchy is NSNull || hierarchy == nil)
    }

    @Test("GET /view/hierarchy?tag= 验证 UIButton 信息")
    func testInspectButton() async throws {
        let result = try await TestHTTPClient.get("/view/hierarchy?tag=200", port: port)

        #expect(result.statusCode == 200)

        let json = try result.json()
        #expect(json["found"] as? Bool == true)

        let target = json["target"] as? [String: Any]
        #expect(target?["tag"] as? Int == 200)
    }

    // MARK: - GET /view/highlight

    @Test("GET /view/highlight?tag= 高亮视图并返回图片")
    func testHighlightByTag() async throws {
        let result = try await TestHTTPClient.get("/view/highlight?tag=100&borderColor=FF0000&borderWidth=3", port: port)

        #expect(result.statusCode == 200)

        // 验证返回的是图片二进制
        let contentType = result.response?.value(forHTTPHeaderField: "Content-Type")
        #expect(contentType?.contains("image/jpeg") == true)
        #expect(result.data.count > 0)

        // 验证元数据 headers
        #expect(result.response?.value(forHTTPHeaderField: "X-Image-Width") != nil)
        #expect(result.response?.value(forHTTPHeaderField: "X-Image-Height") != nil)
        #expect(result.response?.value(forHTTPHeaderField: "X-Original-Width") != nil)
        #expect(result.response?.value(forHTTPHeaderField: "X-Original-Height") != nil)
        #expect(result.response?.value(forHTTPHeaderField: "X-Image-Format") == "jpeg")
        #expect(result.response?.value(forHTTPHeaderField: "X-Image-Quality") == "0.75")
        #expect(result.response?.value(forHTTPHeaderField: "X-Image-Scale") != nil)
    }

    @Test("GET /view/highlight?tag= 视图不存在返回 404")
    func testHighlightNotFound() async throws {
        let result = try await TestHTTPClient.get("/view/highlight?tag=88888", port: port)

        #expect(result.statusCode == 404)

        let body = String(data: result.data, encoding: .utf8)
        #expect(body?.contains("View not found") == true)
    }

    @Test("GET /view/highlight 缺少参数返回 400")
    func testHighlightMissingParams() async throws {
        let result = try await TestHTTPClient.get("/view/highlight?borderColor=FF0000", port: port)

        #expect(result.statusCode == 400)

        let body = String(data: result.data, encoding: .utf8)
        #expect(body?.contains("Missing") == true)
    }

    // MARK: - GET /view/screenshot

    @Test("GET /view/screenshot?tag= 截取指定视图")
    func testScreenshotByTag() async throws {
        let result = try await TestHTTPClient.get("/view/screenshot?tag=100", port: port)

        #expect(result.statusCode == 200)

        // 验证返回的是图片二进制
        let contentType = result.response?.value(forHTTPHeaderField: "Content-Type")
        #expect(contentType?.contains("image/jpeg") == true)
        #expect(result.data.count > 0)

        // 验证元数据 headers
        #expect(result.response?.value(forHTTPHeaderField: "X-Image-Width") != nil)
        #expect(result.response?.value(forHTTPHeaderField: "X-Image-Height") != nil)
        #expect(result.response?.value(forHTTPHeaderField: "X-Original-Width") != nil)
        #expect(result.response?.value(forHTTPHeaderField: "X-Original-Height") != nil)
        #expect(result.response?.value(forHTTPHeaderField: "X-Image-Format") == "jpeg")
        #expect(result.response?.value(forHTTPHeaderField: "X-Image-Quality") == "0.75")
        #expect(result.response?.value(forHTTPHeaderField: "X-Image-Scale") == "1.0")
    }

    @Test("GET /view/screenshot 无参数截取 keyWindow")
    func testScreenshotFullWindow() async throws {
        let result = try await TestHTTPClient.get("/view/screenshot", port: port)

        #expect(result.statusCode == 200)

        // 验证返回的是图片二进制
        let contentType = result.response?.value(forHTTPHeaderField: "Content-Type")
        #expect(contentType?.contains("image/jpeg") == true)
        #expect(result.data.count > 0)
    }

    @Test("GET /view/screenshot?tag= 视图不存在返回 404")
    func testScreenshotNotFound() async throws {
        let result = try await TestHTTPClient.get("/view/screenshot?tag=88888", port: port)

        #expect(result.statusCode == 404)

        let body = String(data: result.data, encoding: .utf8)
        #expect(body?.contains("View not found") == true)
    }
}
