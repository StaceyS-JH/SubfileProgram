# BSL Push Job Control Queue Design

## Overview

The control queue mechanism provides a way to send operational commands to individual push jobs while they are running. It uses a two-queue approach: a keyed **control queue** that holds the command addressed to a specific job, and the job's normal **send queue** which receives a wakeup signal.

---

## Queue Naming Conventions

All queue names are built using the bank number (e.g. `580` for FI 580).

| Queue | Name Pattern | Example | Type |
|-------|-------------|---------|------|
| Control queue | `HBSCNTR###` | `HBSCNTR580` | Keyed data queue |
| Push job send queue | `HBS###SQ01` | `HBS580SQ01` | Data queue (unkeyed) |
| Resend queue | `HBS###RSQ1` | `HBS580RSQ1` | Data queue (unkeyed) |

The control queue key is the **push job name** as it appears in the PSDS job name field (e.g. `B580P1`). This is a 10-character field padded with blanks.

The key requirement means the sender must know the exact job name of the running push job. The dashboard screen displays the job name for each active push job.

---

## How It Works

Sending a command to a push job requires two SQL calls:

### Step 1 — Write the command to the control queue

```sql
CALL QSYS2.SEND_DATA_QUEUE(
  data_queue_library => :datlib,    -- e.g. BSLDAT580
  data_queue         => :ctlq,      -- e.g. HBSCNTR580
  message_data       => :msgdata,   -- e.g. 'RESEND'
  key_data           => :keydata)   -- e.g. 'B580P1    ' (10 chars)
```

### Step 2 — Wake the push job

```sql
CALL QSYS2.SEND_DATA_QUEUE(
  data_queue_library => :datlib,    -- e.g. BSLDAT580
  data_queue         => :datq,      -- e.g. HBS580SQ01
  message_data       => 'CONTROL')
```

The push job is normally blocked waiting on its send queue. The `'CONTROL'` message wakes it. The job then calls `CheckQue` which reads from `HBSCNTR580` using `KEY_ORDER => 'EQ'` and `KEY_DATA => psjobnm` (its own job name from the PSDS), retrieving only the entry written for it.

Multiple push jobs for the same FI (e.g. `B580P1`, `B580P2`) can each have their own entry in `HBSCNTR580` at the same time without interference, because the key isolates them.

---

## Currently Implemented Commands

### ENDJOB

Signals the push job to end cleanly.

- The job logs the normal end to HBSCOMLOG
- Closes the HTTP persistent connection
- Sets `PushIsActive = No` and leaves the main loop

```sql
-- Send to control queue
message_data => 'ENDJOB',
key_data     => 'B580P1    '

-- Wake the job
message_data => 'CONTROL'  (to HBS580SQ01)
```

### RESEND

Signals the push job to drain its resend queue (`HBS580RSQ1`) and retry any GUIDs that were queued there due to prior 5xx HTTP errors or connection failures.

- The job logs the resend action
- Immediately checks `HBS580RSQ1` for a waiting GUID
- Sets `CheckResend = Yes` if GUIDs are found, causing the job to drain the resend queue before returning to normal send queue processing

```sql
-- Send to control queue
message_data => 'RESEND',
key_data     => 'B580P1    '

-- Wake the job
message_data => 'CONTROL'  (to HBS580SQ01)
```

---

## Concrete Example — FI 580, Push Job B580P1

**Scenario:** BSL server returned 503 errors for 10 minutes. GUIDs accumulated in `HBS580RSQ1`. Maintenance is over and you want the push job to retry them.

**Values visible on the dashboard screen:**

| Field | Value |
|-------|-------|
| Data Library | `BSLDAT580` |
| Control Queue | `HBSCNTR580` |
| Key (job name) | `B580P1` |
| Send Queue | `HBS580SQ01` |

**SQL executed by the dashboard:**

```sql
-- Step 1: Write RESEND command addressed to B580P1
CALL QSYS2.SEND_DATA_QUEUE(
  data_queue_library => 'BSLDAT580',
  data_queue         => 'HBSCNTR580',
  message_data       => 'RESEND',
  key_data           => 'B580P1    ');

-- Step 2: Wake B580P1
CALL QSYS2.SEND_DATA_QUEUE(
  data_queue_library => 'BSLDAT580',
  data_queue         => 'HBS580SQ01',
  message_data       => 'CONTROL');
```

**What happens inside B580P1:**

1. `RcvDtaq` returns `'CONTROL'` from `HBS580SQ01`
2. `CheckQue('HBSCNTR580')` is called — reads the entry keyed to `'B580P1    '`
3. `w_dta30` = `'RESEND'`
4. Log entry written to HBSCOMLOG
5. `RcvDtaq(ResendQ...)` called with wait=0 — pulls first GUID from `HBS580RSQ1`
6. `CheckResend = Yes` — subsequent loop iterations drain `HBS580RSQ1` before checking `HBS580SQ01`

---

## Proposed Future Commands

The following commands have been discussed but are not yet implemented. They would follow the same two-step send pattern.

### DEBUGON / DEBUGOFF

Turn HTTPAPI debug file writing on or off dynamically without restarting the push job.

- `DEBUGON` would call `http_debug(*on: dsHbsPars.DebugFilePath)` and set `DebugActive = Yes`
- `DEBUGOFF` would call `http_debug(*off)` and set `DebugActive = No`
- Currently this is handled via the `PushControl` proc (which processes a special GUID with service type `PushCtrl`), but a direct control queue command would be simpler

### STATSON / STATSOFF

Enable or disable periodic statistics logging for the push job. When on, the job would write a snapshot of its counters (send attempts, resend queue depth, connection count, etc.) to HBSCOMLOG at a configurable interval.

### REFRESH

Reload the push job's server parameters from `HBSPARS` without restarting. Would re-execute `LoadPushParameters()` to pick up changes to IP addresses, timeouts, retry counts, etc. A `Refresh` stub already exists in `PushControl` but is not implemented.

### STATSNOW

One-shot version of STATSON — write a single stats snapshot immediately without enabling ongoing interval logging.

---

## Design Notes

**Job name as key:** The sender must supply the exact job name (e.g. `B580P1`) padded to 10 characters. This is a constraint of the keyed data queue design. The dashboard screen displays active push job names to make this practical.

**Command is consumed on receipt:** The entry in `HBSCNTR###` should be removed when the push job reads and acts on it (`REMOVE => 'YES'`). This ensures a new command sent later (including to the same job) is processed correctly and prior commands do not interfere.

**Unknown commands:** If `CheckQue` returns a value that does not match any known command, the `other` branch of the `select` clears `w_qdata` and issues `iter`, effectively ignoring it and returning to wait for the next item on the send queue.

**`CONTROL` as a general-purpose wakeup:** The `'CONTROL'` value on the send queue is only a signal — it carries no command itself. The actual command is always in the control queue. This keeps the send queue simple and allows the control queue to be updated independently of when the push job happens to check it.
