---
name: app-probe-debug
description: Use when debugging or verifying iOS app behavior via AppProbe HTTP inspection, observing UI state, reading local data, triggering operations, or resolving disagreements between multiple observation channels
---

# AppProbe — Discovery & Verification

## Overview

AppProbe provides an HTTP bridge to the running iOS app. Use it to observe UI, read data, trigger logic, and — when existing capabilities are insufficient — create new observation endpoints. All verification follows multi-channel cross-validation.

## Core Principles

**1. Discover first; create what's missing**

Query the catalog before assuming a capability doesn't exist. If nothing matches, add an action — never give up verification because "there's no API."

**2. Multi-channel cross-validation**

Confirm through at least two independent channels. Screenshot + hierarchy + action + sandbox — signals that agree build confidence; signals that contradict reveal the real problem (often the observation method itself).

**3. Doubt your tools**

When logic seems correct but HTTP returns unexpected results, check the observation method first — data source, timing, thread. Older actions have higher probability of being out of sync with current code.

## Connection

| Environment | Base URL |
|-------------|----------|
| Simulator | `http://localhost:47180` |
| Real device | User provides IP address |

On connection failure, auto-retry ports 47181–47189. Still failing → ask user to confirm address.

## Capability Discovery

Three-step discovery flow:

```
GET /                    → module overview (names + descriptions)
GET /catalog?module=X    → API list for module X
GET /catalog/detail?path=/X/Y → detailed usage for one API
```

The `hint` field in every response tells you the next call — just follow it.

## Built-in Modules

| Module | Purpose |
|--------|---------|
| **catalog** | Discovery: module overview, API list, detail queries |
| **status** | Server and app status |
| **view** | UIView inspection: hierarchy, properties, screenshots, highlight |
| **vc** | UIViewController inspection: VC hierarchy, topmost VC |
| **sandbox** | Sandbox file ops: browse, read/write, SQLite queries |
| **userDefaults** | Read, set, delete UserDefaults key-value pairs |
| **log** | Recent console logs (`systemLogs=true` to include system) |

Business modules register custom actions at runtime.

## Decision Paths

### Changed UI → confirm effect

```
screenshot (/view/screenshot) → view hierarchy (/view/hierarchy)
→ VC hierarchy (/vc/hierarchy) → highlight if uncertain
```

⚠️ **Never skip screenshot.** Hierarchy alone can mislead — a view may exist but be obscured, zero-sized, or off-screen.

### Need local persisted data

```
sandbox/list → sandbox/sql or sandbox/file
```

### Need user preferences

```
userDefaults list/read → userDefaults/set or userDefaults/delete
```

### Need recent logs

```
log/recent → add systemLogs=true if system framework logs needed
```

### Changed business logic → confirm behavior

```
check catalog for action → if exists, call it → if not, create one → verify
```

### Bug → locate cause

```
gather from multiple channels → cross-compare → contradiction = clue
```

## Multi-Channel Verification Example

```
Suspect data wasn't written:
  Channel 1: sandbox/sql → not found in DB
  Channel 2: UI inspect → shows empty
  Channel 3: action → in-memory state shows written

  → Conflict! Data is in memory but not persisted to disk.
```

## Need a New Action?

When existing capabilities are insufficient, use **app-probe-self-test** for the complete thinking framework and implementation guide.

Key point: it's not about filling a template — it's reasoning through what information you need, where it lives, and how to correctly obtain it.
