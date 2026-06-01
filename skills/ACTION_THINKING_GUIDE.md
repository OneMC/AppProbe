# Action Thinking Guide

When you determine you need a new action to verify a feature or locate a problem, use this guide to structure your thinking process.

**Core philosophy:** Don't just fill in a template — reason through: what information do I need, where is it, and how do I correctly obtain and communicate it.

---

## Thinking Framework

Every time you decide to add an action, walk through this reasoning chain:

```
1. What is my problem?
   → bug symptom / feature to verify / state to observe

2. What information do I need to locate or verify this?
   → which state values, which data, which timing relationships

3. Can I obtain this information now?
   → can inspect see it? can sandbox read it? can an existing action return it?

4. If not → where does this information live at runtime?
   → a ViewModel property? a Service's state? a queue's length? an in-memory cache?

5. How to correctly obtain and communicate it?
   → read what property? on which thread? return what structure so I can easily understand it?
```

---

## When to Add an Action

**Anticipate proactively; don't wait passively.** While writing code, ask yourself:

> "Can the effect of this change be observed via HTTP?"

If the answer isn't obvious → immediately write an action as part of the feature implementation.

**Possible action use cases** (to inspire thinking, not a fixed checklist):

- Query a business object's current state
- Simulate a tap or interaction
- Trigger a navigation/route change
- Aggregate runtime information scattered across multiple sources (memory + queues + caches)
- Return the execution timeline/sequence of a process
- Read runtime logs or diagnostic information

Key: these are not fixed categories — you can create entirely new use cases based on the actual problem.

---

## Action Code Skeleton

### Understanding `module` and `name`

An action's HTTP path is derived from two fields: `/{module}/{name}`

| Field | Role | Example |
|-------|------|---------|
| `module` | Module identifier. Must be a single word (`[a-zA-Z][a-zA-Z0-9]*`), no slashes. | `"cart"`, `"profile"`, `"homepage"` |
| `name` | Action identifier. Can be empty (path becomes `/{module}`) or multi-level (e.g. `"orders/recent"`). | `"getState"`, `"tapCard"`, `""` |

**Key rule:** The `module` value should match a registered module name for the action to appear in the catalog overview with its description. Built-in modules (catalog, status, view, vc, sandbox, userDefaults, log) are pre-registered by the framework.

### Step 1: Ensure Module Is Registered

Before registering any action, ensure its **`module` value** has a registered description. Check existing modules first — only register a new one if no match exists.

```swift
#if DEBUG
// Register the module description (only needs to be done once per module)
AppProbeServer.shared.registerModule(
    name: "cart",
    description: "Shopping cart state inspection and manipulation"
)
#endif
```

> **Important:** You only need to register a module ONCE across the entire app. If another file already registered `"cart"`, skip this step.

### Step 2: Define and Register the Action

```swift
#if DEBUG
final class CartStateAction: AIAction {
    let module = "cart"              // Module name (first path segment)
    let name = "getState"            // Action identifier (second path segment)
    let httpMethod = "GET"
    let summary = "One-line description of what this action observes/triggers"
    let parameters = [
        APIParameterDescriptor(name: "param_name", type: "String", required: true, description: "Parameter description")
    ]
    let example = APIExample(
        requestURL: "/cart/getState?param_name=example_value",
        responseBody: #"{"key": "example response"}"#
    )

    func execute(params: [String: String]) -> ActionResponse {
        // ⚠️ Critical: read the correct state, from the correct data source, on the correct thread
        // If you need main-thread data, use DispatchQueue.main.sync { ... }
        // If data may be concurrently modified, ensure thread-safe access

        guard let paramName = params["param_name"] else {
            return .error(code: 400, message: "Missing 'param_name' parameter")
        }

        // Return success as JSON
        return .json(["key": "value"])
    }
}
#endif
```

### Step 3: Register at the Right Time

```swift
#if DEBUG
// Global observation actions → register at app launch (AppDelegate / SceneDelegate)
// No need to unregister — they persist for the app's lifetime
AppProbeServer.shared.register(CartStateAction())

// Page-scoped actions → register on page init, unregister on deinit
class SomeViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        AppProbeServer.shared.register(PageSpecificAction())
    }
    deinit {
        AppProbeServer.shared.unregister(module: "cart", name: "getState")
    }
}

// One-off debugging actions → register temporarily, delete code after problem is resolved
#endif
```

### ActionResponse Cases

The `execute` method returns `ActionResponse`. Available cases:

| Case | HTTP Status | When to Use |
|------|-------------|-------------|
| `.json(any Codable)` | 200 | Success — return structured data |
| `.jsonWithStatus(any Codable, statusCode: Int)` | Custom | Non-200 structured response (e.g. 404 with error details) |
| `.raw(data: Data, contentType: String, headers: [String: String])` | 200 | Binary response (images, files) |
| `.error(code: Int, message: String)` | Custom | Simple error response (`{"error": message, "statusCode": code}`) |

### Async Considerations

The `execute` method is **synchronous**. If you need to read async state:

- **Main-thread UI state:** Use `DispatchQueue.main.sync { ... }` inside execute to safely read UI properties.
- **Async operation results:** Read the *last known state* (e.g. a cached value, a property that was set by a completion handler). Don't attempt to trigger and wait for an async operation inside `execute`.
- **If you truly need async observation:** Create an action that *starts* the observation and writes results to a known location (e.g. UserDefaults or a file), then read that location with a second call.

### End-to-End Verification

After writing an action, verify the full loop:

```bash
# 1. Build and run the app
# 2. Verify the action appears in the catalog
curl "http://localhost:47180/catalog?module=cart"

# 3. Call the action directly
curl "http://localhost:47180/cart/getState?param_name=value"

# 4. Verify response matches your expected structure
```

---

## Reasoning Process Example

### Scenario: List page occasionally shows blank, but network request logs show success

**Step 1 — What's the problem?**

List is occasionally blank. Not every time, so it's not a fixed data source issue — likely a timing problem.

**Step 2 — What information do I need?**

- Current `dataSource` array count (is there data in memory?)
- tableView's actual `numberOfRows` (how many rows does the UI think there are?)
- Time of the most recent `reloadData` call (was the UI refreshed after data arrived?)

**Step 3 — Are existing capabilities sufficient?**

- inspect can find the tableView and confirm it exists ✓
- inspect cannot see `dataSource` count (that's a ViewModel property) ✗
- sandbox has no relevant persisted data ✗
- No existing action can return this information ✗

**Step 4 — Where is the information?**

- `dataSource.count` → property of ListViewModel
- `numberOfRows` → could get indirectly via inspect, but not direct enough
- `lastReloadTime` → need to record a timestamp at the reloadData call site

**Step 5 — How to correctly obtain it?**

Add a new action: on the main thread, read ListViewModel's `dataSource.count` and the timestamp of the last `reloadData`. Also use inspect to check the tableView's `numberOfRows`.

**Cross-comparison:**
- If `dataSource.count > 0` but `numberOfRows == 0` → reloadData wasn't called or timing is wrong
- If `dataSource.count == 0` → data hasn't reached the ViewModel yet, problem is in the data layer
- If both are > 0 but screen is blank → cell height issue or view is obscured, use inspect to investigate further

---

## Action Lifecycle

| Type | Example | Registration | Handling |
|------|---------|--------------|----------|
| Global observation | Get user login status, query cart contents | App launch (AppDelegate) | **Keep** — long-term verification infrastructure |
| Page-scoped | Inspect current page's ViewModel state | Page init / deinit | **Keep** — unregisters automatically on page exit |
| One-off debugging | Print intermediate variables, record call stacks | Temporary | **Delete code** after problem is resolved |

All action code lives inside `#if DEBUG`, so it never appears in production builds — feel free to add liberally.

---

## Verifying the Action Itself Is Correct

A newly added action is also code and can also have bugs. After writing it, always verify:

1. **Known-state test** — call the action with a state you've already confirmed, check if the return is correct
2. **Cross-validation** — if the action returns a value, independently confirm it with another channel (inspect / sandbox)
3. **Timing verification** — confirm the action reads data at the time you expect (not before the data is ready)

If an action's result is inconsistent with what you observe from other channels — doubt the action itself first, then doubt the business code.
