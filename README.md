# AppProbe

iOS 运行时调试工具，通过内嵌 HTTP 服务器暴露调试功能：**视图检查**、**ViewController 层级**、**沙盒文件管理**、**UserDefaults 管理**、**日志查询** 和 **API 目录发现** 。

在 Debug 模式下启动后，可通过 HTTP 请求远程查看 App 的 UIView 层级结构、截图，浏览和读写沙盒文件，查询 UserDefaults，以及通过 module 目录发现所有可用 API。

## 快速开始

### 集成（CocoaPods）

```ruby
pod 'AppProbe', :path => 'CommonModules/AppProbe'
```

### 启动服务器

```swift
import AppProbe

// 在 AppDelegate 或合适的位置启动
AppProbeServer.shared.start()
```

### 自定义端口启动

如需指定启动端口（例如避免与其他调试工具冲突）：

```swift
import AppProbe

// 从指定端口启动。若该端口被占用，自动尝试后续端口（最多 10 次）
do {
    let actualPort = try AppProbeServer.shared.start(port: 5000)
    print("服务器运行在端口 \(actualPort)")
} catch AppProbeServerError.invalidPort(let port) {
    print("端口号非法: \(port)")
} catch AppProbeServerError.allPortsOccupied(let start, let count) {
    print("端口 \(start) 到 \(start + count - 1) 全被占用")
} catch AppProbeServerError.alreadyRunning(let currentPort) {
    print("服务器已在端口 \(currentPort) 运行")
} catch {
    print("启动失败: \(error)")
}
```

| 错误 | 触发条件 |
|------|---------|
| `invalidPort` | 端口不在 1~65535 范围内 |
| `allPortsOccupied` | 起始端口及后续 10 个端口全部被占用 |
| `alreadyRunning` | 服务器已在运行 |

服务器默认监听端口 **47180**。如果该端口被占用，会自动尝试 47181、47182...（最多重试 10 次）。

- 无参数启动：`AppProbeServer.shared.start()` — 从默认端口启动，失败仅记录日志
- 自定义端口启动：`try AppProbeServer.shared.start(port: 5000)` — 返回实际绑定的端口号，失败抛出明确错误

启动后可通过 `AppProbeServer.shared.port` 获取实际端口号。

- 模拟器：`http://localhost:<port>`
- 真机（IP）：`http://<设备IP>:<port>`
- 真机（Bonjour 域名）：`http://<设备名>.local:<port>`（推荐，无需记忆 IP）

> **关于 `.local` 域名**：iOS 设备通过 mDNS（Bonjour）协议自动在局域网广播主机名。
> 域名格式为 `<设备名>.local`，设备名来自 **设置 → 通用 → 关于本机 → 名称**（系统会自动将空格和特殊字符做 sanitize）。
>
> 例如设备名为 "naechoutekiのiPhone"，则可通过 `http://naechoutekiiPhone.local:47180/` 访问。
>
> 前提：Mac/PC 与 iPhone 在同一局域网内。AppProbe 启动时已通过 Bonjour 注册服务，无需额外配置。

### Info.plist 配置

真机调试需要本地网络权限。项目内置了自动注入脚本 `scripts/inject_local_network_plist.sh` ，在 Xcode Build Phases 中添加 Run Script 即可自动处理：

```
"${PODS_ROOT}/../CommonModules/AppProbe/AppProbe/scripts/inject_local_network_plist.sh"
```

会自动注入 `NSLocalNetworkUsageDescription` 和 `NSBonjourServices` 配置（仅 Debug 生效）。

---

## 架构设计

### 统一 AIAction 协议

所有 API（内置和业务扩展）通过统一的 `AIAction` 协议注册，无第二种注册机制：

```swift
public protocol AIAction: AnyObject {
    var module: String { get }       // 模块名（路径第一段）
    var name: String { get }         // 动作标识（可为空或多层 path）
    var httpMethod: String { get }   // GET 或 POST
    var summary: String { get }      // 一句话描述
    var parameters: [APIParameterDescriptor] { get }
    var example: APIExample { get }
    func execute(params: [String: String]) -> ActionResponse
}
```

### 路径规则

路径自动从 `module` + `name` 推导：
- `name` 为空 → `/{module}`（如 module="status" → `/status`）
- `name` 非空 → `/{module}/{name}`（如 module="view", name="hierarchy" → `/view/hierarchy`）
- `name` 可包含多层路径（如 `name="catalog/detail"` → `/catalog/detail`）

### 注册方式

```swift
// 注册 module 描述（用于 catalog 概览展示）
AppProbeServer.shared.registerModule(name: "payment", description: "支付模块调试接口")

// 注册自定义 action
AppProbeServer.shared.register(MyCustomAction())

// 注销 action
AppProbeServer.shared.unregister(module: "payment", name: "refund")
```

---

## 自动化测试

AppProbe 内置了完整的 HTTP 集成测试，覆盖所有 API 端点。改完代码后可直接运行测试验证功能正确性，无需部署到真机。

### 前置条件

- Xcode 16+（需要 Swift Testing 支持）
- iOS 模拟器（任意可用机型）

### Podfile 配置

确保 Podfile 中 AppProbe 包含 testspecs：

```ruby
pod 'AppProbe', :path => './CommonModules/AppProbe', :configurations => ['Debug'], :testspecs => ['Tests']
```

配置完成后执行一次 `pod install` 生成测试 Target。

### 运行测试

**方式一：Xcode GUI**

1. 打开 `TestDEMO.xcworkspace`
2. 选择 Scheme：`AppProbe-Unit-Tests`
3. 选择模拟器目标（如 iPhone 16）
4. `Cmd + U` 运行全部测试

**方式二：命令行**

```bash
xcodebuild build-for-testing \
  -workspace TestDEMO.xcworkspace \
  -scheme "AppProbe-Unit-Tests" \
  -destination "platform=iOS Simulator,name=iPhone 16,OS=18.3.1"

xcodebuild test-without-building \
  -workspace TestDEMO.xcworkspace \
  -scheme "AppProbe-Unit-Tests" \
  -destination "platform=iOS Simulator,name=iPhone 16,OS=18.3.1"
```

### 测试覆盖

共 95 个测试用例，分为多个测试套件：

| 套件 | 覆盖内容 |
|------|----------|
| APIRegistry Tests | `register`/`unregister`、`allActions`、`allModules`、catalog API（module 过滤/概览/详情）、根路径映射 |
| AppProbe API Tests | `/view/hierarchy`（tag/class/address）、`/view/highlight`、`/view/screenshot`、404 验证 |
| Sandbox API Tests | `/sandbox/list`、`file`、`download`、`write`、`sql`、`delete` + 安全校验 |
| Log API Regression | `/log/recent` 参数过滤、结构验证 |
| System Log Filtering | 默认过滤系统日志、systemLogs 参数、NSLog 保留 |
| Log Capture Methods | Logger/os_log/NSLog 可捕获，print/debugPrint/fputs 不可捕获 |

### 测试原理

测试在模拟器中启动真实的 AppProbeServer，构造测试用 UIView 层级和沙盒文件，通过 URLSession 向 `localhost` 发送 HTTP 请求，验证每个 API 端点的响应状态码和 JSON 结构。

### 测试文件位置

```
CommonModules/AppProbe/Tests/
├── TestHelpers.swift                # HTTP Client、测试视图构建、临时文件管理
├── APIRegistryTests.swift           # APIRegistry 单元测试 + catalog 集成测试
├── AppProbeAPITests.swift       # 视图检查 API 测试
├── SandboxAPITests.swift            # 沙盒文件管理 API 测试
└── LogAPITests.swift                # 日志查询 API 测试
```

---

## 内置 API 一览

| 路径 | 方法 | 说明 |
|------|------|------|
| `/catalog` | GET | API 目录查询（module 概览/过滤/全量） |
| `/catalog/detail` | GET | 指定 API 完整详情 |
| `/status` | GET | 服务器和 App 状态 |
| `/view/hierarchy` | GET | 视图查找与层级检查 |
| `/view/highlight` | GET | 视图高亮并截图 |
| `/view/screenshot` | GET | 视图截图 |
| `/vc/hierarchy` | GET | ViewController 完整层级树 |
| `/vc/current` | GET | 当前最顶层可见 VC |
| `/sandbox/list` | GET | 浏览沙盒目录 |
| `/sandbox/file` | GET | 读取沙盒文件内容 |
| `/sandbox/download` | GET | 下载沙盒文件（二进制流） |
| `/sandbox/sql` | GET | SQLite 只读查询 |
| `/sandbox/write` | POST | 写入沙盒文件 |
| `/sandbox/delete` | POST | 删除沙盒文件/目录 |
| `/userDefaults` | GET | 获取或列举 UserDefaults |
| `/userDefaults/set` | POST | 设置 UserDefaults 值 |
| `/userDefaults/delete` | POST | 删除 UserDefaults 键 |
| `/log/recent` | GET | 查询最近日志 |

根路径 `GET /` 是 `/catalog` 的别名。

---

## 系统管理 API

### GET /catalog

获取 API 目录。支持三种模式：无参数返回 module 概览；`?module=xxx` 返回该模块下的 API 列表；`?module=all` 返回全部 API。

根路径 `GET /` 是此接口的别名，行为完全一致。

**查询参数：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `module` | String | 否 | 模块名称，传 `all` 返回全部 API，不传返回 module 概览 |

**请求示例：**

```bash
# 获取 module 概览
curl http://localhost:47180/catalog

# 获取指定 module 的 API 列表
curl "http://localhost:47180/catalog?module=view"

# 获取全部 API 列表
curl "http://localhost:47180/catalog?module=all"
```

**概览响应示例（无参数）：**

```json
{
  "moduleCount": 7,
  "hint": {
    "listApis": "GET /catalog?module={name} — 获取指定 module 下的全部 API 列表",
    "getDetail": "GET /catalog/detail?path={api_path} — 获取指定 API 的完整使用说明（参数定义和请求示例）"
  },
  "modules": [
    {
      "name": "catalog",
      "description": "API 目录查询",
      "apiCount": 2,
      "apis": [
        {
          "path": "/catalog",
          "method": "GET",
          "summary": "获取 API 目录：无参数返回 module 概览；?module=xxx 返回该模块下的 API；?module=all 返回全部",
          "parameters": [{ "name": "module", "type": "String", "required": false, "description": "模块名称" }]
        },
        {
          "path": "/catalog/detail",
          "method": "GET",
          "summary": "获取指定 API 的完整使用说明，包含参数列表和示例。必传参数: path",
          "parameters": [{ "name": "path", "type": "String", "required": true, "description": "要查询的 API 路径" }]
        }
      ]
    },
    {
      "name": "view",
      "description": "视图检查与调试，支持视图查找、属性检查、高亮标记和截图",
      "apiCount": 3,
      "listApis": "GET /catalog?module=view"
    }
  ]
}
```

**过滤响应示例（`?module=view`）：**

```json
{
  "hint": {
    "listApis": "GET /catalog?module={name} — 获取指定 module 下的全部 API 列表",
    "getDetail": "GET /catalog/detail?path={api_path} — 获取指定 API 的完整使用说明"
  },
  "apiCount": 3,
  "apis": [
    { "path": "/view/hierarchy", "method": "GET", "summary": "查找并检查指定视图的属性和层级树", "module": "view" },
    { "path": "/view/highlight", "method": "GET", "summary": "给指定视图添加临时高亮边框并返回截图", "module": "view" },
    { "path": "/view/screenshot", "method": "GET", "summary": "截取指定视图的截图并直接返回图片二进制", "module": "view" }
  ]
}
```

---

### GET /catalog/detail

获取指定 API 的完整使用说明，包含参数列表和示例。

**查询参数：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `path` | String | 是 | 要查询的 API 路径，如 `/view/hierarchy` |

**请求示例：**

```bash
curl "http://localhost:47180/catalog/detail?path=/view/hierarchy"
```

**响应示例：**

```json
{
  "path": "/view/hierarchy",
  "method": "GET",
  "summary": "查找并检查指定视图的属性和层级树；无参数时返回 keyWindow 完整层级",
  "module": "view",
  "parameters": [
    { "name": "tag", "type": "Int", "required": false, "description": "通过 tag 查找视图" },
    { "name": "class", "type": "String", "required": false, "description": "通过类名查找视图" },
    { "name": "address", "type": "String", "required": false, "description": "通过内存地址查找视图" },
    { "name": "includeSubviews", "type": "Bool", "required": false, "description": "是否包含子视图层级树，默认 true" }
  ],
  "example": {
    "requestURL": "/view/hierarchy?tag=100",
    "responseBody": "{...}"
  }
}
```

---

### GET /status

获取服务器和 App 的基本状态信息。

**请求示例：**

```bash
curl http://localhost:47180/status
```

**响应示例：**

```json
{
  "status": "ok",
  "serverVersion": "1.0.0",
  "appName": "TestDEMO",
  "device": "iPhone 16 Pro",
  "windowCount": 1
}
```

---

## 视图检查 API

### GET /view/hierarchy

查找并检查指定的 UIView ，返回视图属性和子视图层级。

无参数时返回 keyWindow 的完整视图层级树。

**查询参数：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `tag` | Int | 三选一 | 通过 view.tag 精确匹配 |
| `class` | String | 三选一 | 通过类名匹配第一个可见视图 |
| `address` | String | 三选一 | 通过内存地址匹配（如 `0x7f8b1c`） |
| `includeSubviews` | Bool | 否 | 是否包含子视图层级树，默认 `true` |

**请求示例：**

```bash
# 通过 tag 查找
curl "http://localhost:47180/view/hierarchy?tag=100"

# 通过类名查找
curl "http://localhost:47180/view/hierarchy?class=UILabel"

# 通过内存地址查找
curl "http://localhost:47180/view/hierarchy?address=0x7f8b1c"

# keyWindow 完整层级
curl "http://localhost:47180/view/hierarchy"
```

**成功响应示例：**

```json
{
  "found": true,
  "target": {
    "address": "0x7f8b1c005a00",
    "className": "UILabel",
    "tag": 100,
    "frame": { "x": 20, "y": 100, "width": 280, "height": 44 },
    "bounds": { "x": 0, "y": 0, "width": 280, "height": 44 },
    "center": { "x": 160, "y": 122 },
    "alpha": 1.0,
    "isHidden": false,
    "isUserInteractionEnabled": true,
    "backgroundColor": "#FFFFFF",
    "tintColor": "#007AFF",
    "layerInfo": {
      "cornerRadius": 8.0,
      "borderWidth": 0.0,
      "borderColor": null,
      "shadowColor": null,
      "shadowOffset": { "width": 0, "height": -3 },
      "shadowRadius": 0.0,
      "shadowOpacity": 0.0
    },
    "constraints": []
  },
  "hierarchy": {
    "depth": 2,
    "subviewCount": 3,
    "tree": {
      "className": "UILabel",
      "address": "0x7f8b1c005a00",
      "tag": 100,
      "frame": { "x": 20, "y": 100, "width": 280, "height": 44 },
      "alpha": 1.0,
      "isHidden": false,
      "subviews": [],
      "labelInfo": {
        "text": "Hello World",
        "font": { "name": ".SFUI-Regular", "size": 17.0 },
        "textColor": "#000000",
        "textAlignment": "natural"
      },
      "imageViewInfo": null,
      "buttonInfo": null
    }
  },
  "searched": {
    "tag": 100,
    "className": null,
    "address": null,
    "windowCount": 1,
    "totalViewsScanned": 42
  }
}
```

**未找到响应示例（HTTP 404）：**

```json
{
  "found": false,
  "target": null,
  "hierarchy": null,
  "error": "View with tag 999 not found",
  "searched": {
    "tag": 999,
    "className": null,
    "address": null,
    "windowCount": 1,
    "totalViewsScanned": 42
  }
}
```

---

### GET /view/highlight

给指定视图添加临时高亮边框并返回截图。响应直接返回图片二进制数据，元数据通过响应头返回。

**查询参数：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `tag` | Int | 二选一 | 通过 tag 查找视图 |
| `address` | String | 二选一 | 通过内存地址查找视图 |
| `borderColor` | String | 否 | 边框颜色，Hex 格式（如 `FF0000`），默认红色 |
| `borderWidth` | Double | 否 | 边框宽度，默认 `2.0` |
| `quality` | Double | 否 | JPEG 压缩质量 (0.0-1.0)，默认 0.75 |
| `scale` | Double | 否 | 渲染缩放比例 (0.1-3.0)，默认 1.0 |
| `format` | String | 否 | 图片格式：`jpeg`（默认）或 `png` |

**请求示例：**

```bash
# 通过 tag 高亮，绿色边框
curl -o highlight.jpg "http://localhost:47180/view/highlight?tag=100&borderColor=00FF00&borderWidth=3.0"

# 通过 address 高亮
curl -o highlight.jpg "http://localhost:47180/view/highlight?address=0x7f8b1c"
```

**响应：** `Content-Type: image/jpeg`（或 `image/png`），附带以下响应头：

| 响应头 | 说明 |
|--------|------|
| `X-Image-Width` | 输出图片宽度 (px) |
| `X-Image-Height` | 输出图片高度 (px) |
| `X-Original-Width` | 视图原始宽度 (pt) |
| `X-Original-Height` | 视图原始高度 (pt) |
| `X-Image-Format` | 图片格式 (jpeg/png) |
| `X-Image-Quality` | JPEG 质量（仅 jpeg） |
| `X-Image-Scale` | 渲染缩放比例 |

---

### GET /view/screenshot

截取指定视图的截图，直接返回图片二进制数据。无参数时截取 keyWindow（整个屏幕）。

**查询参数：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `tag` | Int | 可选 | 通过 view.tag 精确匹配 |
| `class` | String | 可选 | 通过类名匹配第一个可见视图 |
| `address` | String | 可选 | 通过内存地址匹配 |
| `quality` | Double | 否 | JPEG 压缩质量 (0.0-1.0)，默认 0.75 |
| `scale` | Double | 否 | 渲染缩放比例 (0.1-3.0)，默认 1.0 |
| `format` | String | 否 | `jpeg`（默认）或 `png` |

**请求示例：**

```bash
# 截取 keyWindow
curl -o screen.jpg http://localhost:47180/view/screenshot

# 指定视图 + 自定义参数
curl -o view.jpg "http://localhost:47180/view/screenshot?tag=100&quality=0.9&scale=2.0"

# 无损 PNG
curl -o view.png "http://localhost:47180/view/screenshot?tag=100&format=png"
```

**响应：** 与 `/view/highlight` 相同的 `Content-Type` 和 `X-Image-*` 响应头。

---

## ViewController 层级 API

### GET /vc/hierarchy

获取完整 ViewController 层级树，识别 Nav/Tab/容器结构。

**查询参数：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `depth` | Int | 否 | 限制递归深度（默认不限） |
| `class` | String | 否 | 高亮/标记指定类名的 VC |

**请求示例：**

```bash
curl http://localhost:47180/vc/hierarchy
curl "http://localhost:47180/vc/hierarchy?depth=3"
curl "http://localhost:47180/vc/hierarchy?class=HomeViewController"
```

**响应示例：**

```json
{
  "windowCount": 1,
  "scenes": [
    {
      "sceneTitle": "Default",
      "rootViewController": {
        "className": "UITabBarController",
        "address": "0x100800000",
        "title": null,
        "isViewLoaded": true,
        "isVisible": true,
        "selectedIndex": 0,
        "tabs": [],
        "navigationStack": null,
        "presentedViewController": null,
        "children": null,
        "highlighted": null
      }
    }
  ]
}
```

---

### GET /vc/current

获取当前最顶层可见 ViewController 的详细信息，含导航栈和 present 链。

**请求示例：**

```bash
curl http://localhost:47180/vc/current
```

**响应示例：**

```json
{
  "className": "HomeViewController",
  "address": "0x100900000",
  "title": "Home",
  "isViewLoaded": true,
  "isVisible": true,
  "parentNavigation": {
    "className": "UINavigationController",
    "stackDepth": 1,
    "stackClasses": ["HomeViewController"]
  },
  "presentationChain": ["UITabBarController", "UINavigationController", "HomeViewController"],
  "viewAddress": "0x100900100"
}
```

---

## 沙盒文件管理 API

所有沙盒 API 的路径参数均为**相对于沙盒根目录的相对路径**。禁止使用 `..` 路径穿越和绝对路径。

### GET /sandbox/list

浏览沙盒目录内容。

**查询参数：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `path` | String | 否 | 目录相对路径，默认为沙盒根目录 |

**请求示例：**

```bash
# 浏览沙盒根目录
curl http://localhost:47180/sandbox/list

# 浏览 Documents 目录
curl "http://localhost:47180/sandbox/list?path=Documents"
```

**响应示例：**

```json
{
  "currentPath": "Documents",
  "files": [
    {
      "name": "config.json",
      "path": "Documents/config.json",
      "size": 1024,
      "isDirectory": false,
      "modificationDate": "2026-05-20T10:30:00Z",
      "isReadable": true
    },
    {
      "name": "Caches",
      "path": "Documents/Caches",
      "size": 0,
      "isDirectory": true,
      "modificationDate": "2026-05-19T08:00:00Z",
      "isReadable": true
    }
  ]
}
```

---

### GET /sandbox/file

读取沙盒中的文件内容。

**查询参数：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `path` | String | 是 | 文件相对路径 |
| `format` | String | 否 | 读取格式：`auto`（默认）、`text`、`json`、`download` |

**format 参数说明：**

| 值 | 行为 |
|------|------|
| `auto` | 自动判断：文本类小文件直接返回内容；SQLite 返回下载链接；大文件返回下载链接；其他小文件返回 Base64 |
| `text` | 强制以 UTF-8 文本返回（仅限文本类文件） |
| `json` | 强制以 JSON 文本返回（仅限 .json / .plist 文件） |
| `download` | 返回下载链接，不直接返回内容 |

**请求示例：**

```bash
curl "http://localhost:47180/sandbox/file?path=Documents/config.json&format=json"
curl "http://localhost:47180/sandbox/file?path=Documents/log.txt&format=text"
```

**文本文件响应示例：**

```json
{
  "name": "config.json",
  "path": "Documents/config.json",
  "size": 256,
  "contentType": "json",
  "textContent": "{\"key\": \"value\"}",
  "base64Content": null,
  "downloadUrl": null,
  "message": null
}
```

---

### GET /sandbox/download

下载沙盒中的文件（二进制流）。

**查询参数：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `path` | String | 是 | 文件相对路径 |

**请求示例：**

```bash
curl -o app.db "http://localhost:47180/sandbox/download?path=Library/Application%20Support/app.db"
```

响应为 `application/octet-stream` 二进制数据，附带 `Content-Disposition` 头。

---

### GET /sandbox/sql

对沙盒中的 SQLite 数据库执行只读查询。仅允许 `SELECT` 和 `PRAGMA` 语句。

**查询参数：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `path` | String | 是 | 数据库文件的相对路径 |
| `sql` | String | 是 | SQL 查询语句（仅 SELECT / PRAGMA） |

**请求示例：**

```bash
# 查询表结构
curl "http://localhost:47180/sandbox/sql?path=Library/Application%20Support/app.db&sql=PRAGMA%20table_info(users)"

# 查询数据
curl "http://localhost:47180/sandbox/sql?path=Documents/test.db&sql=SELECT%20*%20FROM%20users%20LIMIT%205"
```

**响应示例：**

```json
{
  "columns": ["id", "name", "email"],
  "rows": [
    { "id": "1", "name": "Alice", "email": "alice@example.com" },
    { "id": "2", "name": "Bob", "email": "bob@example.com" }
  ],
  "rowCount": 2
}
```

---

### POST /sandbox/write

写入内容到沙盒文件。支持覆盖和追加模式，父目录不存在时会自动创建。

**查询参数：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `path` | String | 是 | 文件相对路径 |
| `content` | String | 是 | 写入内容 |
| `encoding` | String | 否 | 编码方式：`utf8`（默认）或 `base64` |
| `append` | Bool | 否 | 是否追加模式，默认 `false`（覆盖） |

**请求示例：**

```bash
# 覆盖写入
curl -X POST "http://localhost:47180/sandbox/write?path=Documents/log.txt&content=hello"

# 追加模式
curl -X POST "http://localhost:47180/sandbox/write?path=Documents/log.txt&content=world&append=true"

# Base64 编码写入
curl -X POST "http://localhost:47180/sandbox/write?path=Documents/data.bin&content=SGVsbG8=&encoding=base64"
```

**响应示例：**

```json
{
  "success": true,
  "path": "Documents/log.txt",
  "bytesWritten": 5,
  "message": "File created"
}
```

---

### POST /sandbox/delete

删除沙盒中的文件或目录。**目录将被递归删除，操作不可逆。**

**查询参数：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `path` | String | 是 | 文件或目录的相对路径 |

**请求示例：**

```bash
curl -X POST "http://localhost:47180/sandbox/delete?path=Documents/temp.txt"
```

**响应示例：**

```json
{
  "success": true,
  "path": "Documents/temp.txt",
  "message": "Deleted"
}
```

---

## UserDefaults 管理 API

### GET /userDefaults

获取或列举 UserDefaults 键值对。传 `key` 获取单个值，不传列举所有。

**查询参数：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `key` | String | 否 | 精确获取指定 key 的值；不传时列举所有 key |
| `prefix` | String | 否 | 列举模式下，只返回以此前缀开头的 key |
| `search` | String | 否 | 列举模式下，只返回 key 名包含此子串的条目 |
| `suite` | String | 否 | 自定义 suite 名称，不传时使用 UserDefaults.standard |

**请求示例：**

```bash
# 列举所有
curl http://localhost:47180/userDefaults

# 按前缀过滤
curl "http://localhost:47180/userDefaults?prefix=feature_"

# 获取单个值
curl "http://localhost:47180/userDefaults?key=feature_darkMode"
```

**响应示例（列举）：**

```json
{
  "suite": "standard",
  "count": 2,
  "entries": [
    { "key": "feature_darkMode", "type": "Bool", "value": "true" },
    { "key": "feature_newUI", "type": "Bool", "value": "false" }
  ]
}
```

---

### POST /userDefaults/set

设置 UserDefaults 值。

**查询参数：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `key` | String | 是 | 要设置的 key |
| `value` | String | 是 | 值（字符串表示） |
| `type` | String | 是 | 值类型：`string` / `int` / `double` / `bool` |
| `suite` | String | 否 | 自定义 suite 名称 |

**请求示例：**

```bash
curl -X POST "http://localhost:47180/userDefaults/set?key=feature_darkMode&value=true&type=bool"
```

**响应示例：**

```json
{
  "success": true,
  "key": "feature_darkMode",
  "type": "bool",
  "value": "true",
  "message": "Value set"
}
```

---

### POST /userDefaults/delete

删除 UserDefaults 中的指定 key。

**查询参数：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `key` | String | 是 | 要删除的 key |
| `suite` | String | 否 | 自定义 suite 名称 |

**请求示例：**

```bash
curl -X POST "http://localhost:47180/userDefaults/delete?key=feature_darkMode"
```

**响应示例：**

```json
{
  "success": true,
  "key": "feature_darkMode",
  "message": "Key removed"
}
```

---

## 日志查询 API

### GET /log/recent

查询当前进程的最近日志。使用 OSLogStore（iOS 15+）从统一日志系统读取日志条目。

**默认行为：过滤系统日志**（`com.apple.*` 等系统框架 subsystem），仅返回 App 自身和第三方库日志。通过 `systemLogs=true` 可包含系统日志。

**查询参数：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `count` | Int | 否 | 返回条数，默认 50，最大 200 |
| `level` | String | 否 | 最低日志级别：debug / info / notice / error / fault |
| `subsystem` | String | 否 | 按 subsystem 精确过滤 |
| `category` | String | 否 | 按 category 精确过滤 |
| `since` | String | 否 | 起始时间（Unix timestamp 秒 或 ISO8601） |
| `keyword` | String | 否 | 消息内容关键词搜索（大小写不敏感） |
| `systemLogs` | Bool | 否 | 是否包含系统日志，默认 false |

**请求示例：**

```bash
# 查询最近 10 条 App 日志（过滤系统日志）
curl "http://localhost:47180/log/recent?count=10"

# 查询 error 级别以上的日志
curl "http://localhost:47180/log/recent?level=error"

# 包含系统日志
curl "http://localhost:47180/log/recent?systemLogs=true"

# 按 subsystem 精确查询
curl "http://localhost:47180/log/recent?subsystem=com.myapp.network"
```

**响应示例：**

```json
{
  "hint": {
    "source": "OSLogStore (iOS 15+)",
    "limitation": "仅能获取通过 os_log / Logger API 输出的日志。",
    "unsupportedMethods": ["print() 输出不保证捕获"]
  },
  "totalMatched": 3,
  "returned": 3,
  "oldestDate": "2026-05-21T10:00:00Z",
  "newestDate": "2026-05-21T10:05:30Z",
  "entries": [
    {
      "date": "2026-05-21T10:05:30Z",
      "level": "error",
      "subsystem": "com.myapp",
      "category": "network",
      "message": "Request timeout"
    }
  ]
}
```

### 日志输出方式捕获能力

| 输出方式 | 能否捕获 | 说明 |
|---------|---------|------|
| `Logger` API (os.Logger) | 可捕获 | 直接写入 unified logging，带 subsystem 和 category |
| `os_log()` 函数 | 可捕获 | 传统 C 风格 API，同属 unified logging |
| `NSLog()` | 可捕获 | 底层走 os_log，subsystem 为空字符串 |
| `print()` | 不可捕获 | 走 stdout，不经过 unified logging |
| `debugPrint()` | 不可捕获 | 同 print，走 stdout |
| `fputs(stderr)` / `printf` | 不可捕获 | C 层输出，不经过 unified logging |

### 默认过滤的系统 subsystem

以下 Apple 系统框架的 subsystem 默认被过滤（传 `systemLogs=true` 时返回）：

`com.apple.CoreData` `com.apple.network` `com.apple.CFNetwork` `com.apple.UIKit` `com.apple.Foundation` `com.apple.CoreAnimation` `com.apple.runningboard` `com.apple.RunningBoardServices` `com.apple.Metal` `com.apple.avfaudio` `com.apple.SystemConfiguration` `com.apple.TCC` `com.apple.defaults` `com.apple.BackgroundTaskAgent`

> **注意**：空 subsystem 不被过滤（NSLog 输出的 subsystem 为空，过滤会导致 NSLog 内容丢失）。

---

## 扩展 API：注册自定义 Module

业务模块可通过 `registerModule` + `register` 注册自定义模块和 API，注册后会自动出现在 `/catalog` 概览中。

```swift
import AppProbe

// 1. 注册 module 描述
AppProbeServer.shared.registerModule(name: "payment", description: "支付模块调试接口")

// 2. 实现 AIAction
final class PaymentOrderAction: AIAction {
    let module = "payment"
    let name = "orders"
    let httpMethod = "GET"
    let summary = "查询最近支付订单"
    let parameters = [
        APIParameterDescriptor(name: "count", type: "Int", required: false, description: "返回条数"),
    ]
    let example = APIExample(
        requestURL: "/payment/orders?count=10",
        responseBody: #"{"orders":[]}"#
    )

    func execute(params: [String: String]) -> ActionResponse {
        // 实现业务逻辑
        return .json(["orders": []])
    }
}

// 3. 注册 action
AppProbeServer.shared.register(PaymentOrderAction())
```

---

## 错误码对照表

| 错误码 | HTTP 状态码 | 说明 |
|--------|------------|------|
| `invalid_path` | 403 | 路径无效（包含 `..` 或绝对路径） |
| `not_found` | 404 | 文件或目录不存在 |
| `not_readable` | 403 | 文件不可读 |
| `not_writable` | 403 | 路径不可写 |
| `is_directory` | 400 | 目标是目录而非文件 |
| `not_directory` | 400 | 目标不是目录 |
| `invalid_encoding` | 400 | 无效的编码格式 |
| `unsupported_media_type` | 415 | 文件类型不支持此操作 |
| `file_too_large` | 413 | 文件太大 |
| `read_failed` | 500 | 读取文件失败 |
| `write_failed` | 500 | 写入文件失败 |
| `delete_failed` | 500 | 删除文件失败 |
| `list_failed` | 500 | 列出目录失败 |
| `db_open_failed` | 500 | 数据库打开失败 |
| `sql_error` | 500 | SQL 执行错误 |
| `invalid_sql` | 403 | 非法 SQL（仅允许 SELECT / PRAGMA） |

**错误响应格式：**

```json
{
  "error": "错误描述信息",
  "code": "error_code"
}
```

---

## 安全说明

- **路径安全**：所有沙盒路径必须是相对路径，禁止 `..` 穿越和绝对路径，路径解析后必须仍在沙盒根目录内
- **SQL 安全**：仅允许 `SELECT` 和 `PRAGMA` 查询，数据库以只读模式打开
- **仅限 Debug**：此工具应仅在 Debug 构建中启用，不应包含在生产版本中
- **网络隔离**：服务器通过 Bonjour 在本地网络可发现，确保仅在受信任的网络环境中使用
