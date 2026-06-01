// ViewControllerAPITests.swift
// AppProbe Tests
//
// ViewController 层级检查 API 集成测试：
// - GET /vc/hierarchy
// - GET /vc/current

import Foundation
import UIKit
import Testing
@testable import AppProbe

@Suite("ViewController API Tests")
@MainActor
struct ViewControllerAPITests {

    let port: UInt

    init() async throws {
        AppProbeServer.shared.start()
        guard AppProbeServer.shared.isRunning else {
            throw TestError.serverNotRunning
        }
        self.port = AppProbeServer.shared.port
    }

    @Test("GET /vc/hierarchy 返回层级树")
    func testHierarchy() async throws {
        let result = try await TestHTTPClient.get("/vc/hierarchy", port: port)

        #expect(result.statusCode == 200)

        let json = try result.json()
        #expect(json["windowCount"] as? Int != nil)
        #expect((json["windowCount"] as? Int ?? 0) >= 1)

        let scenes = json["scenes"] as? [[String: Any]]
        #expect(scenes != nil)
        #expect((scenes?.count ?? 0) >= 1)

        if let scene = scenes?.first {
            #expect(scene["sceneTitle"] as? String != nil)
            let rootVC = scene["rootViewController"] as? [String: Any]
            #expect(rootVC != nil)
            #expect(rootVC?["className"] as? String != nil)
            #expect(rootVC?["address"] as? String != nil)
            #expect(rootVC?["isViewLoaded"] as? Bool != nil)
            #expect(rootVC?["isVisible"] as? Bool != nil)
        }
    }

    @Test("GET /vc/hierarchy?depth=1 限制递归深度")
    func testHierarchyWithDepth() async throws {
        let result = try await TestHTTPClient.get("/vc/hierarchy?depth=1", port: port)

        #expect(result.statusCode == 200)

        let json = try result.json()
        let scenes = json["scenes"] as? [[String: Any]]
        #expect(scenes != nil)
    }

    @Test("GET /vc/hierarchy?class= 高亮指定类名")
    func testHierarchyWithHighlight() async throws {
        let result = try await TestHTTPClient.get(
            "/vc/hierarchy?class=UIViewController",
            port: port
        )

        #expect(result.statusCode == 200)

        let json = try result.json()
        #expect(json["scenes"] as? [[String: Any]] != nil)
    }

    @Test("GET /vc/current 返回当前顶层 VC")
    func testCurrent() async throws {
        let result = try await TestHTTPClient.get("/vc/current", port: port)

        #expect(result.statusCode == 200)

        let json = try result.json()
        #expect(json["className"] as? String != nil)
        #expect(json["address"] as? String != nil)
        #expect(json["isViewLoaded"] as? Bool != nil)
        #expect(json["isVisible"] as? Bool != nil)
        #expect(json["presentationChain"] as? [String] != nil)
        #expect((json["presentationChain"] as? [String])?.isEmpty == false)
    }

    @Test("VC current 包含 viewAddress")
    func testCurrentHasViewAddress() async throws {
        let result = try await TestHTTPClient.get("/vc/current", port: port)

        #expect(result.statusCode == 200)

        let json = try result.json()
        // 如果 isViewLoaded == true，viewAddress 应该非 nil
        if json["isViewLoaded"] as? Bool == true {
            #expect(json["viewAddress"] as? String != nil)
        }
    }
}
