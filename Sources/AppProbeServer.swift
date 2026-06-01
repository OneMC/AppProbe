// AppProbeServer.swift
// AppProbe
//
// HTTP 调试服务器。统一 dispatch 所有请求到 AIAction。

import UIKit
import GCDWebServer
import Network
import os

private let logger = Logger(subsystem: "com.appprobe", category: "server")

// MARK: - Errors

public enum AppProbeServerError: Error {
    /// 服务器已在运行，无法重复启动
    case alreadyRunning(currentPort: UInt)

    /// 起始端口及后续端口全部被占用
    case allPortsOccupied(startPort: UInt, attemptedCount: UInt)

    /// 传入的端口号超出有效范围（1~65535）
    case invalidPort(port: UInt)
}

// MARK: - AppProbeServer

public final class AppProbeServer {

    // MARK: - Singleton

    public static let shared = AppProbeServer()

    // MARK: - Properties

    private var webServer: GCDWebServer?
    private var browser: NWBrowser?

    public static let defaultPort: UInt = 47180
    private static let maxPortRetries: UInt = 10

    public private(set) var port: UInt = AppProbeServer.defaultPort

    public var isRunning: Bool {
        return webServer?.isRunning ?? false
    }

    public var serverURL: String {
        let host = Self.wifiIPAddress ?? "localhost"
        return "http://\(host):\(self.port)"
    }

    // MARK: - Initialization

    private init() {}

    // MARK: - Public API

    /// 启动 HTTP 调试服务器（使用默认端口 47180）
    public func start() {
        do {
            _ = try start(port: Self.defaultPort)
        } catch AppProbeServerError.alreadyRunning {
            logger.info("[start] 服务器已在运行: \(self.serverURL)")
        } catch {
            logger.error("[start] 启动失败: \(error.localizedDescription)")
        }
    }

    /// 从指定端口启动 HTTP 调试服务器。
    /// 若指定端口被占用，自动尝试后续端口（最多 10 次）。
    ///
    /// - Parameter port: 期望的起始端口号，必须在 1~65535 范围内
    /// - Returns: 实际成功绑定的端口号
    /// - Throws: `AppProbeServerError` 当启动失败时抛出
    @discardableResult
    public func start(port: UInt) throws -> UInt {
        guard (1...65535).contains(port) else {
            logger.error("[start(port:)] 非法端口号: \(port)")
            throw AppProbeServerError.invalidPort(port: port)
        }

        guard webServer == nil || !webServer!.isRunning else {
            throw AppProbeServerError.alreadyRunning(currentPort: self.port)
        }

        logger.info("[start(port:)] 正在启动服务器，起始端口: \(port)...")
        triggerLocalNetworkPermission()

        let server = prepareServer()

        var currentPort = port
        let maxPort = port + Self.maxPortRetries

        while currentPort < maxPort {
            guard isPortAvailable(currentPort) else {
                logger.info("[start(port:)] 端口 \(currentPort) 已被占用，尝试下一个")
                currentPort += 1
                continue
            }

            let options: [String: Any] = [
                GCDWebServerOption_Port: currentPort,
                GCDWebServerOption_BindToLocalhost: false,
                GCDWebServerOption_BonjourName: "AppProbe",
                GCDWebServerOption_BonjourType: "_http._tcp"
            ]

            do {
                try server.start(options: options)
                self.port = currentPort
                self.webServer = server
                logger.info("[start(port:)] 服务器已启动: \(self.serverURL)")
                return currentPort
            } catch {
                logger.warning("[start(port:)] 端口 \(currentPort) 启动失败, 尝试下一个")
                currentPort += 1
            }
        }

        logger.error("[start(port:)] 端口 \(port) 到 \(maxPort - 1) 全被占用，启动失败")
        throw AppProbeServerError.allPortsOccupied(startPort: port, attemptedCount: Self.maxPortRetries)
    }

    /// 停止服务器
    public func stop() {
        guard let server = webServer, server.isRunning else { return }
        server.stop()
        self.webServer = nil
        logger.info("[stop] 服务器已停止")
    }

    /// 注册 module 描述
    public func registerModule(name: String, description: String) {
        APIRegistry.shared.registerModule(name: name, description: description)
    }

    /// 注册 action（内置和业务统一入口）
    public func register(_ action: AIAction) {
        APIRegistry.shared.register(action)
    }

    /// 注销 action
    public func unregister(module: String, name: String) {
        APIRegistry.shared.unregister(module: module, name: name)
    }

    // MARK: - Server Preparation

    private func prepareServer() -> GCDWebServer {
        let server = GCDWebServer()
        registerBuiltInModules()
        registerBuiltInActions()
        setupDispatch(on: server)
        return server
    }

    // MARK: - Dispatch

    private func setupDispatch(on server: GCDWebServer) {
        // 根路径 / 特殊处理（alias to catalog）
        server.addHandler(forMethod: "GET", path: "/", request: GCDWebServerRequest.self) { request in
            return self.dispatch(request)
        }

        // GET default handler
        server.addDefaultHandler(forMethod: "GET", request: GCDWebServerRequest.self) { request in
            return self.dispatch(request)
        }

        // POST default handler
        server.addDefaultHandler(forMethod: "POST", request: GCDWebServerRequest.self) { request in
            return self.dispatch(request)
        }
    }

    private func dispatch(_ request: GCDWebServerRequest) -> GCDWebServerResponse? {
        let path: String
        if request.path == "/" {
            // 根路径 → 映射到 /catalog
            path = "/catalog"
        } else {
            path = request.path
        }

        guard let action = APIRegistry.shared.action(forPath: path) else {
            logger.warning("[dispatch] 未匹配: \(request.method) \(request.path)")
            return ResponseHelper.errorResponse(404, "Not found: \(request.path)")
        }

        // 校验 HTTP method
        if action.httpMethod.uppercased() != request.method.uppercased() {
            logger.warning("[dispatch] 方法不匹配: \(request.method) \(request.path), 期望 \(action.httpMethod)")
            return ResponseHelper.errorResponse(405, "Method not allowed. Use \(action.httpMethod) for \(request.path)")
        }

        let params = request.query ?? [:]
        let result = action.execute(params: params)
        return ResponseHelper.convert(result)
    }

    // MARK: - Built-in Registration

    private func registerBuiltInModules() {
        let modules: [(String, String)] = [
            ("catalog", "API 目录查询"),
            ("status", "服务器状态监控"),
            ("view", "视图检查与调试，支持视图查找、属性检查、高亮标记和截图"),
            ("vc", "ViewController 层级检查，支持完整层级树和当前可见 VC 查询"),
            ("sandbox", "沙盒文件管理，支持浏览目录、读写文件、SQLite 查询和文件删除"),
            ("userDefaults", "UserDefaults 读写管理，支持列举、获取、设置和删除键值对"),
            ("log", "应用日志查询，支持按级别/子系统/分类/关键词过滤（iOS 15+）"),
        ]
        for (name, desc) in modules {
            APIRegistry.shared.registerModule(name: name, description: desc)
        }
    }

    private func registerBuiltInActions() {
        let actions: [AIAction] = [
            CatalogAction(), CatalogDetailAction(), StatusAction(),
            ViewHierarchyAction(), ViewHighlightAction(), ViewScreenshotAction(),
            VCHierarchyAction(), VCCurrentAction(),
            SandboxListAction(), SandboxFileAction(), SandboxDownloadAction(),
            SandboxSQLAction(), SandboxWriteAction(), SandboxDeleteAction(),
            UDGetAction(), UDSetAction(), UDDeleteAction(),
            LogRecentAction(),
        ]
        for action in actions {
            APIRegistry.shared.register(action)
        }
    }

    // MARK: - Networking Helpers

    private func isPortAvailable(_ port: UInt) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = INADDR_ANY.bigEndian

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return bindResult == 0
    }

    private func triggerLocalNetworkPermission() {
        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: "_http._tcp", domain: nil), using: params)
        browser.stateUpdateHandler = { state in
            switch state {
            case .ready:
                logger.info("[permission] 本地网络权限已授予")
            case .failed(let error):
                logger.error("[permission] NWBrowser 失败: \(error.localizedDescription)")
            default:
                break
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    private static var wifiIPAddress: String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            guard addrFamily == UInt8(AF_INET),
                  let name = interface.ifa_name,
                  String(cString: name) == "en0" else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname, socklen_t(hostname.count),
                        nil, socklen_t(0), NI_NUMERICHOST)
            address = String(cString: hostname)
        }
        return address
    }
}
