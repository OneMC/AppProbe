---
name: ai-debug-power
description: Use during iOS app development to discover, invoke, and create verification capabilities on the running app via HTTP — forming a write-build-discover-verify-fix loop with multi-channel cross-validation
---

# AppProbe — Autonomous Discovery & Verification

You have an HTTP bridge to the running iOS app. Through it you can observe UI, read data, trigger logic — and more importantly, when existing capabilities aren't enough, you can **create new observation capabilities yourself**.

---

## Core Principles

### 1. Discover Capabilities; Create What's Missing

When you need to verify or observe some state, first query the catalog for an existing capability. If none is found, proactively add an action to gain that capability. **Never give up verification just because "there's no existing API" — capabilities can be created.**

### 2. Multi-Channel Cross-Validation

When diagnosing issues or verifying features, **confirm through at least two independent channels**. What inspect shows, what an action returns, what sandbox reads — if multiple signals contradict, it means an observation method itself is faulty, not that you should rush to conclusions.

Multiple signals agree → confidence. Signals contradict → the contradiction itself is the most valuable clue.

### 3. Proactively Build Verification Capabilities

While writing code, think: "How can I verify this change took effect via HTTP?"

If the answer isn't obvious, **immediately add an action** as part of the feature implementation. Don't finish writing code and say "please test manually" — you have the ability to verify it yourself.

### 4. Doubt Your Observation Tools

When you're confident the code logic is correct but HTTP returns unexpected results:

1. First check the observation method itself — is this action reading the right data source? Right timing? Right thread?
2. The older an action's registration, the higher the probability it's out of sync with current code
3. Cross-verify with another channel

**Your eyes (observation tools) can also be broken. When you find contradictions, check your eyes before checking the road.**

---

## Connection

| Environment | Base URL |
|-------------|----------|
| Simulator | `http://localhost:47180` |
| Real device | User must provide the actual IP address |

Default: `http://localhost:47180`. Verification: `GET /` — connection succeeds if catalog info is returned.

On connection failure:
1. Simulator — automatically try incrementing ports (47181, 47182 ... 47189)
2. Still failing — ask the user to confirm the address or device network status

---

## Capability Discovery Flow

Capabilities are dynamically registered and may change at any time. Discover currently available capabilities in three steps:

### Step 1: Get Module Overview

```
GET /
```

Response structure:
```json
{
  "moduleCount": 7,
  "modules": [
    {
      "name": "sandbox",
      "description": "Sandbox file management: browse directories, read/write files, SQLite queries, and file deletion",
      "apiCount": 6,
      "listApis": "GET /catalog?module=sandbox"
    },
    {
      "name": "catalog",
      "description": "API catalog queries",
      "apiCount": 2,
      "apis": [ ... ]
    },
    ...
  ],
  "hint": {
    "listApis": "GET /catalog?module={name}",
    "getDetail": "GET /catalog/detail?path={api_path}"
  }
}
```

**Notes:**
- The `hint` field tells you exactly how to make the next call — just follow it.
- The `catalog` and `status` modules are the discovery mechanism itself and inline their full API lists (no need for Step 2).
- Other modules only provide an overview; use Step 2 to get their API list, then Step 3 for detailed usage.

### Step 2: Get API List for a Specific Module

```
GET /catalog?module={name}
```

Response structure:
```json
{
  "apiCount": 6,
  "apis": [
    {
      "path": "/sandbox/list",
      "method": "GET",
      "summary": "Browse directory contents",
      "module": "sandbox"
    },
    ...
  ]
}
```

### Step 3: Get Detailed Usage for a Single API

```
GET /catalog/detail?path={api_path}
```

Response structure:
```json
{
  "path": "/sandbox/list",
  "method": "GET",
  "summary": "Browse directory contents",
  "module": "sandbox",
  "parameters": [
    { "name": "path", "type": "String", "required": false, "description": "Path relative to sandbox root; omit to list the sandbox root directory" }
  ],
  "example": {
    "requestURL": "/sandbox/list?path=Documents",
    "responseBody": "{...}"
  }
}
```

---

## Built-in Capability Overview

Below are the built-in modules. Specific endpoints and parameters are obtained through the discovery flow above; this only describes their purpose:

| Module | Purpose |
|--------|---------|
| **catalog** | Discovery mechanism: API catalog queries (module overview, filter, detail) |
| **status** | Server and app status monitoring |
| **view** | UIView inspection: hierarchy tree, properties, screenshots, highlight markers. Quickly locate UI issues |
| **vc** | UIViewController inspection: VC hierarchy tree, topmost VC. Verify navigation and page structure |
| **sandbox** | Sandbox file operations: browse directories, read/write files, SQLite queries. Verify local persisted data |
| **userDefaults** | User preferences storage: read, set, delete UserDefaults key-value pairs |
| **log** | Log queries: recent console logs (system logs filtered by default, `systemLogs=true` to include) |

**Business modules register their own custom modules and actions at runtime.**

---

## Decision Paths

### → Changed UI, need to confirm the effect

```
screenshot for visual overview → view/hierarchy for specific view properties
→ vc/hierarchy for VC structure → highlight to locate if uncertain
```

### → Need to query locally persisted data

```
sandbox/list to find target file/database → sandbox/sql or sandbox/file to verify content
```

### → Need to read/modify user preferences

```
userDefaults to list/read → userDefaults/set or userDefaults/delete to modify
```

### → Need to check recent logs

```
log/recent for app logs → add systemLogs=true if system framework logs needed
```

### → Changed business logic, need to confirm correct behavior

```
check catalog for a corresponding action → if exists, call it → if not, create one → call to verify
```

### → Encountered a bug, need to locate the cause

```
gather info from multiple channels (screenshot + view/hierarchy + vc/hierarchy + sandbox + action)
→ cross-compare → the contradiction point is the clue
```

**All paths converge to:** observe → cross-validate → if signals conflict, doubt the observation method itself.

---

## Multi-Channel Verification in Practice

**Never draw conclusions from a single channel.** Example:

```
You suspect some data wasn't written →
  Channel 1: sandbox/sql queries database → not found
  Channel 2: inspect the corresponding UI → shows empty
  Channel 3: action queries in-memory state → shows written

  → Signal conflict! The problem is "written to memory but not persisted to disk"
```

**Doubt mechanism:**

- Logic confirmed correct but observation doesn't match expectations → first examine the observation method (data source? timing? thread?)
- The older an action's registration, the lower its confidence → prioritize re-checking old action implementations
- Verify the same thing with another independent channel → only draw conclusions when two channels agree

### UI Verification Protocol

**Any UI change MUST include screenshot verification.** When encountering UI issues, follow this mandatory sequence:

1. **Screenshot first** — `GET /view/screenshot` (no params = full window; `?tag=N` / `?class=XXX` for specific views)
2. **View hierarchy** — `GET /view/hierarchy` to inspect UIView layer (frame, hidden, alpha, constraints)
3. **VC hierarchy** — `GET /vc/hierarchy` to inspect UIViewController layer (topmost VC, presentation)

⚠️ Do NOT skip the screenshot step. Hierarchy data alone can be misleading — a view may exist in the hierarchy but be visually obscured, zero-sized, or off-screen. Screenshots provide visual ground truth.

Screenshot quick ref: `GET /view/screenshot` (full window), `?tag=N` / `?class=XXX` / `?address=0x...` (specific view), `&quality=0.8&format=png` (options). Save with `curl -o file.jpg <url>`.

Save verification results to `{project_root}/.appprobe/YYYYMMDD-title/` (screenshots, hierarchy JSON). This directory should be in `.gitignore`.

---

## Need to Add an Action?

When you determine existing capabilities are insufficient to verify your changes or locate a problem, read [ACTION_THINKING_GUIDE.md](./ACTION_THINKING_GUIDE.md) for the complete thinking framework and writing guide.

Key point: it's not about filling in a template — it's about reasoning: what's the problem, what information do I need, where is that information, how to correctly obtain it.
