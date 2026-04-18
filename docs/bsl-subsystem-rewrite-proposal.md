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

### Phase 1: Database Refactoring (Synchronous)
1.  **Create New Tables:** Define and create the new `HBSTRANS`, `HBSREQ`, and `HBRESP` tables.
2.  **Refactor Application:** Modify the application to write to the new tables synchronously. This step improves the database schema without introducing asynchronous complexity.
3.  **Test & Deploy:** Validate and deploy the synchronous refactoring to establish a stable foundation.

### Phase 2: Asynchronous & Service Architecture Implementation
1.  **Create Asynchronous Framework:** Create the persistent `HBSWRITER` job and the `HBSLOGDQ` data queue.
2.  **Offload CLOB Writes:** Refactor the application to write large JSON payloads to User Spaces and send messages to the writer job, removing the `INSERT` from the main transaction path.
3.  **Implement Writer Logic:** The `HBSWRITER` will process the queue, write data from the User Space to the database, and delete the User Space.
4.  **Implement Service Architecture:** Choose and implement one of the two service architecture options detailed in section 3.2.
5.  **Refactor Response Flow:** Ensure the final response from `HBSHANDLR` is passed back to `HBSCHILD1` via a pointer to avoid copying large memory blocks.
6.  **Create Scavenger Job:** Implement a periodic cleanup job to remove any orphaned User Spaces or other objects.
7.  **Test & Deploy:** Validate and deploy the full asynchronous, high-performance solution.

## 3. Core Architectural Changes

### 3.1. Asynchronous Logging with a Persistent Writer

To resolve I/O bottlenecks, we will implement a unified asynchronous logging mechanism.

*   **Persistent Writer Job (`HBSWRITER`):** A single, long-running RPGLE program that waits on a data queue (`HBSLOGDQ`) to receive work.
*   **In-Memory Data Transfer (User Spaces):** Large JSON payloads will be written to temporary User Space (`*USRSPC`) objects. A unique 10-character name will be generated for each.
*   **Communication (Data Queues):** A single, permanent Data Queue (`HBSLOGDQ`) will act as the work queue. Messages will contain the User Space name, its library, and the transaction GUID.
*   **Logging Control File (`HBSLOGCTL`):** A new configuration file will allow logging to be toggled on or off for each service.

### 3.2. Service Architecture: Two Options

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

### 3.3. Memory Management & Pointer Usage

A core tenet of this design is to minimize memory duplication. Large data payloads will be passed by reference using pointers.

*   **Asynchronous Logging Flow:** Only the 10-character User Space name (acting as a handle) is passed between jobs, not the multi-megabyte payload itself.
*   **Client Response Flow (`HBSHANDLR` -> `HBSCHILD1`):** The final response payload will be passed back to `HBSCHILD1` via a pointer to the memory buffer, avoiding a costly data copy.

## 4. Resource Management & Preventing Orphans

A key concern is preventing orphaned objects (`*USRSPC`) from accumulating.

1.  **Sequential Ownership (Primary Defense):** The process establishes a clear chain of ownership. `HBSCHILD1` creates the User Space, `HBSHANDLR` uses it, and then passes ownership to `HBSWRITER`. **The `HBSWRITER` job is the sole and final owner responsible for deleting the User Space.**
2.  **Scavenger Job (Secondary Defense):** A periodic "scavenger" job will run to find and delete any objects older than a defined Time-to-Live (e.g., 24 hours), ensuring the system remains clean.

## 5. Performance & Implementation Considerations

*   **Synchronous Status Updates:** It has been reviewed and confirmed that small, fast SQL `UPDATE` statements (e.g., for a status flag) do **not** need to be offloaded and can be performed synchronously by the main application programs.
*   **Error Handling:** The `HBSWRITER` program must have robust error handling to log any failures during the database write process.
*   **Job Queue Management:** The `HBSWRITER` job should be configured to run in an appropriate subsystem and job queue.

## 6. Benefits

*   **Maximum Performance:** Client response time is no longer impacted by database write or (with Option B) program call latency.
*   **Increased Throughput (TPS):** Handler and receiver jobs are freed up much faster, allowing them to process more transactions.
*   **Granular Operational Control:** Logging can be toggled for specific services without code changes or downtime.
*   **Architectural Flexibility:** The design provides a clear choice to balance performance needs against operational requirements.
*   **Guaranteed Cleanup:** The combination of sequential ownership and a scavenger job provides a multi-layered defense against orphaned system objects.


