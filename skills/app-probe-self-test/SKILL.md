---
name: app-probe-self-test
description: Use when existing AppProbe capabilities cannot verify an iOS feature or behavior, and you need to create a new HTTP action that returns a verification checklist for automated self-testing and state observation
---

# AppProbe — Self-Test Action Creation

## Overview

Create AppProbe HTTP actions that **return structured checklists for AI-driven automated verification**. The action doesn't just trigger an operation — it tells the AI exactly what changed, how to verify it, and what to check if verification fails. The AI executes the checklist automatically; no human inspection required.

**State data replaces screenshots; checklist replaces manual inspection.**

## When to Use

- Existing observation tools cannot verify a behavior
- Need repeatable verification of an operation (e.g. clone, pull, push)
- Need to expose UI state (button availability, panel visibility) for AI validation
- Fixing a bug that requires observing state transitions

## When NOT to Use

- Simple unit testing → use XCTest / Swift Testing
- UI layout verification → use screenshot / view hierarchy
- One-off debugging → use existing actions

---

## Checklist Verification Loop

This is the **core workflow**. Every operation must be designed so the AI can verify it automatically.

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  1. Discover    │────▶│  2. Operate     │────▶│ 3. AI Verifies  │
│  /module/list   │     │ /module/operate │     │   checklist     │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                                                        │
                              ┌─────────────────────────┘
                              ▼ fail
                        ┌─────────────────┐     ┌─────────────────┐
                        │ 4. AI Debugs    │────▶│ 5. Fix & Repeat │
                        │  per checklist  │     │                 │
                        └─────────────────┘     └─────────────────┘
```

### AI 的验证职责

When an operation action returns a checklist, **the AI MUST automatically verify every item**:

1. **Read `desc`** — understand what should have changed
2. **Execute `verify`** — make the HTTP call specified (usually a status or list action)
3. **Compare** — check if the response matches the expected state described in `desc`
4. **On failure** — read `debug` and follow the debugging steps; read `know` for context

**This is not optional.** The checklist is a verification contract. If the AI doesn't execute it, the action serves no purpose.

---

## Checklist Item Fields

Every checklist item is a **verification instruction for the AI**:

| Field | Purpose | Written For |
|-------|---------|-------------|
| `desc` | What changed / what to expect | AI reads this to understand the assertion |
| `verify` | Exact HTTP call to confirm | AI executes this automatically |
| `know` | Context / assumptions | AI reads this before verifying |
| `debug` | Steps if verification fails | AI follows this when assertion fails |

### `verify` Field Format

The `verify` field **must be executable** by the AI. Use this format:

```
GET /module/name?param=value → expect key == expected_value
```

Or for more complex checks:

```
GET /module/status → response.items should contain "target_name"
GET /view/hierarchy?class=UIButton → expect at least 3 buttons
```

**Bad verify fields** (AI cannot execute):

```
❌ "Check the UI looks correct"           → too vague
❌ "User should see the new item"         → not an HTTP call
❌ "Verify data is persisted"             → no specific endpoint
```

**Good verify fields** (AI can execute):

```
✅ "GET /cart/list → expect count >= 1"
✅ "GET /home/status → response.panelVisible == true"
✅ "GET /view/hierarchy?class=UILabel → find label with text 'Done'"
```

---

## Complete Example: Pull Operation

### Step 1: Discover

```bash
GET /repo/list
```

Response:
```json
{
  "repos": [
    { "name": "my-project", "currentBranch": "main", "hasUncommittedChanges": false }
  ]
}
```

### Step 2: Operate (triggers pull + returns checklist)

```bash
POST /repo/pull?name=my-project
```

Response:
```json
{
  "success": true,
  "message": "Pull completed, 3 commits merged",
  "checklist": [
    {
      "desc": "Latest commit hash should be updated from 'abc1234' to a newer value",
      "verify": "GET /repo/status?name=my-project → response.latestCommit != 'abc1234'",
      "know": "Before pull, latestCommit was 'abc1234'. Pull fetches remote commits.",
      "debug": "If hash unchanged: check network reachability, check remote URL correctness, check if branch has upstream configured"
    },
    {
      "desc": "Working tree should remain clean (no uncommitted changes)",
      "verify": "GET /repo/status?name=my-project → response.hasUncommittedChanges == false",
      "know": "This repo had no uncommitted changes before pull. Pull should be a fast-forward or auto-merge.",
      "debug": "If hasUncommittedChanges is true: check for merge conflicts, check if pull introduced unstaged changes"
    },
    {
      "desc": "Repo list should still contain 'my-project'",
      "verify": "GET /repo/list → response.repos contains item with name == 'my-project'",
      "know": "Pull should not remove or rename the repository.",
      "debug": "If repo missing: check if pull operation corrupted the repo metadata"
    }
  ]
}
```

### Step 3: AI Auto-Verifies

The AI **automatically** executes each `verify`:

1. Calls `GET /repo/status?name=my-project` → checks `latestCommit != 'abc1234'` ✅
2. Calls `GET /repo/status?name=my-project` → checks `hasUncommittedChanges == false` ✅
3. Calls `GET /repo/list` → checks repo still exists ✅

**All pass → operation verified. No human inspection needed.**

### Step 4: If Verification Fails

Say step 2 fails: `hasUncommittedChanges == true`.

The AI reads `debug`: *"check for merge conflicts, check if pull introduced unstaged changes"*

Then the AI:
1. Calls `GET /repo/status?name=my-project` to get detailed conflict info
2. Takes a screenshot (`GET /view/screenshot`) to see if a merge conflict UI appeared
3. Reports: *"Pull introduced uncommitted changes — likely merge conflicts. Screenshot shows conflict resolution dialog."*

---

## Core Pattern

Every verifiable operation follows the same three-action pattern:

```
GET /module/list        → discover targets and their current state
GET /module/operate     → trigger operation + return checklist
GET /module/status      → query component state for verification
```

| Type | Purpose | Example |
|------|---------|---------|
| **Discovery** | List targets and current UI state | `/repo/list` |
| **Operation** | Trigger action + return checklist | `/repo/pull` |
| **Status** | Query component runtime state | `/repo/status` |

---

## Thinking Framework

Before creating an action, reason through this chain:

```
1. What is my problem?
   → bug symptom / feature to verify / state to observe

2. What information do I need?
   → which state values, which data, which timing relationships

3. Can I obtain this information now?
   → can inspect see it? can sandbox read it? can an existing action return it?

4. If not → where does this information live at runtime?
   → a ViewModel property? a Service's state? a queue's length? an in-memory cache?

5. How to correctly obtain and communicate it?
   → read what property? on which thread? return what structure?
```

**Anticipate proactively; don't wait passively.** While writing code, ask: "Can the effect of this change be observed via HTTP?" If not obvious → immediately write an action as part of the feature.

---

## Action Code Skeleton

### Step 1: Register Module (once per module)

```swift
#if DEBUG
AppProbeServer.shared.registerModule(
    name: "repo",
    description: "Git repository operations and status inspection"
)
#endif
```

Only register once per module across the entire app. If another file already registered `"repo"`, skip this step.

### Step 2: Define the Action

```swift
#if DEBUG
final class RepoPullAction: AIAction {
    let module = "repo"
    let name = "pull"
    let httpMethod = "POST"
    let summary = "Pull latest changes from remote, return verification checklist"
    let parameters = [
        APIParameterDescriptor(
            name: "name", type: "String", required: true,
            description: "Repository name to pull"
        )
    ]
    let example = APIExample(
        requestURL: "/repo/pull?name=my-project",
        responseBody: #"{"success":true,"message":"Pull completed","checklist":[...]}"#
    )

    func execute(params: [String: String]) -> ActionResponse {
        guard let repoName = params["name"] else {
            return .error(code: 400, message: "Missing 'name' parameter")
        }

        // ⚠️ Execute on correct thread, read correct data source
        let result = performPull(repoName: repoName)

        // Build checklist for AI auto-verification
        let checklist = [
            ChecklistItem(
                desc: "Latest commit hash should be updated",
                verify: "GET /repo/status?name=\(repoName) → response.latestCommit changed",
                know: "Pull fetches remote commits; hash must differ from pre-pull value",
                debug: "Check network reachability, remote URL, upstream branch config"
            ),
            ChecklistItem(
                desc: "Working tree should remain clean",
                verify: "GET /repo/status?name=\(repoName) → response.hasUncommittedChanges == false",
                know: "Repo had no uncommitted changes before pull",
                debug: "Check for merge conflicts or unstaged changes introduced by pull"
            )
        ]

        let response = ActionResultWithChecklist(
            success: result.success,
            message: result.message,
            checklist: checklist
        )
        return .json(response)
    }
}
#endif
```

### Step 3: Register at the Right Time

```swift
#if DEBUG
// Global observation → register at app launch, keep for lifetime
AppProbeServer.shared.register(RepoPullAction())

// Page-scoped → register on init, unregister on deinit
class SomeViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        AppProbeServer.shared.register(PageSpecificAction())
    }
    deinit {
        AppProbeServer.shared.unregister(module: "page", name: "state")
    }
}

// One-off debugging → register temporarily, delete code after resolved
#endif
```

---

## ActionResponse Reference

| Case | HTTP Status | When to Use |
|------|-------------|-------------|
| `.json(any Codable)` | 200 | Success — structured data (including checklist) |
| `.jsonWithStatus(any Codable, statusCode: Int)` | Custom | Non-200 JSON (e.g. 404 with details) |
| `.raw(data: Data, contentType: String, headers: [String: String])` | 200 | Binary (images, files) |
| `.error(code: Int, message: String)` | Custom | Simple error (`{"error": message, "statusCode": code}`) |

---

## Async Considerations

`execute` is **synchronous**.

- **Main-thread UI state:** Use `DispatchQueue.main.sync { ... }`
- **Async operation results:** Read the *last known state* (cached value, property set by completion handler). Don't trigger and wait for async work inside `execute`.
- **Truly need async observation:** Create an action that *starts* observation and writes to a known location (UserDefaults / file), then read that location with a second call.

---

## Action Lifecycle

| Type | Example | Registration | Handling |
|------|---------|--------------|----------|
| Global observation | User login status, cart contents | App launch | **Keep** — long-term infrastructure |
| Page-scoped | Current page's ViewModel state | Page init / deinit | **Keep** — auto-unregisters on exit |
| One-off debugging | Print intermediates, record stacks | Temporary | **Delete code** after resolved |

All action code is inside `#if DEBUG` — never appears in production.

---

## End-to-End Verification

After writing an action, verify the full loop:

```bash
# 1. Build and run the app
# 2. Verify it appears in the catalog
curl "http://localhost:47180/catalog?module=repo"

# 3. Call the action
curl -X POST "http://localhost:47180/repo/pull?name=my-project"

# 4. Verify response contains checklist with valid verify fields
# 5. Execute each verify call manually to confirm they work
```

---

## Verify the Action Itself

A new action is also code and can have bugs. After writing it:

1. **Known-state test** — call with a confirmed state, check return correctness
2. **Cross-validation** — independently confirm with another channel (inspect / sandbox)
3. **Timing verification** — confirm it reads data at the expected time
4. **Checklist sanity** — manually execute each `verify` URL to ensure it resolves correctly

If an action's result contradicts other channels — doubt the action first, then the business code.

---

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| `verify` field is vague or not an HTTP call | Must be a specific `GET/POST /path` the AI can execute |
| Checklist items lack `debug` guidance | AI cannot self-repair when verification fails |
| Returning view frames in list action | Use `/view/hierarchy` separately |
| Using screenshots for verification | Create dedicated status action |
| Returning business state not UI state | Source from ViewModel, not models |
| Missing error responses | Return 400/404/409 with context |
| Forgetting `#if DEBUG` wrapper | Always wrap action code |
| Registering module multiple times | Check if already registered elsewhere |

---

## Related

- **app-probe-debug** — Discovery, multi-channel verification, and built-in capability usage
