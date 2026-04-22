# BSL Multi-Port Capability: Benefits and Implementation Path

**Written:** April 2026  
**Context:** HBSCONTRL1 / HBSCHILD1 / HBSHANDLR architecture review

---

## 1. Overview

The BSL subsystem controller (`HBSCONTRL1`) already contains a partially-implemented multi-port architecture. The data structures, queue naming conventions, and accept loop all anticipate multiple simultaneous listen ports per bank — but four bugs in the `RecvJobs` procedure prevent the design from functioning correctly when more than one port is active.

This document describes:
- What the multi-port design was intended to deliver
- The operational and architectural benefits it would provide
- What work is required to make it functional
- Why it is worth completing even if multiple ports are not immediately activated

---

## 2. What the Design Already Provides

The existing code reflects a deliberate multi-port architecture, not an accident:

| Existing Element | Evidence of Intent |
|---|---|
| `socklist dim(8) inz(-1)` | Array of 8 listen socket descriptors — one per port |
| `rcvport dim(8)` | Corresponding port numbers for each socket |
| `totrecv dim(8)` | Per-port active worker count tracking |
| `For I by 1 to totports` | Accept loop iterates all active ports each cycle |
| Queue name built as `'HBSRCVQ' + %subst(a_port:3:3)` | Port-keyed receive queue names (e.g., `HBSRCVQ021`, `HBSRCVQ022`) |
| `rcvport(I) = 99999` sentinel value | Dynamic port disable/enable without array resize |
| Control commands `00002`/`00003` | Runtime add/remove of individual listen ports |

The framework is there. The bugs that prevent it from working are concentrated in a single procedure (`RecvJobs`) and are straightforward to fix.

---

## 3. Operational Benefits of Multiple Ports

### 3.1. Request Priority and QoS Isolation

This is the most compelling benefit for BSL. Each port has its own fully independent pipeline:

```
Port 3021  →  HBSRCVQ021  →  HBSCHILD1 workers  →  HBSHANDLR pool A
Port 3022  →  HBSRCVQ022  →  HBSCHILD1 workers  →  HBSHANDLR pool B
```

Practical example:

| Port | Service Type | Characteristic |
|---|---|---|
| 3021 | JWT token issuance | Time-critical — called on every login |
| 3022 | Account inquiry / bulk data | Lower priority — potentially slow responses |

With a single port, a flood of bulk requests can fill the single receive queue and delay token issuance for every user trying to log in at the same time. With two ports, the pipelines are completely independent — neither can starve the other regardless of load on the other side.

This is effectively a hardware-free quality-of-service layer built directly into the BSL socket architecture.

### 3.2. Per-Port Handler Pool Sizing

`SbmHandler` and `SbmPush` currently submit a fixed number of handler and push jobs configured globally per bank. With multiple ports each port could be given its own handler count:

- High-volume, low-latency port: 3 handler jobs
- Bulk / lower-priority port: 1 handler job

This provides capacity allocation without any job priority or pool management complexity — the jobs simply run in separate pools and the system naturally balances.

### 3.3. Independent Failure Isolation

If the handler pool on one port encounters a problem (corrupted request, runaway job, queue saturation), the other port's pipeline continues completely unaffected. With a single port, a handler issue stops processing for the entire bank.

This is particularly relevant for BSL because `HBSHANDLR` calls arbitrary host service programs — a misbehaving service on one port cannot take down services on another.

### 3.4. External Network Segmentation

Different ports can be given different network-level treatment:

- Firewall rules that allow port 3021 from all internal networks but restrict port 3022 to specific source IPs
- Load balancer health checks per port
- Network monitoring per service category

`HBSCONTRL1` manages all of this with a single controller job — no additional processes required.

### 3.5. Runtime Port Management Without Restart

The control queue commands `00002` (close one port) and `00003` (open one port) allow individual ports to be added or removed at runtime without stopping the controller or other ports. Once the `w_dta` vs `w_dta30` bug (analysis issue #4) is fixed, this capability becomes functional.

This means a new service category can be activated by sending a single data queue command — no subsystem restart, no disruption to existing ports.

---

## 4. What Needs to Be Fixed

Four bugs in `HBSCONTRL1` and one declaration change prevent multi-port from working. All are in or adjacent to the `RecvJobs` procedure and the main accept loop. None require architectural redesign.

### 4.1. Analysis Issue #2 — Duplicate Job Names on Spawn

**Location:** `RecvJobs`, inner `For COUNTC` loop  
**Problem:** `WorkerName` is assigned `'B' + bankno + 'R' + %char(port)` both before and inside the spawn loop. The counter `countc3` is calculated but never used in the name. When `child# > 1`, all spawned jobs get identical names, causing system collisions.  
**Fix:** Incorporate `countc3` into the inner assignment:

```rpgle
WorkerName = 'B' + bankno + 'R' + %char(port) + %trim(countc3);
```

### 4.2. Analysis Issue #3 — Socket Pair Index Never Increments Across Ports

**Location:** `RecvJobs` procedure  
**Problem:** `p` is hardcoded to `1` at the top of `RecvJobs`. When the main accept loop calls `RecvJobs` for ports 2, 3, etc., each call overwrites `ser(1)` and `job(1)`. Only the last port's socket pair survives. All prior accepted connections lose their socket reference before the `sendmsg` call.  
**Fix:** Pass the current port loop index `I` into `RecvJobs` as a parameter and use it as the `p` index:

```rpgle
D RecvJobs  pi  10i 0 opdesc
D   port        5  0
D   child#      3  0
D   portIdx     3  0     // Add: current port loop index

// Inside RecvJobs:
p = portIdx;
ser(p) = svec(1);
job(p) = Child#;
```

### 4.3. Analysis Issue #5 — SSL Config Always Sourced from Port 1

**Location:** `RecvJobs` procedure  
**Problem:** `childParm.SSLSEC` and `childParm.APPID` are hardcoded to `abnkports(1)` regardless of which port is being processed. Workers spawned for ports 2–8 receive port 1's configuration.  
**Fix:** Use the passed port index:

```rpgle
// Before:
childParm.SSLSEC = abnkports(1).p_ssltls;
childParm.APPID  = abnkports(1).p_appid;

// After:
childParm.SSLSEC = abnkports(portIdx).p_ssltls;
childParm.APPID  = abnkports(portIdx).p_appid;
```

### 4.4. Analysis Issue #4 — `w_dta` vs `w_dta30` Mismatch

**Location:** Main `dow *inlr = *off` loop, after `CheckQue`  
**Problem:** `CheckQue` populates `w_dta30` (30-char). Six of the seven control commands then compare against `w_dta` (10-char, never populated), so dynamic port management commands `00002`/`00003` never fire.  
**Fix:** Change all six `%subst(w_dta : ...)` comparisons to `%subst(w_dta30 : ...)`.

### 4.5. `poll()` — Accept Loop Replacement (Optional but Recommended)

**Location:** Main accept loop, replacing `usleep` + sequential `accept`  
**Problem:** The current `usleep(0100000)` + sequential per-port `accept` means that with N ports active, each port is checked at most once every 100ms × N. Under connection load the loop burns CPU polling sockets that have no pending connections.  
**Fix:** Replace with `poll()`, which blocks the kernel until any of the watched sockets has a pending connection, then returns immediately. With a `timeout` of 100ms, the loop cadence for `CheckQue` and the scheduler is preserved. With a single port the behavior is functionally identical to `usleep` except connections are accepted within <1ms of arrival rather than up to 100ms.

See [HBSCONTRL1-analysis.md](HBSCONTRL1-analysis.md) issue #8 for full context.

**Key implementation note — `pollfd` DS field sizes:**

The `poll()` C API `struct pollfd` uses `short` (2-byte) integers for `events` and `revents`. In RPG these must be declared `int(5)`, not `int(10)`. Using `int(10)` produces a silently misaligned structure with no compile error.

```rpgle
dcl-ds pollfd_t qualified template;
  fd      int(10);   // C int   — 4 bytes
  events  int(5);    // C short — 2 bytes  ← must be int(5)
  revents int(5);    // C short — 2 bytes  ← must be int(5)
end-ds;

dcl-c POLLIN const(1);

dcl-pr poll int(10) extproc('poll');
  fds     likeds(pollfd_t) options(*varsize);
  nfds    uns(10) value;
  timeout int(10) value;      // milliseconds
end-pr;
```

---

## 5. Relationship to HBSCHILD1 and HBSHANDLR

No changes are required to `HBSCHILD1` or `HBSHANDLR` to support multiple ports. Each `HBSCHILD1` instance receives its port-specific receive queue name via `childParm` at spawn time and operates independently. Each `HBSHANDLR` instance reads from whichever queue it was submitted against. The port isolation is entirely implemented at the controller and queue-naming layer.

The one `HBSCHILD1` consideration: `HBSCONTRL1` currently reads `HBSCHILD1` by name in the `spawnp` path:

```rpgle
path = '/QSYS.LIB/' + %trim(ServerLibrary) + '.LIB/HBSCHILD1.PGM' + x'00';
```

All ports use the same `HBSCHILD1` program — only the queue name they receive as a spawn argument differs. This is correct and requires no change.

---

## 6. Implementation Effort Estimate

| Change | Scope | Estimated Effort |
|---|---|---|
| Issue #2 — Job name counter | 2-line change in `RecvJobs` inner loop | Trivial |
| Issue #3 — Port index parameter | Add one parameter to `RecvJobs` PI/PR, use it for `p` | Small |
| Issue #5 — SSL config index | 2-line change in `RecvJobs` | Trivial |
| Issue #4 — `w_dta` → `w_dta30` | 6 substitution changes in main loop | Small |
| `poll()` accept loop | New DS + PR + rewrite of accept block | Moderate |

Issues #2, #3, #4, and #5 together represent perhaps 2 hours of work including testing. `poll()` adds another hour plus testing under load. None require changes to database objects, binding directories, or dependent programs.

---

## 7. Recommended Approach

**Phase A (now):** Apply fixes #2, #3, #4, and #5. This makes the existing multi-port framework correct without activating it — the system continues to run on a single port per bank, but the code is no longer broken if a second port is ever added.

**Phase B (with Phase A or separately):** Implement `poll()` to replace the `usleep` + sequential accept loop. This is independent of multi-port activation and provides a marginal latency improvement for the single-port case while making the accept loop correctly scalable for multi-port.

**Phase C (operational decision):** Configure a second port per bank for a specific service category (e.g., a high-volume or time-critical service). At that point the isolation benefits described in section 3 become realized. No further code changes are required — it is a configuration and deployment decision.

---

## 8. Current State vs. Target State

| Capability | Current State | After Phase A+B |
|---|---|---|
| Single port per bank | Works | Works (improved latency) |
| Multiple ports per bank | Broken (spawn bugs) | Fully functional |
| Runtime port add/remove | Broken (`w_dta` bug) | Functional |
| Connection acceptance latency | Up to 100ms | < 1ms (poll wakeup) |
| Accept loop CPU under multi-port load | Busy-polls all ports | Event-driven, kernel-managed |
| Per-port QoS isolation | Not available | Available via configuration |
