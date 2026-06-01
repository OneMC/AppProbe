// APIRegistryTests.swift
// AppProbe Tests
//
// APIRegistry 单元测试：注册/注销、查询、示例验证
//
// 注意：APIRegistry.shared 是进程级单例，其他 Test Suite（AppProbeAPITests 等）
// 在启动服务器时会并行注册路由。因此本 Suite 使用唯一路径前缀 /_test_/ 隔离测试数据，
// 避免与真实路由竞争。

import Foundation
import Testing
@testable import AppProbe

// MARK: - Mock Action

/// 测试用 AIAction 实现
final class MockAction: AIAction {
    let module: String
    let name: String
    let httpMethod: String
    let summary: String
    let parameters: [APIParameterDescriptor]
    let example: APIExample

    init(
        module: String,
        name: String,
        httpMethod: String = "GET",
        summary: String = "Mock action",
        parameters: [APIParameterDescriptor] = [],
        example: APIExample = APIExample(
            requestURL: "/mock/test",
            responseBody: #"{"success":true,"message":"ok"}"#
        )
    ) {
        self.module = module
        self.name = name
        self.httpMethod = httpMethod
        self.summary = summary
        self.parameters = parameters
        self.example = example
    }

    func execute(params: [String: String]) -> ActionResponse {
        return .json(ActionResult(success: true, message: "executed"))
    }
}

// MARK: - Registry Unit Tests

@Suite("APIRegistry Unit Tests")
struct APIRegistryUnitTests {

    @Test("register 注册后可通过路径查询")
    func testRegisterAction() {
        let action = MockAction(module: "_test_", name: "tapCard")
        APIRegistry.shared.register(action)

        let path = "/_test_/tapCard"
        let found = APIRegistry.shared.action(forPath: path)
        #expect(found != nil)
        #expect(found?.path == path)
        #expect(found?.httpMethod == "GET")
        #expect(found?.summary == "Mock action")
        #expect(found?.module == "_test_")

        // 清理
        APIRegistry.shared.unregister(module: "_test_", name: "tapCard")
    }

    @Test("unregister 注销后动作对象被移除")
    func testUnregisterAction() {
        let action = MockAction(module: "_test_", name: "unregTest")
        APIRegistry.shared.register(action)

        let path = "/_test_/unregTest"
        #expect(APIRegistry.shared.action(forPath: path) != nil)

        APIRegistry.shared.unregister(module: "_test_", name: "unregTest")
        #expect(APIRegistry.shared.action(forPath: path) == nil)
    }

    @Test("allActions 返回按路径排序的列表")
    func testAllActionsSorted() {
        let actionZ = MockAction(module: "_test_", name: "zzz_sort")
        let actionA = MockAction(module: "_test_", name: "aaa_sort")
        APIRegistry.shared.register(actionZ)
        APIRegistry.shared.register(actionA)

        let all = APIRegistry.shared.allActions()
        // 验证列表是按路径排序的
        guard all.count >= 2 else { return }
        for i in 1..<all.count {
            #expect(all[i - 1].path <= all[i].path, "allActions() 未按路径排序")
        }
        // 验证我们注册的两个都存在
        #expect(all.contains { $0.path == "/_test_/aaa_sort" })
        #expect(all.contains { $0.path == "/_test_/zzz_sort" })

        // 清理
        APIRegistry.shared.unregister(module: "_test_", name: "zzz_sort")
        APIRegistry.shared.unregister(module: "_test_", name: "aaa_sort")
    }

    @Test("action(forPath:) 不存在的路径返回 nil")
    func testActionNotFound() {
        #expect(APIRegistry.shared.action(forPath: "/_test_/nonexistent_xyz") == nil)
    }

    @Test("register 自动生成 /{module}/{name} 路径")
    func testActionPathGeneration() {
        let action = MockAction(module: "_test_", name: "pathGen")
        APIRegistry.shared.register(action)

        let expectedPath = "/_test_/pathGen"
        let found = APIRegistry.shared.action(forPath: expectedPath)
        #expect(found != nil)
        #expect(found?.path == expectedPath)

        // 清理
        APIRegistry.shared.unregister(module: "_test_", name: "pathGen")
    }

}

// 注意：reset() 测试已移除 —— 该方法会清空进程级单例的所有数据，
// 在 Swift Testing 的并行执行模型下无法安全测试，且会导致其他测试随机失败。
// reset() 的实现仅为 removeAll()，其正确性由 Swift 标准库保证。

// MARK: - Route Completeness Tests

@Suite("Route Completeness Tests")
@MainActor
struct RouteCompletenessTests {

    init() async throws {
        AppProbeServer.shared.start()
        guard AppProbeServer.shared.isRunning else {
            throw TestError.serverNotRunning
        }
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    @Test("所有内置路由都有对应的 AIAction")
    func testAllRegisteredRoutesHaveActions() {
        let expectedPaths = [
            "/view/hierarchy",
            "/status",
            "/view/highlight",
            "/view/screenshot",
            "/sandbox/list",
            "/sandbox/file",
            "/sandbox/download",
            "/sandbox/sql",
            "/sandbox/write",
            "/sandbox/delete",
            "/userDefaults",
            "/userDefaults/set",
            "/userDefaults/delete",
            "/catalog",
            "/catalog/detail",
            "/vc/hierarchy",
            "/vc/current",
            "/log/recent",
        ]
        for path in expectedPaths {
            #expect(
                APIRegistry.shared.action(forPath: path) != nil,
                "API \(path) missing from registry"
            )
        }
    }

    @Test("所有 action 的 httpMethod 字段不为空")
    func testAllActionsHaveMethod() {
        for action in APIRegistry.shared.allActions() {
            #expect(!action.httpMethod.isEmpty, "\(action.path) has empty httpMethod")
        }
    }

    @Test("所有 action 的 summary 字段不为空")
    func testAllActionsHaveSummary() {
        for action in APIRegistry.shared.allActions() {
            #expect(!action.summary.isEmpty, "\(action.path) has empty summary")
        }
    }
}

// MARK: - Example Validation Tests

@Suite("Example Validation Tests")
@MainActor
struct ExampleValidationTests {

    init() async throws {
        AppProbeServer.shared.start()
        guard AppProbeServer.shared.isRunning else {
            throw TestError.serverNotRunning
        }
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    @Test("示例 URL 中的参数名必须出现在 parameters 定义中")
    func testExampleURLParametersMatchActions() {
        for action in APIRegistry.shared.allActions() {
            guard let url = URLComponents(string: action.example.requestURL) else {
                continue
            }
            let exampleParamNames = Set(url.queryItems?.map(\.name) ?? [])
            let definedParamNames = Set(action.parameters.map(\.name))

            let undefined = exampleParamNames.subtracting(definedParamNames)
            #expect(
                undefined.isEmpty,
                "\(action.path): example uses undefined params: \(undefined)"
            )
        }
    }

    @Test("示例 responseBody 必须是合法 JSON（返回二进制的接口除外）")
    func testExampleResponsesAreValidJSON() {
        for action in APIRegistry.shared.allActions() {
            // 返回 raw binary 的接口，example 是描述性文本而非 JSON
            if action.example.responseBody.hasPrefix("<") {
                continue
            }
            guard let data = action.example.responseBody.data(using: .utf8) else {
                Issue.record("\(action.path): example responseBody is not valid UTF-8")
                continue
            }
            do {
                _ = try JSONSerialization.jsonObject(with: data)
            } catch {
                Issue.record("\(action.path): example responseBody is not valid JSON — \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Catalog Integration Tests

@Suite("Catalog Integration Tests")
@MainActor
struct CatalogIntegrationTests {

    let port: UInt

    init() async throws {
        AppProbeServer.shared.start()
        guard AppProbeServer.shared.isRunning else {
            throw TestError.serverNotRunning
        }
        self.port = AppProbeServer.shared.port
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    @Test("GET /catalog?module=all 返回所有已注册 API")
    func testCatalogList() async throws {
        let result = try await TestHTTPClient.get("/catalog?module=all", port: port)

        #expect(result.statusCode == 200)

        let json = try result.json()
        let apiCount = json["apiCount"] as? Int
        #expect(apiCount != nil)
        #expect((apiCount ?? 0) >= 18)

        let apis = json["apis"] as? [[String: Any]]
        #expect(apis != nil)
        #expect((apis?.count ?? 0) >= 18)

        if let firstApi = apis?.first {
            #expect(firstApi["path"] as? String != nil)
            #expect(firstApi["method"] as? String != nil)
            #expect(firstApi["summary"] as? String != nil)
            #expect(firstApi["module"] as? String != nil)
        }
    }

    @Test("GET /catalog/detail 返回指定 API 详情")
    func testCatalogDetail() async throws {
        let result = try await TestHTTPClient.get(
            "/catalog/detail?path=/status",
            port: port
        )

        #expect(result.statusCode == 200)

        let json = try result.json()
        #expect(json["path"] as? String == "/status")
        #expect(json["method"] as? String == "GET")
        #expect(json["summary"] as? String != nil)
        #expect(json["module"] as? String == "status")

        let parameters = json["parameters"] as? [[String: Any]]
        #expect(parameters != nil)

        let example = json["example"] as? [String: Any]
        #expect(example != nil)
        #expect(example?["requestURL"] as? String != nil)
        #expect(example?["responseBody"] as? String != nil)
    }

    @Test("GET /catalog/detail 查询不存在的 API 返回 404")
    func testCatalogDetailNotFound() async throws {
        let result = try await TestHTTPClient.get(
            "/catalog/detail?path=/nonexistent",
            port: port
        )

        #expect(result.statusCode == 404)
    }

    @Test("GET /catalog/detail 缺少 path 参数返回 400")
    func testCatalogDetailMissingPath() async throws {
        let result = try await TestHTTPClient.get(
            "/catalog/detail",
            port: port
        )

        #expect(result.statusCode == 400)
    }

    @Test("GET /nonexistent/action 未注册的动作返回 404")
    func testActionDispatchNotFound() async throws {
        let result = try await TestHTTPClient.get(
            "/nonexistent/action",
            port: port
        )

        #expect(result.statusCode == 404)
    }
}

// MARK: - Module Registry Tests

@Suite("Module Registry Tests")
struct ModuleRegistryTests {

    // 注意：不调用 reset()！Swift Testing 并行执行测试，
    // reset() 会清除其他正在运行的测试的数据。
    // 使用唯一前缀 _test_mod_ 隔离测试数据。

    @Test("registerModule 注册后 allModules 可查到")
    func testRegisterModule() {
        APIRegistry.shared.registerModule(name: "_test_mod_reg", description: "Test module description")

        let modules = APIRegistry.shared.allModules()
        let found = modules.first { $0.name == "_test_mod_reg" }
        #expect(found != nil)
        #expect(found?.description == "Test module description")
    }

    @Test("allModules 返回按名称排序的列表")
    func testAllModulesSorted() {
        APIRegistry.shared.registerModule(name: "_test_mod_zzz", description: "Z module")
        APIRegistry.shared.registerModule(name: "_test_mod_aaa", description: "A module")

        let modules = APIRegistry.shared.allModules()
        // 验证整体有序（只需 >= 2 个元素时才检查）
        guard modules.count >= 2 else { return }
        for i in 1..<modules.count {
            #expect(modules[i - 1].name <= modules[i].name, "allModules() 未按名称排序")
        }
        // 确认我们注册的两个都在
        #expect(modules.contains { $0.name == "_test_mod_aaa" })
        #expect(modules.contains { $0.name == "_test_mod_zzz" })
    }

    @Test("重复注册同名 module 更新描述")
    func testRegisterModuleOverwrite() {
        APIRegistry.shared.registerModule(name: "_test_mod_dup", description: "Original")
        APIRegistry.shared.registerModule(name: "_test_mod_dup", description: "Updated")

        let modules = APIRegistry.shared.allModules()
        let found = modules.first { $0.name == "_test_mod_dup" }
        #expect(found?.description == "Updated")
    }

    @Test("actions(forModule:) 过滤正确")
    func testActionsForModule() {
        // 使用唯一 module 名避免并行测试冲突
        let actionA1 = MockAction(module: "_test_filter_a", name: "filter_a_1")
        let actionA2 = MockAction(module: "_test_filter_a", name: "filter_a_2")
        let actionB1 = MockAction(module: "_test_filter_b", name: "filter_b_1")
        APIRegistry.shared.register(actionA1)
        APIRegistry.shared.register(actionA2)
        APIRegistry.shared.register(actionB1)

        let modA = APIRegistry.shared.actions(forModule: "_test_filter_a")
        #expect(modA.count == 2)
        #expect(modA.allSatisfy { $0.module == "_test_filter_a" })

        let modB = APIRegistry.shared.actions(forModule: "_test_filter_b")
        #expect(modB.count == 1)
        #expect(modB.first?.module == "_test_filter_b")

        let modNone = APIRegistry.shared.actions(forModule: "_test_nonexistent_xyz")
        #expect(modNone.isEmpty)

        // 清理
        APIRegistry.shared.unregister(module: "_test_filter_a", name: "filter_a_1")
        APIRegistry.shared.unregister(module: "_test_filter_a", name: "filter_a_2")
        APIRegistry.shared.unregister(module: "_test_filter_b", name: "filter_b_1")
    }

    @Test("actions(forModule:) 返回按路径排序的列表")
    func testActionsForModuleSorted() {
        let actionZ = MockAction(module: "_test_sort_mod", name: "sort_z")
        let actionA = MockAction(module: "_test_sort_mod", name: "sort_a")
        APIRegistry.shared.register(actionZ)
        APIRegistry.shared.register(actionA)

        let results = APIRegistry.shared.actions(forModule: "_test_sort_mod")
        #expect(results.count == 2)
        guard results.count >= 2 else { return }
        #expect(results[0].path < results[1].path)

        // 清理
        APIRegistry.shared.unregister(module: "_test_sort_mod", name: "sort_z")
        APIRegistry.shared.unregister(module: "_test_sort_mod", name: "sort_a")
    }

    @Test("AppProbeServer.registerModule 代理到 APIRegistry")
    @MainActor
    func testServerRegisterModule() async throws {
        AppProbeServer.shared.start()
        guard AppProbeServer.shared.isRunning else {
            throw TestError.serverNotRunning
        }
        try await Task.sleep(nanoseconds: 100_000_000)

        AppProbeServer.shared.registerModule(name: "_test_mod_server", description: "Registered via server")

        let modules = APIRegistry.shared.allModules()
        let found = modules.first { $0.name == "_test_mod_server" }
        #expect(found != nil)
        #expect(found?.description == "Registered via server")
    }
}

// MARK: - Module Catalog Integration Tests

@Suite("Module Catalog Integration Tests")
@MainActor
struct ModuleCatalogIntegrationTests {

    let port: UInt

    init() async throws {
        AppProbeServer.shared.start()
        guard AppProbeServer.shared.isRunning else {
            throw TestError.serverNotRunning
        }
        self.port = AppProbeServer.shared.port
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    @Test("GET /catalog 无参数返回 module 概览")
    func testCatalogOverview() async throws {
        let result = try await TestHTTPClient.get("/catalog", port: port)

        #expect(result.statusCode == 200)

        let json = try result.json()
        let moduleCount = json["moduleCount"] as? Int
        #expect(moduleCount != nil)
        #expect((moduleCount ?? 0) >= 4)

        // 顶层 hint 存在
        let hint = json["hint"] as? [String: Any]
        #expect(hint != nil)
        #expect(hint?["listApis"] as? String != nil)
        #expect(hint?["getDetail"] as? String != nil)

        let modules = json["modules"] as? [[String: Any]]
        #expect(modules != nil)

        // system module 包含完整 apis 数组
        if let systemMod = modules?.first(where: { ($0["name"] as? String) == "system" }) {
            #expect(systemMod["description"] as? String != nil)
            #expect(systemMod["apiCount"] as? Int != nil)
            let apis = systemMod["apis"] as? [[String: Any]]
            #expect(apis != nil)
            #expect((apis?.count ?? 0) >= 3)
            // 第一个应该是 catalog（最重要）
            if let firstApi = apis?.first {
                #expect(firstApi["path"] as? String == "/catalog")
                #expect(firstApi["parameters"] as? [[String: Any]] != nil)
            }
        }

        // 非 system module 有 listApis 字段，无 apis 字段，无 getDetail（已在顶层 hint 中）
        if let viewMod = modules?.first(where: { ($0["name"] as? String) == "view" }) {
            #expect(viewMod["listApis"] as? String == "GET /catalog?module=view")
            #expect(viewMod["getDetail"] == nil || (viewMod["getDetail"] as? String) == nil)
            #expect(viewMod["apis"] == nil || (viewMod["apis"] as? [[String: Any]]) == nil)
        }
    }

    @Test("GET /catalog?module=sandbox 返回该 module 的 API 列表")
    func testCatalogFilterByModule() async throws {
        let result = try await TestHTTPClient.get("/catalog?module=sandbox", port: port)

        #expect(result.statusCode == 200)

        let json = try result.json()
        // 带参数的响应也包含 hint
        let hint = json["hint"] as? [String: Any]
        #expect(hint != nil)
        #expect(hint?["getDetail"] as? String != nil)

        let apiCount = json["apiCount"] as? Int
        #expect(apiCount != nil)
        #expect((apiCount ?? 0) >= 6)

        let apis = json["apis"] as? [[String: Any]]
        #expect(apis != nil)
        // 所有 API 都属于 sandbox module
        if let apis = apis {
            for api in apis {
                #expect(api["module"] as? String == "sandbox")
            }
        }
    }

    @Test("GET /catalog?module=all 返回所有 API")
    func testCatalogAll() async throws {
        let result = try await TestHTTPClient.get("/catalog?module=all", port: port)

        #expect(result.statusCode == 200)

        let json = try result.json()
        let apiCount = json["apiCount"] as? Int
        #expect(apiCount != nil)
        #expect((apiCount ?? 0) >= 18)

        let apis = json["apis"] as? [[String: Any]]
        #expect(apis != nil)
    }

    @Test("GET /catalog?module=不存在的 返回 404")
    func testCatalogNotFoundModule() async throws {
        let result = try await TestHTTPClient.get(
            "/catalog?module=nonexistent_xyz",
            port: port
        )

        #expect(result.statusCode == 404)
    }

    @Test("GET / 根路径无参数返回 module 概览")
    func testRootPathOverview() async throws {
        let result = try await TestHTTPClient.get("/", port: port)

        #expect(result.statusCode == 200)

        let json = try result.json()
        // 根路径等同于 /catalog，应返回 module 概览
        let moduleCount = json["moduleCount"] as? Int
        #expect(moduleCount != nil)
        #expect((moduleCount ?? 0) >= 5)
    }

    @Test("GET /?module=view 根路径支持 module 过滤")
    func testRootPathFilterByModule() async throws {
        let result = try await TestHTTPClient.get("/?module=view", port: port)

        #expect(result.statusCode == 200)

        let json = try result.json()
        let apis = json["apis"] as? [[String: Any]]
        #expect(apis != nil)
        // 所有返回的 API 都属于 view module
        if let apis = apis {
            for api in apis {
                #expect(api["module"] as? String == "view")
            }
        }
    }

    @Test("sandbox module 概览中无 apis 字段，有 listApis 指引")
    func testNonSystemModuleHasListHint() async throws {
        let result = try await TestHTTPClient.get("/catalog", port: port)

        #expect(result.statusCode == 200)

        let json = try result.json()
        let modules = json["modules"] as? [[String: Any]]
        #expect(modules != nil)

        if let sandboxMod = modules?.first(where: { ($0["name"] as? String) == "sandbox" }) {
            let apiCount = sandboxMod["apiCount"] as? Int
            #expect((apiCount ?? 0) == 6)
            // 无 apis 数组
            #expect(sandboxMod["apis"] == nil || (sandboxMod["apis"] as? [[String: Any]]) == nil)
            // 有 listApis 指引
            #expect(sandboxMod["listApis"] as? String == "GET /catalog?module=sandbox")
        }
    }

    @Test("动态注册 module 后立即出现在概览中")
    func testDynamicModuleRegistration() async throws {
        // 注册一个新的自定义 module
        AppProbeServer.shared.registerModule(
            name: "_test_dynamic",
            description: "动态注册的测试分类"
        )

        let result = try await TestHTTPClient.get("/catalog", port: port)

        #expect(result.statusCode == 200)

        let json = try result.json()
        let modules = json["modules"] as? [[String: Any]]
        let found = modules?.first { ($0["name"] as? String) == "_test_dynamic" }
        #expect(found != nil)
        #expect(found?["description"] as? String == "动态注册的测试分类")
        #expect(found?["apiCount"] as? Int == 0)
        #expect(found?["listApis"] as? String == "GET /catalog?module=_test_dynamic")
    }

    @Test("已注册但无 API 的 module 过滤返回空列表而非 404")
    func testEmptyModuleReturnsEmptyList() async throws {
        // 注册一个无任何 API 的 module
        AppProbeServer.shared.registerModule(
            name: "_test_empty_mod",
            description: "空分类"
        )

        let result = try await TestHTTPClient.get(
            "/catalog?module=_test_empty_mod",
            port: port
        )

        #expect(result.statusCode == 200)

        let json = try result.json()
        let apiCount = json["apiCount"] as? Int
        #expect(apiCount == 0)
        let apis = json["apis"] as? [[String: Any]]
        #expect(apis != nil)
        #expect(apis?.isEmpty == true)
    }

    @Test("module 概览中每个 module 的 description 不为空")
    func testAllModulesHaveDescription() async throws {
        let result = try await TestHTTPClient.get("/catalog", port: port)

        #expect(result.statusCode == 200)

        let json = try result.json()
        let modules = json["modules"] as? [[String: Any]]
        #expect(modules != nil)

        if let modules = modules {
            for mod in modules {
                let name = mod["name"] as? String ?? "unknown"
                let desc = mod["description"] as? String
                #expect(desc != nil && !(desc?.isEmpty ?? true),
                    "module '\(name)' 缺少 description")
            }
        }
    }
}
