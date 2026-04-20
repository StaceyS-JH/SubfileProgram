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

## 7. Benefits

*   **Maximum Performance:** Client response time is no longer impacted by database write or (with Option B) program call latency.
*   **Increased Throughput (TPS):** Handler and receiver jobs are freed up much faster, allowing them to process more transactions.
*   **Granular Operational Control:** Logging can be toggled for specific services without code changes or downtime.
*   **Architectural Flexibility:** The design provides a clear choice to balance performance needs against operational requirements.
*   **Guaranteed Cleanup:** The combination of sequential ownership and a scavenger job provides a multi-layered defense against orphaned system objects.


