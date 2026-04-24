# Proposal: BSL Subsystem Rewrite

## 1. Executive Summary

This document proposes a comprehensive architectural change to the BSL Subsystem to improve performance, throughput, and operational flexibility. It consolidates several key initiatives into a single, unified project plan:

1.  **Asynchronous Logging:** Offload all database logging writes to a separate, persistent writer job to eliminate I/O bottlenecks in the main transaction path.
2.  **Database Schema Refactoring:** Normalize the existing `HBSRECV` and `HBSSEND` tables into a cleaner, more efficient structure (`HBSTRANS`, `HBSREQ`, `HBRESP`) to reduce data redundancy.
3.  **Flexible Service Architecture:** Provide two distinct, configurable options for the host service program architecture, allowing a choice between maximum performance and operational agility.

Communication between the main application programs and the new writer job will be handled via a high-speed **Data Queue**. This eliminates the overhead of submitting a new job for every transaction. Additionally, the proposal introduces a configuration file to enable or disable this logging on a per-service basis, providing granular control without requiring code changes.

This unified design represents the most scalable, maintainable, and robust solution for the identified performance and architectural issues.

## 2. Phased Implementation Plan

The project will be implemented in two distinct phases to manage complexity and reduce risk.

### Phase 1: Database Refactoring (Synchronous) ✅ Code-Complete
1.  **Create New Tables:** Define and create the new `HBSTRANS`, `HBSREQ`, and `HBRESP` tables. ✅
2.  **Refactor Application:** Modify the application to write to the new tables synchronously. ✅ (`HBSHANDLR`, `HBSCHILD1`, `HBSWORK` all updated)
3.  **Test & Deploy:** Validate and deploy the synchronous refactoring to establish a stable foundation.

### Phase 1b: Logging & Observability Improvements ✅ Code-Complete
These changes were applied alongside Phase 1 to bring the production member-tracked changes into the local codebase.

1.  **ssp22 — GUID Logs to HBSLOGF:** Replaced all `hbstools_Actvty()` calls in `HBSHANDLR` with `hbstools_CrtLog(...:'Y')`. Log entries now go to the `HBSLOGF` table via the new `hbstools_CrtLog` API, which retrieves descriptions from `HBSLOGDSC` and populates `lotype`/`loinfo` correctly. ✅
2.  **ssp21 — CrtLogEvent/AppErrLog per Service:** `HBSWORK.GetWorkData` now returns a full `likeds(dsVersion)` DS populated from `HBSVERSN` (via `HBSVERSNV1` view). `HBSHANDLR` extracts `CrtLogEvnt`, `AppErrLog`, `VersnActv`, and `RunAsTest` from the returned DS into module-level globals. `CallSrvc` passes `gCrtLogEvent` and `gAppErrLog` into `RtnOpts` positions 1 and 2 before calling `CallHostProgram`, allowing per-service control of logging behaviour. ✅
3.  **ssp20 — Remove HBSPATH:** `HBSHANDLR.LoadPath` cursor changed from `select * from HBSPATH` to `select hstsrvc, header from hbhsts`. The `HBSPATH` table dependency is eliminated. ✅

### Phase 2: Asynchronous & Service Architecture Implementation
1.  **Create Asynchronous Framework:** Create the persistent `HBSWRITER` job and the `HBSLOGDQ` data queue.
2.  **Offload CLOB Writes:** Refactor the application to write large JSON payloads to User Spaces and send messages to the writer job, removing the `INSERT` from the main transaction path.
3.  **Implement Writer Logic:** The `HBSWRITER` will process the queue, write data from the User Space to the database, and delete the User Space.
4.  **Implement Service Architecture:** Choose and implement one of the two service architecture options detailed in section 4.2.
5.  **Refactor Response Flow:** Ensure the final response from `HBSHANDLR` is passed back to `HBSCHILD1` via a pointer to avoid copying large memory blocks.
6.  **Create Scavenger Job:** Implement a periodic cleanup job to remove any orphaned User Spaces or other objects.
7.  **Test & Deploy:** Validate and deploy the full asynchronous, high-performance solution.

## 3. Phase 1 Implementation Notes

The following design decisions were made during Phase 1 implementation. Phase 2 must account for them.

### 3.1. GUID Strategy

Three distinct GUIDs are used per transaction:

| Field | Value | Source |
|---|---|---|
| `HBSTRANS.HTGUID` | Locally generated (`exec sql VALUES QSYS2.GENERATE_UUID() INTO :w_guid2`) | `HBSCHILD1.WriteRecv` |
| `HBSTRANS.HTRQAGUID` | JSON `ActivityId` (`w_guid`) | Parsed from inbound request |
| `HBSTRANS.HTRQPGUID` | JSON `ParentActivityId` (`w_pguid`) | Parsed from inbound request |

`HTGUID` is the primary correlation key used throughout — it is the key in `HBSREQ`, and is stored as `HSTRGUID` in `HBRESP` to provide the back-link.

### 3.2. No Foreign Key Constraints on HBSREQ or HBRESP

`HBSREQ` and `HBRESP` do **not** have FK constraints back to `HBSTRANS`. This was an intentional design decision because:

- `HBSCHILD1` inserts into `HBSTRANS` **and** `HBSREQ` together before putting the GUID on the receive data queue
- `HBSHANDLR` inserts into `HBRESP` before `HBSCHILD1` reads the response
- The strict write ordering makes FKs unenforceable without deferral

In Phase 2, when `HBSWRITER` takes over the inserts asynchronously, this ordering constraint must still be respected — the `HBSTRANS` row must exist before `HBSWRITER` attempts to insert the `HBSREQ` CLOB data.

### 3.3. Two-Phase HBSTRANS Write Pattern

`HBSTRANS` is written in two steps by two different programs:

1.  **`HBSCHILD1.WriteRecv`** — inserts the row with `HTGUID`, `HTRQAGUID`, `HTRQPGUID`, `HTTYPE`, `HTRCVSTS`, `HTSNDSTS`. Service name (`HTSNAME`) and program name (`HTPNAME`) are left as empty defaults.
2.  **`HBSHANDLR.WrtTrans`** — updates the existing row (`UPDATE ... WHERE HTGUID = r_pguid`) to fill in `HTSNAME`, `HTPNAME`, and set `HTSNDSTS`.

In Phase 2, `HBSWRITER` will take over step 1 for the CLOB body write, but the two-step ownership pattern should be preserved.

### 3.4. HBRESP Key Design (HSGUID = HTGUID)

`HBRESP` uses `HSGUID CHAR(36)` as its primary key, and this value **is the same as `HTGUID`** — the locally generated `w_guid2` from `HBSCHILD1.WriteRecv`. This means no separate back-link column is needed.

- `HBSHANDLR.WrtSend` inserts into `HBRESP` using `wReqData.r_pguid` (= `HTGUID`) as `HSGUID`
- `HBSCHILD1.ReadSQL` queries `HBRESP WHERE HSGUID = :w_guid` using `w_guid2` directly
- `HBSCHILD1.UpdtStat` updates `HBSTRANS SET HTSNDSTS WHERE HTGUID = :w_guid2` using the same key

The single GUID value serves as the correlation key through the entire chain — no intermediary `r_trguid` field or back-link column is required.

### 3.5. Files Modified in Phase 1 / Phase 1b

| File | Type | Changes |
|---|---|---|
| `HBSTRANS.SQL` | DDL | New table; `HTSNAME`/`HTPNAME` are `NOT NULL WITH DEFAULT ''` |
| `HBSREQ.SQL` | DDL | New table; no FK |
| `HBRESP.SQL` | DDL | New table; no FK; includes `HSTRGUID` |
| `HBSHANDLR.SQLRPGLE` | Program | `WrtTrans` → UPDATE; `WrtSend` → `INSERT INTO HBRESP`; `UpdtStat` → `UPDATE HBSTRANS`; all `hbstools_Actvty` → `hbstools_CrtLog` (ssp22); `LoadPath` cursor → `hbhsts` (ssp20); `GetWorkData` calls use `likeds(dsVersion)` (ssp21); globals `gCrtLogEvent`/`gAppErrLog`/`gVersionActive`/`gRunAsTest` added (ssp21); `CallSrvc` sets `RtnOpts` positions 1-2 from globals (ssp21) |
| `HBSWORK.SQLRPGLE` | Program | `GetRQWorkData`/`GetMNWorkData` → `HBSREQ JOIN HBSTRANS`; `GetSRWorkData` → `HBRESP JOIN HBSTRANS`; all proc signatures changed to `likeds(dsVersion)` (ssp21); `SrvcLst` replaced by `dsVersion extname('HBSVERSNV1')` + `ServiceList` array (ssp21); `LoadSrvcs` cursor → `select * from HBSVERSN` (ssp21); `GetHostSrvc` returns full version row (ssp21) |
| `HBSCHILD1.SQLRPGLE` | Program | `WriteRecv`/`WriteEndr` → `HBSTRANS`+`HBSREQ`; `ReadSQL` → `HBRESP`; `UpdtStat` uses `r_trguid`; `GetReqFiNum` proc restored; SQL Set Option block added |
| `HBSHS003.SQLRPGLE` | Program | Copied from member; updated to `inPtr`/`outPtr` pattern |

> **Phase 2 Prerequisite — HBSWRITER:** `HBSWRITER.RPGLE` still contains a live `INSERT INTO HBSSEND` at approximately line 156. This must be rewritten to use `HBRESP` before Phase 2 work begins, as `HBSSEND` no longer exists in the new table structure.

---

## 4. Core Architectural Changes

### 4.1. Asynchronous Logging with a Persistent Writer

To resolve I/O bottlenecks, we will implement a unified asynchronous logging mechanism.

*   **Persistent Writer Job (`HBSWRITER`):** A single, long-running RPGLE program that waits on a data queue (`HBSLOGDQ`) to receive work.
*   **In-Memory Data Transfer (User Spaces):** Large JSON payloads will be written to temporary User Space (`*USRSPC`) objects. A unique 10-character name is generated for each using a 2-character type prefix combined with the first 8 characters of `HTGUID`:
    *   `RQ` + first 8 chars of `HTGUID` — for request payloads (created by `HBSCHILD1`)
    *   `RS` + first 8 chars of `HTGUID` — for response payloads (created by `HBSHANDLR`)
    *   Example: `HTGUID` = `4c89cc10-...` → User Space names `RQ4c89cc10` / `RS4c89cc10`
    *   The User Space name is directly reconstructable from `HBSTRANS.HTGUID` at any point, making orphan detection trivial. User Spaces are created in the library identified by `d_BankLib` from the `HBSSBSCTL` data area (the same library used for all subsystem data queues), **not** in `QTEMP`, since `HBSWRITER` runs as a separate job and cannot access the creating job's `QTEMP`.

*   **UUID Source — `QSYS2.GENERATE_UUID()` (v4):** `HTGUID` is generated using `QSYS2.GENERATE_UUID()`, which produces a **version 4 (random)** UUID per RFC 4122. This replaces the prior use of `hbstools_CrtGUID()` (v1, time-based). The GUID serves as a random identity key only — sequencing is handled by the row timestamp, so there is no need for a time-ordered UUID.

    | Property | `hbstools_CrtGUID()` (v1) — old | `QSYS2.GENERATE_UUID()` (v4) — new |
    |---|---|---|
    | Algorithm | 100ns clock + MAC address | Cryptographically random |
    | First 8 chars (`time_low`) | Sequential — increments every 100ns | 32 bits of independent entropy |
    | Uniqueness guarantee | Clock-based; `time_low` wraps every **429 seconds** | Statistical — no cyclic wrap |
    | Risk for User Space names | Two transactions 429 s apart share the same `time_low`; if a prior User Space was not cleaned up, `QUSCRTUS` with `*NO` would fail | No sequential dependency |
    | One call, one value | Requires separate call for naming GUID | Single `HTGUID` value serves both `HBSTRANS` insert and User Space name |

    **Collision probability with v4 (birthday paradox + retry):**

    The first 8 hex characters represent 32 bits of randomness → 4,294,967,296 (≈ 4.3 billion) distinct values. The probability that a single new User Space name collides with one of the *n* currently live spaces is:

    $$P_\text{single}(n) = \frac{n}{2^{32}}$$

    With *k* retries (each generating a fresh UUID independently), the probability that **all** attempts fail is:

    $$P_\text{fail}(n, k) = \left(\frac{n}{2^{32}}\right)^{k+1}$$

    | Concurrent live User Spaces | No retry | After 1 retry | After 2 retries | After 3 retries |
    |---|---|---|---|---|
    | 100 | 2.3 × 10⁻⁸ | 5.4 × 10⁻¹⁶ | 1.3 × 10⁻²³ | ~0 |
    | 1,000 | 2.3 × 10⁻⁷ | 5.4 × 10⁻¹⁴ | 1.3 × 10⁻²⁰ | ~0 |
    | 10,000 | 2.3 × 10⁻⁶ | 5.4 × 10⁻¹² | 1.3 × 10⁻¹⁷ | ~0 |
    | 65,536 | 1.5 × 10⁻⁵ | 2.3 × 10⁻¹⁰ | 3.6 × 10⁻¹⁵ | 5.4 × 10⁻²⁰ |

    Even with zero retries at 1,000 concurrent spaces the chance of failure is 1 in 4.3 million. After one retry it drops to 1 in 18 trillion. Three retries renders the failure probability computationally indistinguishable from zero at all realistic BSL load levels.

*   **User Space Creation — Optimistic Retry Pattern:** `QUSCRTUS` is called with `Replace = '*NO'`. Rather than pre-checking for an existing object (which would pay an API cost on every transaction for an event that statistically never occurs), the caller uses an optimistic retry loop: attempt creation, inspect `dsApiErr.MsgId` on failure, and if `CPF9870` (object already exists) is returned, regenerate the GUID and retry up to 3 times. Any other error code is treated as a hard failure and logged. This costs nothing on the 99.99988% of calls where there is no collision, and makes the code provably correct rather than relying solely on probability.

    ```rpgle
    dow rtyCount < 3;
      exec sql VALUES QSYS2.GENERATE_UUID() INTO :w_GUID2;
      w_usName = 'RQ' + %subst(w_GUID2: 1: 8);
      clear dsApiErr;
      QUSCRTUS(w_usName + w_dtaqlib :'HBSJSON   ':bodyLen:x'00'
              :'*CHANGE   ':'HBSCHILD1 REQ payload    ':'*NO       ':dsApiErr);
      if dsApiErr.BytesAvl = 0;
        leave;                        // success
      elseif %subst(dsApiErr.MsgId:1:7) = 'CPF9870';
        rtyCount += 1;                // collision — retry with new UUID
      else;
        hbstools_CommLog(660005:'QUSCRTUS failed ' + dsApiErr.MsgId);
        return *off;
      endif;
    enddo;
    ```

*   **Communication (Data Queues):** A single, permanent Data Queue (`HBSLOGDQ`) will act as the work queue. Messages will contain the User Space name, its library, and the transaction GUID.
*   **Logging Control File (`HBSLOGCTL`):** A new configuration file will allow logging to be toggled on or off for each service.

### 4.2. Service Architecture: Two Options

To balance the need for performance with operational agility (like applying hotfixes), two distinct architectures are proposed for the service layer. The choice can be made during implementation based on final priorities.

#### Option A: Direct Program Calls (`*PGM` with `ACTGRP(*NEW)`)

This model prioritizes simplicity and operational flexibility. It is the direct replacement for the current `HBSCHPC` logic.

*   **Object Type:** Host services remain as standard `*PGM` objects.
*   **Activation Group:** Programs are compiled with `ACTGRP(*NEW)`.
*   **Execution Flow:** `HBSHANDLR` makes a standard dynamic program call to the appropriate host service program. A new activation group is created for the call and destroyed upon return.
*   **Pros:**
    *   **Live Recompiles:** A service program can be recompiled and deployed while the subsystem is active. The next call will automatically pick up the new version. This is ideal for applying hotfixes without an outage.
    *   **Simplicity:** This is a well-understood, standard IBM i programming model.
*   **Cons:**
    *   **Performance Overhead:** Every call incurs the cost of creating and destroying an activation group, along with program activation and file open/close cycles. This is less performant than Option B.

#### Option B: Procedure Pointer Cache (`*SRVPGM`)

This model prioritizes maximum performance by eliminating call overhead.

*   **Object Type:** Host services are converted to `*SRVPGM` objects, each exporting a single, consistently named procedure (e.g., `Process`).
*   **Execution Flow:**
    1.  **Caching:** On the first call to a service, `HBSHANDLR` uses the `QleActBndPgm` and `QleGetExp` APIs to get a procedure pointer to the service's `Process` procedure. This pointer is cached in a module-level array.
    2.  **Dispatch:** All subsequent calls are high-speed bound procedure calls made directly through the cached pointer.
*   **Pros:**
    *   **Maximum Performance:** Eliminates all program activation and dynamic call overhead, resulting in the fastest possible execution.
*   **Cons:**
    *   **No Live Recompiles:** Once a service program is activated and its pointer is cached, it is locked. Recompiling and deploying a new version requires clearing the cache (e.g., via a `RELOAD` command to the handler) or restarting the handler jobs.

### 4.3. Memory Management & Pointer Usage

A core tenet of this design is to minimize memory duplication. Large data payloads will be passed by reference using pointers.

*   **Asynchronous Logging Flow:** Only the 10-character User Space name (acting as a handle) is passed between jobs, not the multi-megabyte payload itself.
*   **Client Response Flow (`HBSHANDLR` -> `HBSCHILD1`):** The final response payload will be passed back to `HBSCHILD1` via a pointer to the memory buffer, avoiding a costly data copy.

## 5. Resource Management & Preventing Orphans

A key concern is preventing orphaned objects (`*USRSPC`) from accumulating.

1.  **Sequential Ownership (Primary Defense):** The process establishes a clear chain of ownership. `HBSCHILD1` creates the User Space, `HBSHANDLR` uses it, and then passes ownership to `HBSWRITER`. **The `HBSWRITER` job is the sole and final owner responsible for deleting the User Space.**
2.  **Scavenger Job (Secondary Defense):** A periodic "scavenger" job will run to find and delete any objects older than a defined Time-to-Live (e.g., 24 hours), ensuring the system remains clean.

## 6. Performance & Implementation Considerations

*   **Synchronous Status Updates:** It has been reviewed and confirmed that small, fast SQL `UPDATE` statements (e.g., for a status flag) do **not** need to be offloaded and can be performed synchronously by the main application programs.
*   **Error Handling:** The `HBSWRITER` program must have robust error handling to log any failures during the database write process.
*   **Job Queue Management:** The `HBSWRITER` job should be configured to run in an appropriate subsystem and job queue.
*   **Possible Future: System-Wide Debug Messaging Framework.** Debugging `HBSWRITER`, `HBSHANDLR`, and `HBSCHILD1` is currently difficult because detailed trace-level information is not available without code changes. A toggleable debug framework applied across all three programs would significantly improve diagnosability. Key design considerations:

    *   **Activation via Control Queue.** Each persistent job (`HBSWRITER`, `HBSHANDLR`) already has or is adjacent to a control queue. Sending `DEBUGON` or `DEBUGOFF` to that queue would toggle a `w_debug` indicator in real time — no restart or recompile required. For `HBSCHILD1`, which is request-scoped (not persistent), the debug flag could be read from a shared data area at job startup.

    *   **Where to write debug output — three options:**
        1. **`hbstools_CommLog` (current pattern).** Simplest to implement but mixes debug noise with operational logs. Not ideal if `CommLog` feeds monitoring or alerting.
        2. **Job log via `SNDPGMMSG`.** Zero schema overhead. Messages appear in `DSPJOBLOG` and are gone when the job ends. Best for transient, trace-level detail during a specific debug session.
        3. **Dedicated debug table (e.g., `HBSDEBUG`).** Higher setup cost but enables persistent, queryable debug history. First-class columns for GUID, program name, procedure, timestamp, and message text make correlation queries simple (`SELECT * FROM HBSDEBUG WHERE DBGUID = '...' ORDER BY DBTS`). Rows can be purged on a short cycle independently of operational data.

    *   **Recommended approach.** Job log for real-time trace-level output; dedicated table for anything that needs to survive the job and be queried after the fact. The two are complementary. Error-level messages remain in `CommLog` unconditionally regardless of the debug flag.

*   **Possible Future: Selective Request/Response Storage per Service.** Currently every transaction writes both a request (`HBSREQ`) and response (`HBRESP`) row unconditionally. For high-volume services where the response is only useful for diagnosis, storing successful responses is unnecessary overhead. Two new flags on `HBSVERSN` (surfaced through `HBSVERSNV1` and the existing `dsVersion` DS already returned by `HBSWORK.GetWorkData`) would control this per service:

    *   `LogReqData char(1)` — `'Y'` = always write request body to `HBSREQ`; `'N'` = skip.
    *   `LogRespData char(1)` — `'Y'` = always write; `'E'` = errors only (i.e., `Success = *off` or `ResponseDetailCollection` contains error codes); `'N'` = never write.

    **Decision point is `HBSHANDLR`**, not `HBSWRITER`. Since `HBSHANDLR` constructs the response and already knows the success/error outcome before calling `WrtSend`, it can simply skip creating the User Space and sending the DQ message when storage is not required — nothing reaches `HBSWRITER` at all for suppressed records. This keeps `HBSWRITER` simple and stateless. The `LogReqData`/`LogRespData` values are already available in `gCrtLogEvent`/`gAppErrLog` style globals once `GetWorkData` returns, requiring no additional queries.

## 7. NTQuery Service Name Enrichment

### 7.1. Background

`NTQuery` (registered as `NTQuery` in `HBSVERSN`) is a single service entry point that multiplexes many distinct query types. The actual query being executed is identified by a `QueryNum` field nested inside the JSON request body (`HeaderInfo.QueryNum`). `HBSVERSN` has one row for `NTQuery`, so `HTSNAME` in `HBSTRANS` is written as the plain service name `NTQuery` for every transaction — the specific query number is not visible in the dashboard or in any operational query against `HBSTRANS`.

`NTQuery` is not a high-volume service today, but it has the potential to become **the single largest category of inbound requests** to the BSL Subsystem as more downstream systems adopt it. When that happens, the dashboard row `NTQuery` will be meaningless for triage without knowing which query was called.

### 7.2. Existing Functionality: Query Number Resolved at Display Time in `HBSDB`

The current implementation resolves the query number **at display time** inside `HBSDB.Build_In_List`. When `service = 'NTQuery'` is detected for a row, the code performs an additional `SELECT HRBODY FROM HBSREQ WHERE HRGUID = :aguid`, parses the returned JSON CLOB via `data-into YAJLINTO`, and builds the enriched service name:

```rpgle
service = 'NTQuery' + NTQuery.HeaderInfo.QueryNum;
```

The `QueryNum` field is declared as `char(16)` (zero-padded), so `'0000000000000414'` produces `'NTQuery0000000000000414'` — however in practice only the last 3 digits are meaningful and are used for display (e.g. `'NTQuery414'`).

**This approach requires no changes to `HBSWORK`, `HBSHANDLR`, or any other program.** The cost is one synchronous CLOB read per NTQuery row on every dashboard refresh. At current volumes this is acceptable. The `24002`-tagged declarations (`mysqlclobdata`, `myclobdata`, `NtQuery` DS) and the special-case block remain in `HBSDB` to support this.

### 7.3. Future Option: Embed QueryNum in the BSL Service Return String

When NTQuery volume grows and the display-time CLOB read cost becomes a concern, the cleanest upgrade path requires **no new parameters and no changes to `HBSWORK`**. The NTQuery BSL service already returns a response string through `HBSHANDLR` via the existing call interface. The convention is:

**Reserve positions 1–3 of the NTQuery return string for the 3-digit query number suffix.** No other BSL service uses these positions for this purpose — the convention is specific to NTQuery and documented here. The NTQuery BSL service populates positions 1–3 with the last 3 digits of `QueryNum` (e.g. `'414'`) before returning.

`HBSHANDLR` then inspects the return string immediately after `CallHostProgram` returns, before calling `WrtTrans`:

```rpgle
// NTQuery returns query number suffix in return string positions 1-3
if %trim(gServiceName) = 'NTQuery'
     and %subst(ReturnString: 1: 3) <> *blanks;
  gServiceName = 'NTQuery' + %subst(ReturnString: 1: 3);
endif;
```

`WrtTrans` writes the enriched `gServiceName` into `HTSNAME` — no interface change, no additional SQL, zero compute overhead beyond what the return string handling already does.

With `HTSNAME` pre-populated as `'NTQuery414'`, `'NTQuery290'`, etc., `HBSDB.Build_In_List` reads the enriched value directly from `HBSTRANS` and the NTQuery special-case block can be removed entirely, eliminating the per-row CLOB read on every dashboard refresh.

### 7.4. `HBSVERSN` Filter Compatibility

Either approach produces the same enriched display value. The `HTSNAME like '%NTQuery%'` filter in the inbound filter screen (`HBSDBFM SF01`, field `FSERVICE`) works without change — `'NTQuery414'` matches `'%NTQuery%'`. If operators want to filter on a specific query number they can enter `NTQuery414` directly, which resolves to `HTSNAME like '%NTQuery414%'`.

### 7.5. Implementation Checklist (Future Option Only)

The existing display-time approach requires no implementation steps. The following applies only if the decision is made to move extraction to write time:

| Step | Program | Action |
|---|---|---|
| 1 | NTQuery BSL service | Populate positions 1–3 of the return string with the last 3 digits of `QueryNum` before returning to `HBSHANDLR`. Document this as a reserved convention for NTQuery. |
| 2 | `HBSHANDLR.SQLRPGLE` | After `CallHostProgram` returns, check: if service is `NTQuery` and `%subst(ReturnString:1:3) <> *blanks`, set `gServiceName = 'NTQuery' + %subst(ReturnString:1:3)`. `WrtTrans` then writes the enriched name into `HTSNAME` with no further changes. |
| 3 | `HBSDB.SQLRPGLE` | Remove the `if service = 'NTQuery'` special-case block from `Build_In_List`. Remove `mysqlclobdata`, `myclobdata`, and `NtQuery` DS declarations. Tag removals with the active change tag. |
| 4 | Smoke test | Confirm a live `NTQuery` transaction shows `NTQuery414` (or appropriate suffix) in the `HBSDB` inbound list and in `HBSTRANS.HTSNAME`. |

## 8. HBSCHILD1 Cleanup Work (April 2026)

A focused cleanup pass was performed on `HBSCHILD1.SQLRPGLE` during April 2026 to address several technical debt items identified in code review. These changes are complete and in the local codebase. The IBM i source member should be updated at next deployment.

### 8.1. SSL/TLS Code Removed

The original M02/23001 modifications added an SSL/TLS upgrade path using `hbssock_*` GSKit APIs (`hbssock_Read`, `hbssock_write`, `hbssock_CloseSession`, `hbssock_CloseHandle`). This path was controlled by `gSecurity` and `entry.Gsecurity` flags.

Since BSL no longer uses SSL/TLS for inbound connections, all conditional SSL blocks have been removed from 6 locations:
- Main `DoW` loop — SSL handle/session creation
- Post-`DoW` cleanup — `hbssock_CloseSession` / `hbssock_CloseHandle`
- `Initialization` subroutine — `entry.gsecurity` initialization
- `RecvDta` — SSL read branch (`hbssock_Read`)
- `SendDta` — SSL write branch (`hbssock_write`)
- `SendDtaErr` — SSL write branch (`hbssock_write`)

The plain `recv()` / `send()` paths are retained. Each location is marked `// We don't currently use SSL`. If SSL is needed in future, the GSKit approach should be re-evaluated against IBM i TLS socket options.

The `entry.Gsecurity` and `gSecurity` fields remain declared (they are part of the `entry` DS and global declarations respectively) but are no longer referenced in logic. They can be removed in a future cleanup if the DS layout permits.

### 8.2. Request Buffer Sizes Increased to 32K

The original buffer sizing was inconsistent and too small — `rcvbuff` was `char(4096)` but `iToGet` passed `10000` to `recv()`, creating a potential buffer overrun. `w_contlen` was `char(4)`, limiting Content-Length parsing to 4 digits (max 9999 bytes).

All buffer-related fields were updated to a consistent 32K baseline:

| Field | Before | After |
|---|---|---|
| `rcvbuff` | `char(4096)` | `char(32768)` |
| `iToGet` (init + reset) | `10000` | `32768` |
| `w_contlen` | `char(4)`, guard `> 4` | `char(5)`, guard `> 5` |
| `PrmJson` | `varchar(4000)` | `varchar(32000)` |
| `CheckHeader` `i_buffer` PI | `char(32000)` | `char(32768)` |
| `w_buffer` (CheckHeader) | `varchar(32000)` | `varchar(32768)` |

Note: `PrmJson` is intentionally 32,000 rather than 32,768 — the ~768 byte gap reserves headroom for the HTTP header that precedes the JSON body in `rcvbuff`.

Response buffers (`bigbuffer`, `bigbuffero`, `SndBuff`) remain at `varchar(2000000)` — unchanged.

### 8.3. `recvretry` Split into Two Independent Counters

`recvretry` was doing double duty — it was incremented in two unrelated retry scenarios with different thresholds, causing counter bleed-through between them.

**Scenario 1 (outer loop):** `recv()` returns 0 — counted consecutive zero-byte reads, gave up after 60 attempts (~3 seconds).  
**Scenario 2 (inner `dow morereq` loop):** partial message in buffer — counted recv attempts waiting for the rest of an incomplete message, gave up after 5 attempts (~250ms).

The counters were split:
- `recvretry` — retained for outer loop scenario 1
- `partialretry` (new `PartialRetry s 5i 0`) — used exclusively in the inner partial-receive loop

This eliminates the bleed-through where partial retries from one scenario consumed the budget for the other.

### 8.4. `result = 0` Handling Fixed — Performance Impact

**Problem:** On a non-blocking TCP socket, `recv()` returning `0` means the remote side has closed the connection (TCP graceful EOF / FIN). It does **not** mean "no data available" — that is signalled by `EWOULDBLOCK` (errno 3406, handled in the `result < 0` branch).

The original code treated `result = 0` as a retriable condition, spinning for up to 60 × 50ms = **3 seconds** before closing the connection. Since every successfully completed transaction ends with the client closing its side (result = 0 is the normal conclusion), this imposed a mandatory 3-second dead period after every request before the worker could process the next connection.

**Before:**

```rpgle
when result = 0;    // TCP graceful close or no data on non-blocking socket
  // recvretry: counts consecutive result=0 returns.
  // After 60 attempts (~3 sec), assume connection is dead and exit.
  usleep(FiftyMilliseconds);
  recvretry += 1;
  if recvretry > 60;
     recvretry = 0;
     hbstools_CommLog(600010:'Max return 0');
     Return *On;
  Endif;
  iter;            // usleep and iter X number of times
```

**After:**

```rpgle
when result = 0;    // TCP graceful close — remote side closed connection
  // result=0 means the client sent a TCP FIN (EOF). On a non-blocking
  // socket this is the definitive signal that the connection is done.
  // Exit immediately — no retry is appropriate here.
  Return *On;
```

The `recvretry` counter and associated `hbstools_CommLog(600010:...)` call are now unused by this branch and can be removed in a future cleanup. The `PartialRetry` counter reset at end-of-buffer still clears `recvretry` defensively.

**Throughput impact:** With the original code, a worker handling short-lived connections (one request per connection, typical for internal BSL) was effectively limited to ~20 requests per worker per minute. With immediate exit, the worker is available for the next connection as soon as the response is sent.

**Keep-Alive clarification:** This fix is valid regardless of whether the client uses HTTP Keep-Alive (multiple requests per connection). On a non-blocking TCP socket, the three `recv()` outcomes are mutually exclusive:

| `recv()` result | Meaning |
|---|---|
| `> 0` | Data received — *n* bytes |
| `< 0` with `errno = 3406` (`EWOULDBLOCK`) | Socket open, no data **yet** |
| `= 0` | Remote sent TCP FIN — connection **definitively closed** |

With Keep-Alive, the idle period *between* requests produces `EWOULDBLOCK` (`result < 0`), which the existing code already handles correctly — it calls `SendDta()` and loops. `result = 0` is never the "waiting for the next request" signal. It signals a TCP FIN, which occurs exactly once per connection at the very end, whether the client sent 1 request or 50 over that connection. Immediate exit is the correct response in all cases.

If BSL clients do use Keep-Alive, the per-connection throughput impact of the original bug is smaller (the 3-second penalty hit once per connection rather than once per request), but the fix is still correct and eliminates an unnecessary delay.

### 8.5. Unused Variable Cleanup

Approximately 30 module-level standalone variables were identified as dead code — declared but never referenced in any logic path. They fall into three categories:

- **Old socket/architecture remnants:** `ChildSocket10`, `ChildSocket4`, `HowManyMore`, `HBSBuffer` (and its `BufferPtr`), `ErrorCode` — left over from an earlier socket model before `ChildSocketID int(10)` was introduced.
- **SSL-era variables:** `rx`, `wwOpt`, `gSecurity` (logic removed), `gAppID`, `gEnvHndle`, `gIndx`, `gSrvrNam`, `gSsnHndle`, `gSsnType` — all tied to the GSKit SSL path removed in section 8.1.
- **Keyed data queue variables (global):** `null`, `w_dta`, `w_dtactl`, `w_keyord`, `w_keylen`, `w_keydata`, `w_sendlen`, `w_sendinf` — these were used with the legacy `QRCVDTAQ` API call (see 8.6); they were shadowed by identical local variables inside `CheckQue` and served no purpose at module level.
- **Receive-side processing:** `w_content#`, `w_reqparsed`, `r_attmpt`, `rcvbuffer`, `cnvrtrcv`, `rcvrslt`, `errcee`, `MsgSize`, `pIgnoreMsg`, `iPos`, `RCVErr`, `w_qdata2`, `w_pqlen`, `w_pqkeylen`, `w_pqkeydta`, `w_pqdata` — various accumulation counters and conversion buffers that were displaced by the current implementation but never removed.

All have been removed. `gSecurity` is still declared (it is part of the `entry` DS subfield layout) but is no longer referenced in logic.

### 8.6. `CheckQue` Refactored to SQL (`CheckKeyQue`)

`CheckQue` used the legacy `QRCVDTAQ` IBM i API to receive entries from the controller data queue, matching on a 10-character key (the job name `psjobnm`). This required a 13-parameter fixed-positional API call, an error DS, and 8 local variables — none of which provided value over the SQL equivalent.

The proc has been replaced with `CheckKeyQue`, aligned with the identical pattern already in use in `HBSHANDLR`:

**Before:** Fixed-format `P/D` proc with `QRCVDTAQ` API, 8 local variables, error DS, `opdesc` on the prototype.

**After:** Free-format `dcl-proc` with `QSYS2.RECEIVE_DATA_QUEUE` SQL table function, no local variables, `sqlstate = '02000'` handles the no-data case cleanly.

The new signature adds two explicit parameters (`p_dtaqlib`, `p_keydata`) that were previously pulled from globals implicitly, making the dependencies visible at the call site.

Both call sites updated:
- Main `DoW` loop: `CheckQue(w_dtaqctl)` → `CheckKeyQue(w_dtaqctl:w_dtaqlib:psjobnm)`
- `RecvDta` inner loop: same change

The `QRCVDTAQ` prototype (`RcvDtaqKey`) has been removed entirely.

### 8.7. `dow itoget > 0` Loop Condition Corrected

The outer receive loop in `RecvDta` was `dow itoget > 0`, but `iToGet` is reset to 32768 at the bottom of every cycle and is never set to 0 or below by any code path. The loop exited exclusively via `Leave` statements — the `dow` condition was never actually false.

Changed to `dow *on` with a comment, which matches the true intent and removes the misleading suggestion that `iToGet` drives termination.

*   **Maximum Performance:** Client response time is no longer impacted by database write or (with Option B) program call latency.
*   **Increased Throughput (TPS):** Handler and receiver jobs are freed up much faster, allowing them to process more transactions.
*   **Granular Operational Control:** Logging can be toggled for specific services without code changes or downtime.
*   **Architectural Flexibility:** The design provides a clear choice to balance performance needs against operational requirements.
*   **Guaranteed Cleanup:** The combination of sequential ownership and a scavenger job provides a multi-layered defense against orphaned system objects.

---

## 9. HBSCONTRL1 Cleanup Work (April 2026)

A focused cleanup pass was begun on `HBSCONTRL1.SQLRPGLE` during April 2026 based on a code review that identified thirteen issues (four critical, four high, five medium). See `docs/HBSCONTRL1-analysis.md` for the full inventory. The changes below are the first round applied to the local codebase. The IBM i source member should be updated at next deployment.

### 9.1. Scheduler Throttled to a Configurable Interval

**Problem (Analysis Issue #9):** `Scheduler()` was called unconditionally on every pass of the main `dow *inlr = *off` loop. The loop already runs at least every 100ms due to the `usleep(0100000)` call at the bottom. `Scheduler()` reads all `HBSFSCHED` records for the bank, performs timestamp comparisons, and issues `UPDATE` statements on every pass — resulting in potentially hundreds of thousands of unnecessary file I/O operations per day.

**Solution:** The `Scheduler()` call is now guarded by a timestamp comparison against a `LastSchedRun` module-level variable. The check interval is controlled by a named constant so it can be adjusted without touching logic.

**Changes made:**

1. Added a named constant near the existing `dcl-c` declarations:

```rpgle
dcl-c cSchedIntv const(5);    // Scheduler check interval in seconds
```

Changing this single value and recompiling adjusts the interval for the entire program. Set to `1` for once-per-second, `60` for once-per-minute, etc.

2. Added a `LastSchedRun` timestamp variable alongside the existing `rstime`/`retime` fields:

```rpgle
23001D LastSchedRun  s  z  inz(*loval)
```

Initialized to `*loval` so the scheduler runs on the very first loop iteration rather than waiting one full interval cold on startup.

3. Wrapped the `Scheduler()` call in the main loop:

**Before:**
```rpgle
23001    // check scheduler for any jobs
23001    result = Scheduler();
```

**After:**
```rpgle
23001    // check scheduler for any jobs - throttled to cSchedIntv seconds
23001    if %diff(%timestamp():LastSchedRun:*seconds) >= cSchedIntv;
23001      result = Scheduler();
23001      LastSchedRun = %timestamp();
23001    endif;
```

**Impact:** With the 100ms `usleep`, `Scheduler()` was previously called ~10 times per second, ~600 times per minute, ~864,000 times per day. At the default `cSchedIntv(5)`, it runs once every 5 seconds — approximately a **50x reduction** in `HBSFSCHED` read and update activity. The scheduler's minimum time resolution is unchanged: any job whose `BSNEXTDTE` falls within the 5-second window is still picked up on the very next check after it becomes due.

### 9.2. Multi-Port Bugs Fixed (Phase A)

**Background:** `HBSCONTRL1` already contains a multi-port architecture — arrays `rcvport(8)`, `socklist(8)`, `totrecv(8)`, and a `For I by 1 to totports` accept loop all anticipate multiple simultaneous listen sockets. However, four bugs in the `RecvJobs` procedure and supporting code prevented this from working correctly when more than one port is active. These bugs had no visible impact in production because only one port has ever been configured (`child# = 1`, `totports = 1`), making all four bugs benign in the single-port case.

A full inventory of all thirteen issues is in `docs/HBSCONTRL1-analysis.md`. The four multi-port bugs (analysis issues #1, #2, #3, #5) plus two supporting fixes (GetParms loop, EndRecv loop) were applied in this pass.

#### Why duplicate job names do not break the current single-port system

IBM i differentiates jobs by the triplet `jobname/username/jobnumber`. Even if two jobs have the same name, they are distinct system objects — `B220R/BANKUSR/111111` and `B220R/BANKUSR/111112` are unambiguous. With `child# = 1` and `totports = 1`, exactly one worker is ever named `B220R`, so there is no ambiguity.

The keyed data queue (used by `EndRecv` to signal workers) delivers **one entry per `RcvDtaqKey` call**, matched by key string. With one worker and one signal there is no race. With multiple ports or `child# > 1`, non-deterministic delivery would occur because the DQ cannot distinguish between workers that share the same key string — one port's worker could consume another port's ENDJOB signal.

#### Why the port suffix is needed (and a counter is not)

The port suffix in the job name is not for IBM i job identity (the system handles that via job number) — it is for **keyed data queue routing**. Each worker blocks on `RcvDtaqKey(..., 'EQ', 10, psjobnm, ...)` where `psjobnm` is its 10-character job name from the PSDS. `EndRecv` builds `jobn` the same way the controller set it via `argv(1)` at spawn time and sends one ENDJOB signal per worker.

Without the port suffix:
- Port 3150 → workers named `B220R`
- Port 3151 → workers named `B220R`
- `EndRecv` sends signals keyed `'B220R'` — non-deterministic which port's workers receive them

With the port suffix (`B220R3150`, `B220R3151`), signals are routed exactly to the intended group.

A **counter suffix is not needed**: `EndRecv` sends `totrecv(I)` signals keyed to the port's job name. The DQ delivers one entry per `RcvDtaqKey` call, so N workers each consume exactly one of the N signals — regardless of how many workers share the same name. IBM i job numbers handle individual job identity; the signal count handles individual delivery.

Job name sizing: `'B' + bankno(3) + 'R' + port(4)` = `B220R3150` = 9 characters, fitting within the 10-character IBM i job name limit with 1 character to spare.

#### Bug #1 — `DLTPGM` running before every spawn (Analysis issue #1)

**Problem:** Inside `For cOUNTC = 1 to CHILD#` in `RecvJobs`, a `system(qcmd)` call ran `DLTPGM PGM(LIB/WorkerName)` before each `spawnp`. This deleted the compiled program object every time a worker was spawned. The spawn itself calls the already-loaded activation group, so the delete succeeded silently — but would fail in any environment where the object is locked or the library name is wrong, and would prevent future spawns if the delete left the program in a bad state.

**Fix:** The `DLTPGM` block (3 lines: `ServerLibrary = d_sbslibl`, `Qcmd = 'DLTPGM ...'`, `system(qcmd)`) was removed entirely. `ServerLibrary = d_sbslibl` was retained immediately before the `clear path` block where it is legitimately needed for path construction.

#### Bug #2 — All spawned workers assigned identical job name (Analysis issue #2)

**Problem:** `jobn` was built as `'B' + bankno + 'R' + x'00'` — no port number. With `child# > 1` per port, or with multiple ports active, all workers would receive the same job name (e.g., `B220R`). The keyed DQ signal routing in `EndRecv` would become non-deterministic.

**Fix:** Port number appended to `jobn`:

```rpgle
// Before:
jobn = 'B' + bankno + 'R' + x'00';

// After:
jobn = 'B' + bankno + 'R' + %char(port) + x'00';
```

This produces names like `B220R3150` (9 chars) — unique per port group, routable by `EndRecv`.

#### Bug #3 — Socket array index `p` hardcoded to `1` (Analysis issue #3)

**Problem:** `p = 1` was set unconditionally at the top of `RecvJobs`. `ser(p)` and `job(p)` therefore always wrote to slot 1. When `RecvJobs` was called for ports 2, 3, etc., each call overwrote `ser(1)`, destroying the socket pair reference from the previous port. Only the last port's socket pair survived into `sendmsg`.

**Fix:** Added `portIdx` parameter to `RecvJobs` (both prototype and PI), passed `I` (the port loop index) from the call site, and replaced the hardcoded assignment:

```rpgle
// Before:
p = 1;

// After:
p = portIdx;
```

Call site change: `RecvJobs(rcvport(I):Child#)` → `RecvJobs(rcvport(I):Child#:I)`

#### Bug #5 — SSL config always sourced from `abnkports(1)` (Analysis issue #5)

**Problem:** `childParm.SSLSEC` and `childParm.APPID` were both set from `abnkports(1)` regardless of which port was being processed. With multiple ports, the SSL config from port 1 would be applied to all workers.

**Fix:** Replace the hardcoded index with `portIdx`:

```rpgle
// Before:
childParm.SSLSEC = abnkports(1).p_ssltls;
childParm.APPID  = abnkports(1).p_appid;

// After:
childParm.SSLSEC = abnkports(portIdx).p_ssltls;
childParm.APPID  = abnkports(portIdx).p_appid;
```

Note: SSL was never completed (no SSL fields exist in any HBSPARS JSON, no end-to-end path in HBSCHILD1). These stubs remain in place pending approval for removal. The index fix ensures that if SSL is ever properly implemented, it will use the correct port's configuration.

#### Supporting fix — `GetParms` hardcoded to port 1

**Problem:** The port-loading block in `GetParms` unconditionally loaded only the first port:

```rpgle
AbnkPorts(1).p_portnum = dsBankParms.Bank_Port_List(1).Bank_Port;
rcvport(1) = ABNKPORTS(1).P_PORTNUM;
totports = 1;
```

**Fix:** Replaced with a loop over `num_Bank_Port_List`, also populating the SSL fields now that `dsBankParms.Bank_Port_List` has the matching subfields:

```rpgle
for ary_p = 1 to dsBankParms.num_Bank_Port_List;
  AbnkPorts(ary_p).p_portnum = dsBankParms.Bank_Port_List(ary_p).Bank_Port;
  AbnkPorts(ary_p).p_ssltls  = dsBankParms.Bank_Port_List(ary_p).Bank_SSLTLS;
  AbnkPorts(ary_p).p_appid   = dsBankParms.Bank_Port_List(ary_p).Bank_APPID;
  rcvport(ary_p) = AbnkPorts(ary_p).p_portnum;
endfor;
totports = dsBankParms.num_Bank_Port_List;
```

Two SSL subfields were also added to `dsBankParms.Bank_Port_List` so `data-into`/`ParseJson` can populate them when the JSON is extended:

```rpgle
dcl-ds Bank_Port_List dim(10);
  Bank_Port    int(10) inz(0);
  Bank_SSLTLS  char(1)  inz('');    // added
  Bank_APPID   char(50) inz('');    // added
end-ds;
```

#### Supporting fix — `EndRecv` signaling only port-1 workers

**Problem:** `EndRecv` built `jobn` as `'B' + bankno + 'R'` (no port) and looped `For I by 1 to totrecv(1)` — signaling only the count for port 1, with a key that would match any worker regardless of port.

**Fix:** Outer loop over all ports, `jobn` rebuilt per port, inner loop over that port's worker count:

```rpgle
// Before:
jobn = 'B' + bankno + 'R';
For I by 1 to totrecv(1);
  SndDtaqkey(w_dtaqnm:W_DTAQLIB:w_len:wCtrlReq:w_keylen:jobn);
Endfor;

// After:
For I by 1 to totports;
  jobn = 'B' + bankno + 'R' + %char(rcvport(I));
  For cOUNTC = 1 to totrecv(I);
    SndDtaqkey(w_dtaqnm:W_DTAQLIB:w_len:wCtrlReq:w_keylen:jobn);
  Endfor;
Endfor;
```

`EndController`'s guard also updated from `iF TotRecv(1) > 0` to `iF totports > 0` — `EndRecv` handles empty-port cases internally via the inner loop.

#### Summary of changes applied

| Location | Change |
|---|---|
| `dsBankParms.Bank_Port_List` DS | Added `Bank_SSLTLS char(1)` and `Bank_APPID char(50)` subfields |
| `GetParms` port assignment block | Replaced hardcoded `AbnkPorts(1)`/`rcvport(1)`/`totports=1` with `for ary_p` loop |
| `RecvJobs` prototype | Added `PortIdx packed(3)` parameter |
| `RecvJobs` PI | Added `portIdx packed(3:0)` parameter |
| Main loop call site | `RecvJobs(rcvport(I):Child#)` → `RecvJobs(rcvport(I):Child#:I)` |
| `RecvJobs` body — `jobn` | Appended `%char(port)` — e.g. `B220R3150` |
| `RecvJobs` body — `p` | `p = 1` → `p = portIdx` |
| `RecvJobs` body — SSL index | `abnkports(1)` → `abnkports(portIdx)` (both assignments) |
| `RecvJobs` body — DLTPGM | Block removed |
| `EndRecv` | Outer port loop + per-port `jobn` + inner `totrecv(I)` loop |
| `EndController` | `TotRecv(1) > 0` guard → `totports > 0` |

### 9.3. Multi-Port Benefit Proposal — Port-Based Service Routing

With multi-port now structurally supported, a natural next step is to use the port of origin to **restrict which services are reachable on which port**. This enables scenarios such as:

- Port 3150 — internal services only (corporate network, no authentication required)
- Port 3151 — external/partner services only (DMZ-facing, stricter validation)
- Port 3152 — a new service group activated for a specific integration without touching existing port configuration

All of this would be configuration-driven — no code changes per deployment, just updates to a config table.

#### The routing problem

By the time `HBSCONTRL1` accepts a connection on a given listen socket, it only knows the **port** — not the **service name**. The service name is inside the HTTP request body, which `HBSCHILD1` parses. The controller cannot filter by service; it can only tag the connection with its port of origin. The routing decision has to flow downstream.

#### Proposed design: tag → store → filter

**Step 1 — Controller tags the connection with the port (`HBSCONTRL1`)**

Add `portnum` to the `childParm` DS so the spawned worker receives it:

```rpgle
// childParm DS — add one field:
dcl-ds childParm qualified;
  id      char(10);
  SSLSEC  char(1);
  APPID   char(50);
  portnum packed(5);     // new — port the connection arrived on
  null    char(1) inz(x'00');
end-ds;

// In RecvJobs — populate before spawn:
childParm.portnum = port;
```

**Step 2 — HBSCHILD1 stores the port in the transaction (`HBSTRANS`)**

Add a `HTPORT DECIMAL(5,0) NOT NULL WITH DEFAULT 0` column to `HBSTRANS`. `WriteRecv` reads `childParm.portnum` from the passed parm DS and includes it in the INSERT. No logic change — just one additional column.

**Step 3 — HBSHANDLR validates service vs. port (`HBSVERSN` config)**

Add a `SVCPORT DECIMAL(5,0) NOT NULL WITH DEFAULT 0` column to `HBSVERSN` (and `HBSVERSNV1`). Convention: `0` = accept on any port (default, preserves all existing behavior).

When `GetWorkData` loads the service record, the existing `dsVersion` DS (already returned to `HBSHANDLR`) would carry `SVCPORT`. A single check in `HBSHANDLR` before dispatching to the host program:

```rpgle
if dsVersion.SvcPort > 0
   and dsVersion.SvcPort <> r_htport;   // r_htport from HBSTRANS
  // return error response — service not available on this port
  return;
endif;
```

Because the service record is already loaded by `HBSWORK.GetWorkData` and `HTPORT` is already in `HBSTRANS` (read by `HBSWORK` as part of the join), no additional queries are needed.

#### Why not filter earlier in HBSCHILD1?

HBSCHILD1 does parse the service name from the URL and could theoretically check `HBSVERSN`. However, that lookup is already done by `HBSWORK.GetWorkData` inside HBSHANDLR. Duplicating it in HBSCHILD1 would add coupling between two programs that are intentionally decoupled. HBSHANDLR is the right place because the config record is already in hand there — the port check is a single `if` against data already loaded.

#### Config table options

| Approach | Pros | Cons |
|---|---|---|
| `SVCPORT` column on `HBSVERSN` | Simple — one column, already loaded by `GetWorkData`, no extra join | One allowed port per service only |
| New `HBSSVCPORT` cross-ref table (`SVCNAME`, `PORT`) | Multiple allowed ports per service | Extra join in `GetWorkData`; more DDL |

For the typical use case — each service is pinned to one port — the single column is sufficient. The cross-ref table is worth implementing only if services need to be reachable on multiple distinct ports simultaneously.

#### What this enables

```
Port 3150 → HBSCHILD1 stores HTPORT=3150
            HBSHANDLR checks SVCPORT → only services with SVCPORT=3150 (or 0) execute

Port 3151 → HBSCHILD1 stores HTPORT=3151
            HBSHANDLR checks SVCPORT → only services with SVCPORT=3151 (or 0) execute

SVCPORT=0  → service accepts connections on any port (default, no behavior change)
```

The end result is port-based service partitioning that is entirely config-driven: set `HBSVERSN.SVCPORT` for a service and it is immediately restricted to that port on next request, with no code change or subsystem restart required.

#### Client awareness implications

Port-based service routing has a direct impact on calling systems, and the intended use case should determine which model is adopted before implementation.

**Model A — Client-directed routing:** The calling system explicitly targets a specific port per service. The client must know (and be configured with) the correct port for each service name it calls. This works well when the caller list is small and controlled — each integration maps its service calls to the appropriate port in its own configuration:

```
GETACCTKN → host:3150
JWTGEN    → host:3151
```

Any misconfiguration on the client side results in an error at the HBSHANDLR port check. This is transparent to debug but requires coordination with every calling system when port assignments change.

**Model B — Operational isolation boundary (recommended for BSL):** A single external-facing port (e.g., 3150) handles all client traffic, as today. Additional ports are opened for **different caller classes** — not different service names. For example:

- Port 3150 — standard client requests (all existing integrations, unchanged)
- Port 3151 — batch or administrative traffic from the same server (background jobs, scheduler-submitted calls)
- Port 3152 — a new integration group activated without touching the existing port configuration

In this model, external clients never need to know about port 3151 or 3152 — those are internal operational boundaries. The service restriction becomes: *"only these service names are valid for connections arriving from this network path"* rather than a routing hint that clients must navigate. No client reconfiguration is required when adding a new port.

**Recommendation:** Design the feature for Model B. Use port separation as a **caller-class isolation mechanism** rather than a per-service routing table. The `SVCPORT=0` default ensures zero impact on existing behavior, and new ports can be introduced incrementally without coordinating changes with calling systems.

#### Implementation scope (when approved)

| Object | Change |
|---|---|
| `HBSTRANS` DDL | Add `HTPORT DECIMAL(5,0) NOT NULL WITH DEFAULT 0` |
| `HBSVERSN` DDL | Add `SVCPORT DECIMAL(5,0) NOT NULL WITH DEFAULT 0` |
| `HBSVERSNV1` view | Include `SVCPORT` in select |
| `childParm` DS (`HBSCONTRL1`) | Add `portnum packed(5)` field |
| `RecvJobs` (`HBSCONTRL1`) | Set `childParm.portnum = port` before spawn |
| `HBSCHILD1.WriteRecv` | Read `entry.portnum` from parm; include `HTPORT` in INSERT |
| `dsVersion` DS (`HBSWORK`) | Add `SvcPort packed(5)` subfield matching `HBSVERSNV1` |
| `HBSHANDLR` dispatch path | Add port check before calling host program |

### 9.4. Free-Format Conversion (P-spec → dcl-proc/end-proc)

**Background:** `HBSCONTRL1.SQLRPGLE` was written in mixed fixed/free format — control options and some declarations were already in free-format, but all procedure definitions still used the fixed-format `P … B` / `P … E` (P-spec) boundaries and `D … PI` / `D … DS` / `D … S` specs for their parameters and local variables. This pass converted all procedure definitions to fully free-format `dcl-proc`/`end-proc`.

**Scope:** All 13 internal procedure definitions were converted. The fixed-format global `D`-spec declarations and forward `D … pr` prototype blocks were left in place — they compile correctly in mixed-format mode and will be addressed in a subsequent pass.

#### Procedures converted

| Procedure | Notes |
|---|---|
| `RecvJobs` | `dcl-pi` with `port packed(5)`, `child# packed(3)`, `portIdx packed(3)` |
| `CrtListen` | `dcl-pi *n int(10) end-pi;` (no parameters) |
| `CrtListenP` | `dcl-pi` with `port packed(5)` |
| `errcheck` | `dcl-pi` with `result int(10)` |
| `Scheduler` | `dcl-pi *n int(10) end-pi;` (no parameters) |
| `cleanup` | `dcl-pi` with `info pointer` |
| `SbmHandler` | `dcl-pi` with `worker# packed(3)` |
| `SbmPush` | `dcl-pi` with `worker# packed(3)` |
| `CheckQue` | `dcl-pi` with `p_dtaqnm char(10) const`; local variables converted to `dcl-s`/`dcl-ds`; `w_ErrDS` subfields use `pos()` |
| `EndPush` | `dcl-pi *n int(10) end-pi;`; local `dcl-s` declarations retained |
| `EndHandler` | `dcl-pi *n int(10) end-pi;`; local `dcl-s` declarations retained |
| `EndRecv` | `dcl-pi *n int(10) end-pi;`; local `dcl-s` declarations retained |
| `EndController` | `dcl-pi *n int(10) end-pi;` |
| `CheckCldr`, `GetParms`, `ParseJSON`, `WrtDtaq` | Already `dcl-proc`/`end-proc` before this session |

#### `eval` keyword removed

The obsolete `eval` keyword was removed from two procedures where it had survived from older code:

- `SbmHandler` — two instances of `eval` on assignment statements
- `SbmPush` — one instance
- `RecvJobs` — one remaining instance (`eval countc3 = %char(pcount)`) was identified but left in place; it is harmless and can be removed in a subsequent pass

#### `CEERTX` prototype fixed for free-format

The `CEERTX` condition handler prototype was originally written in mixed fixed/free format using bare fixed-format type specs inside a `dcl-pr` block. This caused a compile error when the rest of the file was converted. The prototype was rewritten as proper free-format:

**Before:**
```rpgle
dcl-pr CEERTX extproc('CEERTX');
  exitProc  *   procptr const;
  userToken 12   options(*omit);
  fc        12   options(*omit);
end-pr;
```

**After:**
```rpgle
dcl-pr CEERTX extproc('CEERTX');
  exitProc  pointer(*proc) const;
  userToken char(12) options(*omit);
  fc        char(12) options(*omit);
end-pr;
```

#### `PortIdx` forward prototype spacing fixed

The fixed-format forward prototype for `RecvJobs` had an extra space before the `3  0` length/decimal specification for the `PortIdx` parameter, placing it one column to the right of the expected position. This caused a compile error. One space was removed to restore correct column alignment.

#### `LastSchedRun` D-spec column alignment fixed

The `LastSchedRun` standalone field declaration had a column alignment issue — the type designator `z` was shifted one column to the right of its expected position, causing a compile error. This was corrected manually and the file compiled clean.

#### Remaining fixed-format work (not yet converted)

| Item | Status |
|---|---|
| Forward `D … pr` prototype blocks (~lines 47–180) | Not converted — compiles fine in mixed-format; lower priority |
| Global `D`-spec standalone fields and data structures | Not converted — compiles fine in mixed-format |
| `eval` in `RecvJobs` body | Not removed — harmless |

---

### 9.5. Proposed: Drain Full Backlog on Each Accept Poll (High-Volume Connection Handling)

**Status:** Not yet implemented — proposed change for next pass.

**Background:** The main loop currently calls `accept()` exactly once per port per iteration, then sleeps 100 ms (`usleep(0100000)`). With a single bank and low connection volume this is adequate. However, at higher volumes — for example 50 client servers connecting simultaneously — this means the kernel's listen backlog drains at only one connection per 100 ms per port, serializing acceptance of a burst that the kernel already has fully queued. At 100 ms/connection a burst of 50 connections takes ~5 seconds to drain; at 10 ms it would still take ~500 ms.

**Root cause:** The loop structure accepts at most one connection before sleeping:

```rpgle
For I by 1 to totports;
  if rcvport(I) <> 99999;
    sockAccept = accept(sockList(I): %addr(sockaddrin): LenSckAdIn);
    ErrCheck(sockaccept);
    If sockaccept > 0;
      RecvJobs(rcvport(I): Child#: I);
      result = close(sockaccept);
    endif;
  endif;
Endfor;
usleep(0100000);
```

**Proposed change:** Because all listen sockets are already set `O_NONBLOCK` by `CrtListen` (via `fcntl(socklist(I): F_SETFL: O_NONBLOCK)`), `accept()` returns immediately with -1 when the backlog is empty. This makes it safe to drain all pending connections in a tight inner loop with no risk of blocking:

```rpgle
For I by 1 to totports;
  if rcvport(I) <> 99999;
    // Drain all pending connections on this port before sleeping
    dow;
      sockAccept = accept(sockList(I): %addr(sockaddrin): LenSckAdIn);
      if sockAccept < 0;      // EWOULDBLOCK — backlog empty, stop draining
        leave;
      endif;
      RecvJobs(rcvport(I): Child#: I);
      result = close(sockaccept);
    enddo;
  endif;
Endfor;
usleep(0100000);
```

**Effect:**
- A burst of N connections on a port is fully drained in a single pass through the outer `For` loop rather than over N loop iterations × 100 ms each.
- When the backlog is empty (the normal idle case), the first `accept()` returns -1 immediately, the `dow` exits, and the loop proceeds exactly as before — no performance regression.
- The `usleep` value becomes purely a CPU throttle and DQ/scheduler poll rate again, decoupled from connection accept latency.

**Note on `RecvJobs` internal `usleep`:** The `usleep(0100000)` inside `RecvJobs` (before the `sendmsg` loop) serves a different purpose — it gives the freshly spawned `HBSCHILD1` jobs time to be scheduled before the parent sends the socket descriptor via `sendmsg`. That sleep should not be removed as part of this change.

**Risk:** Low. The sockets are already `O_NONBLOCK`; the `accept()` return value of -1 on an empty backlog is the documented POSIX behavior. The only new code path is the `dow`/`leave` wrapper; the inner logic is identical to today's.

> **⚠️ HOLD — Memory pressure interaction:** An investigation into recurring `spawnp()` failures (commlog 600008, occurring every 2-3 weeks in production) revealed the server pool is running at approximately 32 page faults/sec at baseline. The drain loop would change burst acceptance from ~1 connection per 100 ms to all pending connections in a single pass, potentially causing all 50+ spawns to fire simultaneously during a connection burst. Under memory pressure, this could make the spawn failure condition significantly worse rather than better.
>
> **Key finding (April 2026):** The production machine experiencing spawn failures runs the BSL subsystem in a **shared pool** alongside other processes. The dev machine — which has never experienced spawn failures — runs in a **dedicated pool**. This is strong evidence that pool memory/activity-level contention is the root cause of the failures, making the memory pressure concern above highly credible. The long-term fix is likely to move BSL to its own dedicated pool (or increase the shared pool size/activity level), not to change the accept/spawn loop structure.
>
> **Further evidence — 660001 log analysis (April 2026):** Comparing `HBSCHILD1` end-of-job commlog entries (code 660001) between the two systems reveals a structural difference, not just a traffic volume difference:
>
> *Healthy system (dedicated pool):*
> - Child jobs live several minutes, handling 18–130 requests each before ending
> - Connection reuse is working as designed — the `HBSCHILD1` loop serves many requests per connection
> - A small number of long-lived workers serve the full traffic volume
>
> *Problematic system (shared pool):*
> - Almost every child job handles **exactly 1 request** then ends
> - Job lifetimes are almost exactly **65 seconds** with striking consistency (e.g., 07:15:47→07:16:52, 07:17:17→07:18:22, 07:20:45→07:21:50, 07:25:46→07:26:51)
> - This 65-second boundary is a **client-side connection timeout** — the client sends one request, waits 65 seconds for a response that doesn't arrive in time, disconnects, then immediately reconnects
>
> *The compounding cycle this creates:*
> 1. Shared pool memory pressure → handler is slow → response takes longer than 65 seconds
> 2. Client times out → disconnects → immediately reconnects
> 3. Controller spawns a new `HBSCHILD1` for the reconnect → more concurrent jobs
> 4. More concurrent jobs → more memory pressure → responses even slower
> 5. More timeouts → more reconnects → more spawns → the flurry of 600008 spawn failures
>
> The actual request volume on both systems may be identical. The problematic system is spawning far more jobs to serve the same traffic because connections are not being reused. That amplified spawn rate, concentrated during busy periods, is what drives the periodic spawn failure flurries. **Fixing pool isolation breaks this cycle at its root** — fast responses mean clients never hit the 65-second timeout, connections stay open and reused, and the spawn rate returns to normal.
>
> **Decision gate:** Do not implement this change until the POSIX errno from the spawn failure is confirmed from the commlog (errno is now being logged as of change 26002). If the errno is `12` (ENOMEM — memory pressure), the drain loop must **not** be implemented without first resolving the pool isolation issue. If the errno is `11` (EAGAIN — job limit) or `1` (EPERM — authority), the memory pressure concern does not apply and the drain loop can be reconsidered independently.

#### Path forward: drain loop + dedicated pool + software ceiling guard

Once BSL is moved to a dedicated pool, the drain loop becomes viable — but it should be paired with a **software ceiling guard** rather than relying on `MAXACTJOBS` or any OS-level job limit as a throttle. Here is why, and how each option behaves:

**Option A — Lower `MAXACTJOBS` to throttle bursts:** Does **not** throttle gracefully. By the time `spawnp()` fails due to a job limit, `accept()` has already pulled the connection out of the kernel backlog. The worker is never created, the socket gets closed with no response, and the client sees silence or an RST. Connections are dropped, not queued.

**Option B — Leave the kernel backlog as the natural queue (recommended):** The listen socket backlog (currently 512) holds connections harmlessly at the TCP layer. The client's stack waits — nothing is dropped and nothing times out quickly. Connections only fail if they sit in the backlog long enough to hit the client's own connect timeout (typically minutes). The correct approach is to leave connections in the backlog when the system is under load, and `accept()` them only when capacity is available.

**Software ceiling guard — the right throttle mechanism:** Before calling `accept()` inside the drain loop, check whether `totrecv(I)` is at or near a configured maximum active worker count. If at the ceiling, skip `accept()` for this iteration — the connection stays safely in the kernel backlog. When a worker finishes and sends the `40001` command that decrements `totrecv`, the next loop iteration resumes acceptance. Nothing is ever dropped; clients simply wait.

```rpgle
dcl-c MAX_WORKERS_PER_PORT const(40);   // tune to pool size / ACTLVL

For I by 1 to totports;
  if rcvport(I) <> 99999;
    dow totrecv(I) < MAX_WORKERS_PER_PORT;
      sockAccept = accept(sockList(I): %addr(sockaddrin): LenSckAdIn);
      if sockAccept < 0;      // EWOULDBLOCK — backlog empty, stop draining
        leave;
      endif;
      RecvJobs(rcvport(I): Child#: I);
      result = close(sockaccept);
    enddo;
  endif;
Endfor;
usleep(0100000);
```

**`ACTLVL` sizing:** The pool's activity level must be set high enough to support the maximum concurrent worker jobs across all ports plus the controller, handler, and push jobs. Undersizing `ACTLVL` causes page faults and ineligible-thread waits even when memory is sufficient; it is a separate tuning parameter from pool memory size. Both must be sized correctly for the drain loop + ceiling guard to work as intended.

---

### 9.7. Investigation: Connection Reuse — OCI Load Balancer 65-Second Idle Timeout

**Status:** Root cause confirmed — no BSL code change required. Fix is an OCI infrastructure configuration change.

**Background:** Analysis of `HBSCHILD1` end-of-job commlog entries (660001) revealed a stark difference between a healthy system (dedicated pool) and a problematic system (shared pool):

- Healthy system: child jobs handle 18–130 requests per connection, living several minutes
- Problematic system: nearly every child job handles exactly **1 request** and ends after exactly **65 seconds**

Initially the 65-second pattern was attributed to slow responses caused by shared pool memory pressure. However, comparing logs from a quiet period on the problematic system showed the same 1-request/65-second pattern at low load — ruling out memory pressure as the cause of the connection churn.

**Analysis of request headers:**

Comparing HTTP request headers between the two systems revealed two smoking guns:

1. **Host header format:** The problematic system shows `Host: 10-90-85-131_3121_8896` — a raw IP address with dashes plus port and FI number. This naming convention is used internally by **Oracle Cloud Infrastructure (OCI)** load balancers and OKE orchestration layers to identify backend targets.

2. **The 65-second value:** OCI Load Balancer documentation explicitly states that the keep-alive idle timeout for backend connections is hardcoded to **65 seconds**. After 65 seconds of inactivity on a backend connection, OCI closes it from the load balancer side.

**Confirmed root cause:** The problematic system's traffic passes through an **OCI Load Balancer**. OCI closes the backend TCP connection to BSL after 65 seconds of idle time by design. `HBSCHILD1` correctly detects the TCP close (`recv()` returns 0), exits `RecvDta`, and ends the job. OCI then opens a fresh connection for the next request, triggering a new `spawnp()` in the controller.

This is not a BSL bug. Adding `Connection: keep-alive` to the BSL response headers would have no effect — OCI's load balancer closes the backend connection regardless of HTTP headers.

The healthy system connects via `upstream12_9498` — a logical hostname consistent with a non-OCI proxy or a differently configured OCI backend socket pool that maintains persistent connections to BSL.

**Impact on spawn rate:** Because OCI reconnects for every request (or after every 65s idle), the spawn rate on the problematic system is permanently elevated compared to a system with persistent connections. Under load this amplifies pool pressure and drives the 600008 spawn failure flurries.

**Fix options:**

1. **OCI backend connection reuse (preferred):** OCI Load Balancer backend sets support persistent connection pooling. Configuring the OCI backend set to maintain a pool of persistent connections to BSL would eliminate the per-request reconnect entirely. This is an OCI infrastructure configuration change — no BSL code change required.

2. **Pool isolation (still required):** Even with OCI connection pooling configured, moving BSL to a dedicated pool eliminates the shared pool contention. Both fixes address different layers of the problem.

3. **Software ceiling guard (future):** Once pool isolation is in place and the spawn rate is understood, the ceiling guard in Section 9.5 provides an additional safety layer.

**Corroborating evidence — HBSTRANS request log vs. 660001 commlog correlation (April 22, 2026):**

A small sample was cross-referenced between incoming request timestamps (from HBSTRANS) and `HBSCHILD1` end-of-job commlog entries (660001) to confirm the OCI idle timeout mechanism directly. The sample covered the window 16:37:05–16:38:07 and contained 8 `GetAccounts` requests arriving in pairs roughly 20 seconds apart.

Four child jobs ended during this window:

| Job started | Job ended | Total Recv | Requests handled |
|-------------|-----------|------------|-----------------|
| 16:37:05 | 16:38:30 | 2 | `0D1AE018` (16:37:05) + `1C797018` (16:37:06) — 85s lifetime |
| 16:37:06 | 16:38:53 | 2 | Second 16:37:06 request + overlap — 107s lifetime |
| 16:37:26 | 16:38:31 | 1 | One of the `121B` pair — 65s idle timeout fired |
| 16:37:51 | 16:39:12 | 3 | `CAF7B018` (16:37:51) + `A573E018` (16:37:49) + `121D` pair member (16:38:07) — 81s lifetime |

The correlation confirms the mechanism: when requests arrive within 65 seconds of each other on the same OCI backend connection, OCI reuses the connection and TotRecv climbs above 1. When there is a gap longer than 65 seconds, OCI closes the backend connection and a new `HBSCHILD1` job is spawned for the next request. The 1-request/65-second jobs are not failures — they are OCI behaving exactly as documented.

This is the first time HBSTRANS request timestamps and 660001 commlog entries have been correlated directly. The sample size is sufficient to confirm the mechanism; a larger dataset would add statistical weight but would not change the conclusion.

**Note:** A `Connection: keep-alive` header was briefly added to `BldHeader` during this investigation and then reverted once the OCI root cause was confirmed. No code change to `HBSCHILD1` is needed for this issue.

---

### 9.8. Proposed: BSL Subsystem Statistics Collection (HBSSTATS)

**Status:** Not yet implemented — proposed for next pass after OCI and pool isolation work is complete.

**Background:** Current instrumentation relies on `HBSCOMLOG` text entries which cannot be easily queried, trended, or visualized. A dedicated statistics table would allow SQL-based analysis of active worker counts, spawn failure rates, handler queue depth, and connection reuse health — both during investigations and as ongoing operational monitoring.

#### Table definition

```sql
CREATE TABLE HBSSTATS (
  STAT_TIME    TIMESTAMP     NOT NULL,
  STAT_TYPE    CHAR(10)      NOT NULL,
  PORT         INT           NOT NULL,
  ACTIVE_WRKS  INT           NOT NULL,
  SPAWN_FAIL   INT           NOT NULL,
  TOTAL_SPAWN  INT           NOT NULL,
  HDLR_QLEN    INT           NOT NULL,
  CTRL_UPTIME  INT           NOT NULL
);

CREATE INDEX HBSSTATS1 ON HBSSTATS (STAT_TIME);
CREATE INDEX HBSSTATS2 ON HBSSTATS (STAT_TYPE, PORT, STAT_TIME);
```

| Column | Type | Description |
|--------|------|-------------|
| `STAT_TIME` | TIMESTAMP | When the snapshot was taken |
| `STAT_TYPE` | CHAR(10) | `'CTRLSNAP'` — controller periodic snapshot; `'SPAWNFAIL'` — logged on each spawn failure |
| `PORT` | INT | Port number (from `rcvport(I)`); 0 for controller-level entries |
| `ACTIVE_WRKS` | INT | `totrecv(I)` — active child jobs on this port at snap time |
| `SPAWN_FAIL` | INT | Cumulative spawn failures since controller started |
| `TOTAL_SPAWN` | INT | Cumulative successful spawns since controller started |
| `HDLR_QLEN` | INT | Handler dataq depth at snap time (entries waiting to be processed) |
| `CTRL_UPTIME` | INT | Seconds since controller job started |

All numeric columns are `INT` (4-byte binary integer) — optimal for `MAX()`, `AVG()`, `GROUP BY` aggregation queries without packed decimal conversion overhead.

#### Control DQ commands: STATSON / STATSOFF

Stats collection is controlled via the existing control dataq mechanism in `HandleCtrlCmd`. Two new commands toggle collection on and off without restarting the controller:

- `STATSON` — enables periodic snapshot inserts to `HBSSTATS` (interval: every 60 seconds per port)
- `STATSOFF` — disables inserts; controller continues running normally with no stats overhead

A module-level `dcl-s w_statsOn ind inz(*off)` flag gates all insert activity. Stats are off by default — enable only when investigating a problem or baselining after a configuration change.

#### Useful queries

```sql
-- Peak and average active workers by port, by day
SELECT PORT, DATE(STAT_TIME) AS SNAP_DATE,
       MAX(ACTIVE_WRKS) AS PEAK_WORKERS,
       INT(AVG(ACTIVE_WRKS)) AS AVG_WORKERS
FROM HBSSTATS
WHERE STAT_TYPE = 'CTRLSNAP'
GROUP BY PORT, DATE(STAT_TIME)
ORDER BY SNAP_DATE DESC, PORT;

-- Spawn failure rate over time
SELECT DATE(STAT_TIME) AS SNAP_DATE, PORT,
       MAX(SPAWN_FAIL) - MIN(SPAWN_FAIL) AS FAILURES_THIS_DAY
FROM HBSSTATS
WHERE STAT_TYPE = 'CTRLSNAP'
GROUP BY DATE(STAT_TIME), PORT
ORDER BY SNAP_DATE DESC;

-- Handler queue depth trend — are handlers keeping up?
SELECT STAT_TIME, PORT, HDLR_QLEN
FROM HBSSTATS
WHERE STAT_TYPE = 'CTRLSNAP'
  AND HDLR_QLEN > 0
ORDER BY STAT_TIME DESC;
```

#### Baseline opportunity

Enable `STATSON` immediately after the OCI backend timeout is raised to capture the before/after comparison for active worker count and spawn failure rate. This will provide concrete evidence of the improvement for stakeholders.

#### Implementation notes

**New module-level fields in `HBSCONTRL1`** (always accumulate regardless of stats on/off, so no history is lost if stats are enabled mid-run):

```rpgle
dcl-s w_statsOn     ind   inz(*off);   // toggled by STATSON/STATSOFF
dcl-s w_spawnFail   int(10) inz(0);    // cumulative spawn failures since start
dcl-s w_totalSpawn  int(10) inz(0);    // cumulative successful spawns since start
dcl-s w_uptimeSecs  int(10) inz(0);    // seconds since controller started
dcl-s LastStatSnap  timestamp inz(*loval);
dcl-s w_ctrlStart   timestamp;         // set in *inzsr
```

**In `HandleCtrlCmd`** — add alongside existing `ENDJOB` handling:

```rpgle
when w_dta30 = 'STATSON';
  w_statsOn = *on;
  hbstools_CommLog(600000:'BSL Stats collection enabled');

when w_dta30 = 'STATSOFF';
  w_statsOn = *off;
  hbstools_CommLog(600000:'BSL Stats collection disabled');
```

**Periodic snapshot** — add after `HandleCtrlCmd()` call in main loop, throttled to 60-second intervals. The `w_statsOn` flag gates the insert; counter updates happen unconditionally:

```rpgle
w_uptimeSecs = %diff(%timestamp():w_ctrlStart:*seconds);
if w_statsOn and %diff(%timestamp():LastStatSnap:*seconds) >= 60;
  For I by 1 to totports;
    exec sql
      insert into HBSSTATS
        (STAT_TIME, STAT_TYPE, PORT, ACTIVE_WRKS,
         SPAWN_FAIL, TOTAL_SPAWN, HDLR_QLEN, CTRL_UPTIME)
      values
        (%timestamp(), 'CTRLSNAP', :rcvport(I), :totrecv(I),
         :w_spawnFail, :w_totalSpawn, 0, :w_uptimeSecs);
  Endfor;
  LastStatSnap = %timestamp();
endif;
```

**On spawn failure** — increment counters unconditionally; insert only when stats on:

```rpgle
if pid2 < 0;
  hbstools_CommLog(600008:'Error in spawn');
  hbstools_CommLog(600008:'Spawn Error Number' + %char(errno));
  w_spawnFail += 1;
  if w_statsOn;
    exec sql
      insert into HBSSTATS
        (STAT_TIME, STAT_TYPE, PORT, ACTIVE_WRKS,
         SPAWN_FAIL, TOTAL_SPAWN, HDLR_QLEN, CTRL_UPTIME)
      values
        (%timestamp(), 'SPAWNFAIL', :rcvport(I), :totrecv(I),
         :w_spawnFail, :w_totalSpawn, 0, :w_uptimeSecs);
  endif;
Else;
  totrecv(I) += 1;
  w_totalSpawn += 1;
Endif;
```

**Note on `HDLR_QLEN`:** Handler queue depth requires a `QSNDDTAQ`/`QRCVDTAQ` query call to retrieve the current entry count — this is a future enhancement. Set to 0 in the initial implementation.

#### Configuration tuning methodology

`HBSSTATS` is designed to be the tuning instrument for BSL configuration decisions. Currently every configuration value (handler count, pool size, activity level) is set by estimate. After the OCI fix is deployed, enable `STATSON` and collect at least one week of data covering both peak and off-peak periods before adjusting anything. Then use the following decision table:

**Handler count tuning (`d_hand#`):**

| `HDLR_QLEN` pattern | Interpretation | Action |
|---------------------|---------------|--------|
| Consistently 0 at all times | Handlers always idle — over-provisioned | Reduce handler count by 25%, recheck after one week |
| Occasionally spikes then drains quickly | Handlers absorbing bursts correctly | No change needed |
| Grows and stays elevated | Handlers falling behind sustained load | Increase handler count |

A queue depth of 0 at all times is not the goal — it means handlers are sitting idle consuming pool activity level slots unnecessarily. A small queue (1–3 entries) that drains within seconds is healthy and means handler count is correctly matched to throughput.

**Worker ceiling guard (`MAX_WORKERS_PER_PORT`):**

Query peak `ACTIVE_WRKS` over a representative week:

```sql
SELECT PORT, MAX(ACTIVE_WRKS) AS PEAK, INT(AVG(ACTIVE_WRKS)) AS AVG_WORKERS
FROM HBSSTATS
WHERE STAT_TYPE = 'CTRLSNAP'
GROUP BY PORT;
```

Set `MAX_WORKERS_PER_PORT` to 1.5× the observed peak — enough headroom for burst spikes without allowing unbounded growth.

**Pool size tuning:**

Once `MAX_WORKERS_PER_PORT` is established, pool memory sizing becomes straightforward:

```
Required pool memory = MAX_WORKERS_PER_PORT × ports × ~3MB per job
                     + handler jobs × ~3MB
                     + push jobs × ~3MB
                     + controller × ~3MB
                     + 25% headroom
```

For example: 40 workers × 2 ports × 3MB + 10 handlers × 3MB + 5 push × 3MB + 1 controller × 3MB + 25% = ~330MB. Round up to 512MB.

**Activity level tuning:**

Set `ACTLVL` to the sum of all maximum concurrent jobs across all roles. Monitor `WRKACTJOB` for ineligible threads — if ineligible count is regularly above zero, raise `ACTLVL`. If page faults per second are high but ineligible count is zero, the issue is pool memory size, not activity level.

**Spawn failure validation:**

After the OCI backend timeout is raised, `SPAWN_FAIL` in `HBSSTATS` should drop to near zero. If failures continue:

```sql
-- Check if failures cluster at specific times (load pattern)
SELECT DATE(STAT_TIME), HOUR(STAT_TIME),
       MAX(SPAWN_FAIL) - MIN(SPAWN_FAIL) AS FAILURES_THIS_HOUR
FROM HBSSTATS
WHERE STAT_TYPE = 'CTRLSNAP'
GROUP BY DATE(STAT_TIME), HOUR(STAT_TIME)
HAVING MAX(SPAWN_FAIL) - MIN(SPAWN_FAIL) > 0
ORDER BY 1 DESC, 2;
```

Persistent failures after the OCI fix indicates pool isolation is still needed regardless.

---

### 9.6. Investigation: `child#`, `P2`, `P3` — Dead Code in SendChild / RecvJobs

**Status:** Pending clarification before any removal — do not change without confirmation.

**Background:** A code review of the `SendChild` subroutine and the inline `sendmsg` loop in `RecvJobs` raised questions about three variables: `child#`, `P2`, and `P3`.

#### `child#` — always 1?

`child#` is a global `packed(3)` field declared as `D child# s 3 0`. It is hardcoded to `1` in two places and never modified elsewhere:

1. In `*inzsr`: `child# = 1;`
2. At the top of the main loop on every iteration: `child# = 1;`

It is passed as the `Worker#` parameter to `RecvJobs`, which uses it as the upper bound of the spawn loop (`For cOUNTC = 1 to CHILD#`) and the `sendmsg` loop (`For P2 by 1 to CHILD#`). The architecture clearly anticipated `child#` being variable — the `ser(dim(2))`, `job(dim(2))` arrays, and the throttle logic with `P3` only make sense if multiple children could be spawned per accepted connection. However, `child#` has never been set to anything other than 1 in production.

**Clarification needed:** Confirm that `child#` is intentionally always 1 (one spawned worker per accepted connection) and that there is no plan to ever set it higher before removing dependent code.

#### `P2` — loop counter for `sendmsg`

`P2` is the `For` loop counter iterating `1 to CHILD#`. Since `CHILD# = 1` always, this loop runs exactly once. If `child#` is confirmed as always 1, the `For P2` loop in both `SendChild` and `RecvJobs` could be replaced with a single unconditional `sendmsg` call.

#### `P3` — broken throttle counter (dead code)

`P3` was intended as a batch-send throttle: sleep 100ms after every 5 `sendmsg` calls. The pattern is:

```rpgle
if P3 = 5;
  usleep(0100000);
  P3 = 0;
endif;
```

**However, `P3` is never incremented anywhere in either loop.** It initializes to 0 and stays 0, so `if P3 = 5` can never be true. The `usleep` inside it is permanently unreachable dead code. This same bug exists in both the `SendChild` subroutine and the `sendmsg` loop in `RecvJobs`.

**Proposed cleanup (pending `child#` clarification):**

| Item | Proposed action |
|---|---|
| `P3 = 0;` initialization | Remove from both loops |
| `if P3 = 5 ... endif` block | Remove from both loops (unreachable dead code) |
| `D p3 s 4 0` declaration | Remove if no other references found |
| `For P2 by 1 to CHILD#` loop | Remove loop wrapper, keep single `sendmsg` call — *only if `child#` confirmed always 1* |
| `P2 = 0;` initialization | Remove if loop is removed |
| `D p2 s 4 0` declaration | Remove if no other references found |


