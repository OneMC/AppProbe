// AppProbeServerPortTests.swift
// AppProbe Tests
//
// AppProbeServer 自定义端口启动测试

import Foundation
import Testing
@testable import AppProbe

// MARK: - Port Blocker

/// 临时占用指定端口的 socket，用于测试端口被占场景
final class PortBlocker {
    private var sock: Int32 = -1

    /// 占用指定端口。成功返回 true，失败返回 false。
    func occupy(port: UInt) -> Bool {
        sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }

        // 允许地址复用，避免 TIME_WAIT 影响
        var reuse: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = INADDR_ANY.bigEndian

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        // 开始监听，确保端口被完全占用
        if bindResult == 0 {
            listen(sock, 1)
        }

        return bindResult == 0
    }

    deinit {
        if sock >= 0 {
            close(sock)
        }
    }
}

// MARK: - Port Tests

@Suite("AppProbeServer Port Tests")
@MainActor
struct AppProbeServerPortTests {

    // MARK: - Helpers

    /// 确保服务器停止，避免影响其他测试
    private static func ensureStopped() {
        AppProbeServer.shared.stop()
    }

    // MARK: - Tests

    @Test("自定义端口启动成功，返回实际端口")
    func testCustomPortStartSuccess() async throws {
        Self.ensureStopped()

        let targetPort: UInt = 52000
        let actualPort = try AppProbeServer.shared.start(port: targetPort)

        #expect(actualPort == targetPort)
        #expect(AppProbeServer.shared.isRunning == true)
        #expect(AppProbeServer.shared.port == targetPort)
        #expect(AppProbeServer.shared.serverURL.contains(":\(targetPort)"))

        // 验证服务器可响应 HTTP 请求
        let result = try await TestHTTPClient.get("/status", port: actualPort)
        #expect(result.statusCode == 200)

        Self.ensureStopped()
    }

    @Test("自定义端口被占时自动回退到下一个可用端口")
    func testPortFallbackWhenOccupied() async throws {
        Self.ensureStopped()

        let blocker = PortBlocker()
        let targetPort: UInt = 52100
        let occupied = blocker.occupy(port: targetPort)
        #expect(occupied == true, "测试辅助 socket 绑定端口 \(targetPort) 失败")

        let actualPort = try AppProbeServer.shared.start(port: targetPort)

        #expect(actualPort == targetPort + 1, "期望回退到 \(targetPort + 1)，实际 \(actualPort)")
        #expect(AppProbeServer.shared.isRunning == true)

        // 验证回退后的端口可响应
        let result = try await TestHTTPClient.get("/status", port: actualPort)
        #expect(result.statusCode == 200)

        Self.ensureStopped()
    }

    @Test("起始端口及后续 10 个端口全被占时抛出 allPortsOccupied")
    func testAllPortsOccupiedThrows() async throws {
        Self.ensureStopped()

        let targetPort: UInt = 52200
        var blockers: [PortBlocker] = []

        // 占用 targetPort 到 targetPort + 9 共 10 个端口
        for offset in 0..<10 {
            let blocker = PortBlocker()
            let port = targetPort + UInt(offset)
            let occupied = blocker.occupy(port: port)
            #expect(occupied == true, "测试辅助 socket 绑定端口 \(port) 失败")
            blockers.append(blocker)
        }

        // 尝试启动应抛错
        do {
            _ = try AppProbeServer.shared.start(port: targetPort)
            Issue.record("期望抛出 allPortsOccupied 错误，但未抛出")
        } catch AppProbeServerError.allPortsOccupied(let startPort, let attemptedCount) {
            #expect(startPort == targetPort)
            #expect(attemptedCount == 10)
        } catch {
            Issue.record("期望抛出 allPortsOccupied，实际抛出: \(error)")
        }

        #expect(AppProbeServer.shared.isRunning == false)

        // blockers 超出作用域自动释放
    }

    @Test("传入 0 抛出 invalidPort")
    func testInvalidPortZero() async throws {
        Self.ensureStopped()

        do {
            _ = try AppProbeServer.shared.start(port: 0)
            Issue.record("期望抛出 invalidPort 错误，但未抛出")
        } catch AppProbeServerError.invalidPort(let port) {
            #expect(port == 0)
        } catch {
            Issue.record("期望抛出 invalidPort，实际抛出: \(error)")
        }
    }

    @Test("传入大于 65535 的端口抛出 invalidPort")
    func testInvalidPortTooLarge() async throws {
        Self.ensureStopped()

        do {
            _ = try AppProbeServer.shared.start(port: 70000)
            Issue.record("期望抛出 invalidPort 错误，但未抛出")
        } catch AppProbeServerError.invalidPort(let port) {
            #expect(port == 70000)
        } catch {
            Issue.record("期望抛出 invalidPort，实际抛出: \(error)")
        }
    }

    @Test("服务器已在运行时再次启动抛出 alreadyRunning")
    func testAlreadyRunningThrows() async throws {
        Self.ensureStopped()

        let firstPort = try AppProbeServer.shared.start(port: 52300)
        #expect(AppProbeServer.shared.isRunning == true)

        do {
            _ = try AppProbeServer.shared.start(port: 52301)
            Issue.record("期望抛出 alreadyRunning 错误，但未抛出")
        } catch AppProbeServerError.alreadyRunning(let currentPort) {
            #expect(currentPort == firstPort)
        } catch {
            Issue.record("期望抛出 alreadyRunning，实际抛出: \(error)")
        }

        Self.ensureStopped()
    }

    @Test("无参数 start() 仍能正常启动且行为不变")
    func testLegacyStartUnchanged() async throws {
        Self.ensureStopped()

        AppProbeServer.shared.start()

        #expect(AppProbeServer.shared.isRunning == true)
        // 默认端口是 47180，如果没有被占的话
        #expect(AppProbeServer.shared.port >= 47180)

        // 验证可响应
        let result = try await TestHTTPClient.get("/status", port: AppProbeServer.shared.port)
        #expect(result.statusCode == 200)

        Self.ensureStopped()
    }

    @Test("stop() 后 isRunning 为 false 且可重新启动")
    func testStopAndRestart() async throws {
        Self.ensureStopped()

        let firstPort = try AppProbeServer.shared.start(port: 52400)
        #expect(AppProbeServer.shared.isRunning == true)

        AppProbeServer.shared.stop()
        #expect(AppProbeServer.shared.isRunning == false)

        let secondPort = try AppProbeServer.shared.start(port: 52401)
        #expect(AppProbeServer.shared.isRunning == true)
        #expect(secondPort == 52401)

        Self.ensureStopped()
    }
}
