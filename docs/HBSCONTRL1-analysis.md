# Code Analysis: HBSCONTRL1.SQLRPGLE

**Analyzed:** April 13, 2026  
**Program:** BSL Server Control Program  
**Purpose:** Socket listener, spawn manager, and controller for BSL subsystem jobs (receive workers, handler jobs, push jobs)

---

## Summary

Thirteen issues were identified across the program. Four are **critical** and directly explain the spawn reliability problems reported. Issues #1–#4 below are the most likely root causes of spawn failures.

---

## Critical Issues

### 1. `DLTPGM` Executes Before Every Spawn

**Location:** `RecvJobs` procedure, inside `For COUNTC = 1 to CHILD#` loop

The following command runs before every `spawnp` call:

```
Qcmd = 'DLTPGM PGM(' + %trim(ServerLibrary) + '/' + %trim(WorkerName) + ')';
system(qcmd);
```

`WorkerName` resolves to a name like `B540R3021`. If this object exists in the library, it is deleted before the spawn. This is almost certainly leftover test cleanup code that was never removed. At a minimum it adds unnecessary overhead; at worst it deletes an unintended object.

**Recommendation:** Remove this `DLTPGM` block entirely unless there is a documented reason for it.

---

### 2. All Spawned Workers Receive the Same Job Name

**Location:** `RecvJobs` procedure

`WorkerName` is assigned **twice** with identical values, ignoring the counter variable `countc3`:

```
WorkerName = 'B' + bankno + 'R' + %char(port);   // before the loop
...
eval countc3 = %char(pcount);                      // calculated but unused
WorkerName = 'B' + bankno + 'R' + %char(port);    // same value re-assigned inside loop
```

When `child# > 1`, all spawned jobs collide on the same job name. The system will reject or rename the duplicates, causing unpredictable behavior. The counter `countc3` was clearly intended to differentiate job names but is never incorporated.

**Recommendation:** Change the inner assignment to use `countc3`, e.g.:

```
WorkerName = 'B' + bankno + 'R' + %char(port) + %trim(countc3);
```

---

### 3. Socket Pair Array Index `p` Is Never Incremented Across Ports

**Location:** `RecvJobs` procedure

`p` is set to `1` at the top of `RecvJobs` and is never incremented across calls. `ser(p)` and `job(p)` therefore always write to slot 1:

```
p = 1;
job(p) = Child#;
...
ser(p) = svec(1);
```

When `RecvJobs` is called for multiple ports (inside the `For I by 1 to totports` main loop), each call overwrites `ser(1)`. Only the last port's socket pair survives into `sendmsg`. All previously accepted connections lose their socket reference.

**Recommendation:** Pass `I` (the port loop index) into `RecvJobs` and use it as the `p` index, or increment `p` based on the current port.

---

### 4. `w_dta` vs. `w_dta30` Mismatch — Six of Seven Commands Never Fire

**Location:** Main `dow *inlr = *off` loop, after `CheckQue` call

`CheckQue` populates `w_dta30` (30-char field). The initial check is correct, but all subsequent comparisons switch to `w_dta` (10-char field, not populated by `CheckQue`):

| Command | Variable Used | Result |
|---------|--------------|--------|
| `00001` — End controller | `w_dta30` | Works correctly |
| `00002` — End listen port | `w_dta` | **Never fires** |
| `00003` — Start listen port | `w_dta` | **Never fires** |
| `20001` — End one handler | `w_dta` | **Never fires** |
| `20002` — Start one handler | `w_dta` | **Never fires** |
| `30001` — End one push | `w_dta` | **Never fires** |
| `30002` — Start one push | `w_dta` | **Never fires** |
| `40001` — End one receive | `w_dta` | **Never fires** |

Dynamic control of the subsystem (starting/stopping individual ports, handlers, push jobs) is completely non-functional as a result.

**Recommendation:** Change all `%subst(w_dta : ...)` comparisons in this block to `%subst(w_dta30 : ...)`.

---

## High Severity Issues

### 5. SSL Configuration Always Uses Port 1 for All Children

**Location:** `RecvJobs` procedure

```
childParm.SSLSEC = abnkports(1).p_ssltls;
childParm.APPID  = abnkports(1).p_appid;
```

These are hardcoded to index `1` regardless of which port is currently being processed. Workers spawned for ports 2, 3, etc. always receive port 1's SSL configuration.

**Recommendation:** Replace `abnkports(1)` with `abnkports(I)` where `I` is the current port loop index passed into `RecvJobs`.

---

### 6. `fdmap` Assignment Is Dead — `socklisten` Is Always `-1`

**Location:** `RecvJobs` procedure

```
fdmap(1) = socklisten;
pid2 = spawnp(path : fd_count : *Omit : inherit : argv : envp);
```

`socklisten` is declared `inz(-1)` and never assigned a valid socket descriptor anywhere in the program. Additionally, `*Omit` is passed for `fd_map`, so the `fdmap` assignment has no effect. This appears to be a remnant of an earlier design intended to pass the accepted socket into the child's fd table.

**Recommendation:** Determine whether the child program (`HBSCHILD1`) needs the socket passed via `fd_map`. If so, pass the accepted socket descriptor and remove `*Omit`. If not, remove the dead `fdmap` and `socklisten` references.

---

### 7. Stale `qdlen` in `EndHandler` Data Queue Send

**Location:** `EndHandler` procedure

`EndHandler` calls `SndDtaq(hbsrdtaq:w_dtaqlib:qdlen:w_QDATA2)` where `w_QDATA2` is 46 bytes. However, `qdlen` is a module-level field and retains whatever value was last set by any prior operation (10, 36, or 46 depending on execution path). Sending the wrong length to the data queue results in truncated or corrupted messages.

**Recommendation:** Set `qdlen = 46` explicitly at the start of `EndHandler` before the `SndDtaq` call (consistent with how `WrtDtaq` handles it).

---

### 8. 100ms Sleep Per Port Per Main Loop Cycle

**Location:** Main `dow *inlr = *off` loop

```
sockAccept = accept(sockList(I): %addr(sockaddrin): LenSckAdIn);
...
usleep(0100000);   // 100ms sleep after processing all ports
```

The sleep runs after every pass through the accept loop. With 3 ports configured, connection acceptance lags by up to 300ms per loop cycle under any load. This reduces maximum connection throughput and increases latency for incoming connections.

**Recommendation:** Reduce the sleep value, or replace with a `select()`/`poll()` call to wait on all sockets simultaneously rather than polling in a timed loop.

---

### 9. `Scheduler()` Reads and Updates `HBSFSCHED` on Every Main Loop Iteration

**Location:** Main loop, `Scheduler` procedure call

The `Scheduler()` call reads all scheduler records for the bank, performs timestamp comparisons, and issues `UPDATE` statements on every pass of the main loop — which already runs at least every 100ms due to the `usleep`. Over a day this results in hundreds of thousands of unnecessary file reads and potential update operations.

**Recommendation:** Add a throttle so `Scheduler()` only runs once per second (or less frequently) by comparing the current timestamp to a `LastSchedCheck` timestamp variable before calling the procedure.

---

## Medium Severity Issues

### 10. `tothand`/`totpush` Reset to 0 on Re-Submit

**Location:** `SbmHandler` and `SbmPush` procedures

Both procedures zero out the running total at the start:

```
tothand = 0;
For COUNTC = 1 to worker#;
  tothand +=1;
```

If either procedure is called a second time (triggered by commands `20002`/`30002`), the count of previously-submitted jobs is lost. `EndHandler`/`EndPush` will then only iterate over the count from the most recent submit, leaving earlier jobs without end signals.

**Recommendation:** Remove the `tothand = 0` / `totpush = 0` reset lines, or maintain separate per-batch arrays rather than a single running total.

---

### 11. Fixed-Duration Waits in `EndController` Without Verification

**Location:** `EndController` procedure

```
usleep(1000000);   // 1 sec after EndPush
usleep(1000000);   // 1 sec after EndHandler
usleep(1000000);   // 1 sec after EndRecv
usleep(2000000);   // 2 sec additional grace period
```

Under load, 1 second may be insufficient for child jobs to actually end before sockets are closed. Under normal conditions, 5 seconds is wasted on every controlled shutdown.

**Recommendation:** Poll `QSYS2.ACTIVE_JOB_INFO` for the relevant job names after sending end signals, with a timeout, rather than relying on fixed sleep durations.

---

### 12. Possible Null Pointer Free After JSON Parse Error in `GetParms`

**Location:** `GetParms` procedure

If `yajl_buf_load_tree` fails (returns null), `docnode` will be null. The `on-error` block sets defaults, but `yajl_tree_free(docnode)` is called unconditionally after `endmon`. Passing a null pointer to `yajl_tree_free` may cause an MCH3601 (pointer not set) exception.

**Recommendation:** Guard the free call:

```
if docnode <> *null;
  yajl_tree_free(docnode);
endif;
```

---

### 13. `w_guid2` Cleared Mid-Loop in `EndPush`

**Location:** `EndPush` procedure

After sending `'CONTROL'` to the push queue:

```
For I by 1 to totpush;
  SndDtaq(hbsdtaq:w_dtaqlib:qdlen:w_guid2);
  clear w_guid2;        // clears after first iteration
endfor;
```

Iterations 2 through `totpush` send a blank GUID to the push data queue instead of `'CONTROL'`.

**Recommendation:** Move `clear w_guid2` to after the loop, or set `w_guid2 = 'CONTROL'` inside the loop before each send.

---

## Issue Summary

| # | Issue | Location | Severity |
|---|-------|----------|----------|
| 1 | `DLTPGM` runs before every spawn | `RecvJobs` loop | **Critical** |
| 2 | All spawned workers get identical job name | `RecvJobs` For loop | **Critical** |
| 3 | Socket pair index `p` never increments | `RecvJobs` | **Critical** |
| 4 | `w_dta` vs `w_dta30` — 6 of 7 commands never fire | Main loop | **Critical** |
| 5 | SSL config always sourced from port 1 | `RecvJobs` | High |
| 6 | `fdmap` dead; `socklisten` always `-1` | `RecvJobs` | High |
| 7 | Stale `qdlen` in `EndHandler` send | `EndHandler` | High |
| 8 | 100ms sleep per port per loop cycle | Main accept loop | High |
| 9 | Full scheduler scan every loop pass | `Scheduler` call | High |
| 10 | `tothand`/`totpush` reset to 0 on re-submit | `SbmHandler`/`SbmPush` | Medium |
| 11 | Fixed-time waits in `EndController` | `EndController` | Medium |
| 12 | Possible null `docnode` free on parse error | `GetParms` | Medium |
| 13 | `w_guid2` cleared mid-loop in `EndPush` | `EndPush` | Medium |
