# Activation Group Options: BSL Handler Architecture

**Date:** April 16, 2026  
**Scope:** HBSHANDLR, HBSCHPC, Host Service Programs  
**Context:** BSL Subsystem — 5–10 handler jobs, 5–10 transactions/second per handler

---

## Background

The original bug: HBSCHPC ran with `ACTGRP(*CALLER)`, meaning every host service program called through it joined the **handler's** activation group. Static storage from each distinct host service type accumulated permanently in the handler's AG for the lifetime of the handler job. This caused unbounded memory growth in long-running handler jobs.

**Why host service programs don't set `*INLR = *on`:**  
This was intentional. With `ACTGRP(*CALLER)`, not setting `*INLR` keeps the program "warm" in the handler's AG between calls — files stay open, static storage persists, and the next call to the same service skips re-initialization. A deliberate performance optimization. The downside is that it's also the mechanism that caused the accumulation bug: every distinct host service type loaded its storage permanently into the handler's AG because nothing ever triggered RPG cleanup.

**Why host service programs don’t set `*INLR = *on`:**  
This was intentional. With `ACTGRP(*CALLER)`, not setting `*INLR` keeps the program “warm” in the handler’s AG between calls — files stay open, static storage persists, and the next call to the same service skips re-initialization. A deliberate performance optimization. The downside is that this same persistence is the mechanism behind the accumulation bug: every distinct host service type loaded its storage permanently into the handler’s AG, because nothing ever triggered RPG cleanup.

---

## Option 1 — Current Fix (Minimal Change)

**Settings:**
| Program | ACTGRP |
|---|---|
| HBSHANDLR | `*NEW` |
| HBSCHPC | `*NEW` ← changed |
| Host service programs | unchanged (`*CALLER` or named) |

**How it works:**  
HBSCHPC now creates and destroys its own AG on every call. Host service programs join HBSCHPC's AG, which is torn down on return. The handler's AG remains flat.

**Memory profile:**  
Flat handler AG. Per-transaction allocate/free cycle in HBSCHPC's AG. No accumulation.  
F-spec files open and close on every call — the AG teardown forces cleanup regardless of `*INLR`. The warm-file optimization of the original design is gone.

**Performance:**  
Two AG lifecycle events per transaction (HBSCHPC + host service). CL program activation + dynamic `CALL PGM()` dispatch overhead on every transaction.  
F-spec files open and close on every call — the AG teardown forces cleanup regardless of `*INLR`. The warm-file optimization of the original design is gone.

**Live recompile pickup:**  
Yes — `CALL PGM(&HOSTPGM)` resolves at call time. Recompiled host service is picked up immediately on the next transaction.

**Pros:**  
- Minimal change, low risk  
- Solves the memory problem immediately  
- No architectural changes to host service programs  

**Cons:**  
- HBSCHPC remains as an extra program hop on every transaction  
- Per-transaction allocation/deallocation churn  
- Two AG lifecycle events per call  

---

## Option 2 — Remove HBSCHPC, Direct Call with Variable Extpgm

**Settings:**
| Program | ACTGRP |
|---|---|
| HBSHANDLR | `*NEW` |
| HBSCHPC | **removed** |
| Host service programs | `*NEW` ← changed |

**How it works:**  
Handler calls host service programs directly using a variable `Extpgm()` prototype resolved at runtime:

```rpgle
dcl-pr HBSService extpgm(gSrvcNam);
  pParms    pointer value;
  pResp     pointer value;
  W_Service char(40) const;
  W_Version char(40) const;
end-pr;
```

Each host service runs in its own `*NEW` AG, created and destroyed on each call. Handler AG stays flat.

**Memory profile:**    
F-spec files open and close on every call — same cost as Option 1, just one fewer AG event. `*INLR = *on` should be set explicitly in host service programs; the AG teardown forces file closure regardless, but not setting it is sloppy and can leave activity log entries.
Flat handler AG. Per-transaction allocate/free in each host service's AG. No accumulation.

**Performance:**  
One AG lifecycle event per transaction (host service only — HBSCHPC eliminated). Dynamic `*PGM` call overhead still applies.  
F-spec files open and close on every call — same cost as Option 1, just one fewer AG event. `*INLR = *on` should be set explicitly in host service programs; the AG teardown forces file closure regardless, but not setting it is sloppy practice.

**Live recompile pickup:**  
Yes — `Extpgm(gSrvcNam)` resolves against the library list at call time.

**Pros:**  
- Eliminates one program hop per transaction vs Option 1  
- Simpler call chain  
- Maintains live recompile pickup  

**Cons:**  
- Requires all host service programs changed to `*NEW`  
- Per-transaction allocation/deallocation churn remains  
- No compile-time parameter verification (variable Extpgm)  
- Interface contract must be maintained via shared copybook  

**Important:** A shared copybook defining the standard call interface is essential since the compiler cannot verify the prototype against the called program at compile time:

```rpgle
// qcpysrc,HBSSVCPR
dcl-pr HBSService extpgm(gSrvcNam);
  pParms    pointer value;
  pResp     pointer value;
  W_Service char(40) const;
  W_Version char(40) const;
end-pr;
```

---

## Option 3 — *SRVPGM with Procedure Pointer Cache (Recommended for Rewrite)

**Settings:**
| Program | ACTGRP |
|---|---|
| HBSHANDLR | `*NEW` |
| HBSCHPC | **removed** |
| Host service programs | `*NEW` as `*SRVPGM` ← restructured |

**How it works:**  
Host service programs are converted from `*PGM` to `*SRVPGM`, each exporting a consistent entry point (`Process`). The handler activates each service program on first encounter using `QleActBndPgm`/`QleGetExp`, caches the procedure pointer in a `ServiceMap` array, and calls directly through the pointer on subsequent transactions.

```rpgle
// Registration cache (module-level in handler)
dcl-ds ServiceMap dim(100) qualified;
  Name    char(40);
  ProcPtr pointer(*proc);
end-ds;
dcl-s ServiceCount int(10) inz(0);
```

```rpgle
// Lookup/register on first encounter
dcl-proc GetServicePtr;
  dcl-pi *n pointer(*proc);
    p_Name char(40) value;
  end-pi;
  dcl-s i       int(10);
  dcl-s ActMark pointer;
  dcl-s ErrDS   char(256) inz(*allx'00');

  for i = 1 to ServiceCount;
    if ServiceMap(i).Name = p_Name;
      return ServiceMap(i).ProcPtr;
    endif;
  endfor;

  ServiceCount += 1;
  ServiceMap(ServiceCount).Name = p_Name;
  QleActBndPgm(ActMark : %trimr(p_Name) : '*LIBL' : 0 : ErrDS);
  QleGetExp(ActMark : *omit : 'Process' : 1 :
            ServiceMap(ServiceCount).ProcPtr : ErrDS);
  return ServiceMap(ServiceCount).ProcPtr;
end-proc;
```

```rpgle
// Per-transaction call
gSvcPtr = GetServicePtr(gSrvcNam);
CallService(pParms : pResp : W_Service : W_Version);
```

**Memory profile:**  
Flat handler AG. Each distinct service program's AG created **once*  
F-spec files stay **open** for the life of the handler job — the warm-file behavior of the original design is restored correctly. `*INLR` is irrelevant in `nomain` service program modules. SQL cursors with `CloSqlCsr(*EndMod)` also remain open since the module never deactivates; cursors over tables that change between transactions should be explicitly opened and closed within each procedure call rather than relying on module-level cursor lifetime.* on first encounter, resident for handler job lifetime. Total footprint = (distinct service programs encountered) × (their static storage). Bounded and predictable regardless of transaction volume.

**Performance:**  
First call to each service type: `QleActBndPgm` + `QleGetExp` + bound call.  
Subsequent calls: one array scan + bound call. No AG lifecycle overhead, no dynamic program resolution.  
Fastest option by a significant margin at high transaction volumes.  
F-spec files stay **open** for the life of the handler job — the warm-file behavior of the original design is restored correctly. `*INLR` is irrelevant in `nomain` service program modules. SQL cursors with `CloSqlCsr(*EndMod)` also remain open since the module never deactivates; cursors over tables that change between transactions should be explicitly opened and closed within each procedure call rather than relying on module-level cursor lifetime.

**Live recompile pickup:**  
**No** — cached procedure pointer references the activated version at time of first call. Handler job must be restarted, or cache must be explicitly cleared, to pick up a recompiled service program.

**Cache invalidation strategies:**

1. **RELOAD control queue command** — handler receives `RELOAD` on the existing `w_dta30` control queue mechanism, clears `ServiceMap` immediately:
   ```rpgle
   if %subst(w_dta30:1:6) = 'RELOAD';
     ServiceCount = 0;  // clears entire cache
   endif;
   ```

2. **Dataq timeout reload** — change the main receive dataq wait from `-1` (infinite) to `60` seconds. On timeout (no data returned), clear the cache:
   ```rpgle
   if w_qlen = 0;       // timeout — no data received
     ServiceCount = 0;  // clear cache, next calls re-activate fresh
     iter;
   endif;
   ```
   During quiet periods (overnight, weekends) this fires automatically. During busy periods the RELOAD command covers explicit deployments.

3. **Combined (recommended):** Both mechanisms together — timeout as a safety net for quiet-period deployments, explicit RELOAD for busy-period deployments.

**Effect of number of service programs:**  
Only affects `*SRVPGM` approach. Each distinct service program encountered adds its static storage once:
- 5 programs: 5 × avg static storage, then flat
- 25 programs: 25 × avg static storage, then flat  
- 50 programs: 50 × avg static storage, then flat

A handler that only processes a subset of transaction types only loads the relevant service programs. At typical BSL service program sizes, even 50 programs loaded is negligible on a modern IBM i LPAR.

**Pros:**  
- Best performance of all options  
- Best memory profile — bounded, flat, no per-transaction churn  
- Eliminates HBSCHPC entirely  
- Scales well with increased transaction volumes  

**Cons:**  
- Most architectural work — requires converting host service programs from `*PGM` to `*SRVPGM`  
- Requires cache invalidation strategy for recompiled service programs  
- `QleActBndPgm`/`QleGetExp` API usage adds implementation complexity  
- Appropriate for a major rewrite, not a quick fix  

---

## Comparison Summary

| File opens per transaction | Every call | Every call | First call only (warm) |
| `*INLR` in host services | Irrelevant (AG teardown forces close) | Should be set; AG teardown forces close | Irrelevant (`nomain` module) |
| SQL cursor lifetime | Closed each call | Closed each call | Stays open — manage explicitly per transaction |
| Live recompile pickup | Yes ✓ | Yes ✓ | No — requires cache clear |
| HBSCHPC required | Yes | No | No |
| Host service changes | None | `*NEW` + set `*INLR`
| Memory per transaction | Allocate/free | Allocate/free | Zero (resident) |
| Memory footprint | Bounded | Bounded | Bounded |
| Per-call overhead | 2 AG events | 1 AG event | ~0 after first call |
| File opens per transaction | Every call | Every call | First call only (warm) |
| `*INLR` in host services | Irrelevant (AG teardown forces close) | Should be set; AG teardown forces close | Irrelevant (`nomain` module) |
| SQL cursor lifetime | Closed each call | Closed each call | Stays open — manage explicitly per transaction |
| Live recompile pickup | Yes ✓ | Yes ✓ | No — requires cache clear |
| HBSCHPC required | Yes | No | No |
| Host service changes | None | `*NEW` on all | Convert to `*SRVPGM *NEW` |
| Implementation effort | Minimal | Low | High |
| Right for quick fix | Yes | Yes | No |
| Right for major rewrite | Acceptable | Better | Best |

---

## Recommended Path

**Immediate (already done):** Option 1 — HBSCHPC changed to `ACTGRP(*NEW)`. Solves the memory accumulation bug with minimal risk.

**During rewrite:** Option 3 — Convert host service programs to `*SRVPGM *NEW`, implement procedure pointer cache with RELOAD command + dataq timeout as cache invalidation strategy, remove HBSCHPC.

The HBSCHPC `*NEW` fix provides a stable interim state. Option 3 is the correct long-term architecture for a high-volume, long-running subsystem.

---

---

## Procedure Pointer Registration — Full Implementation Detail

### 1. Service Program Side (each host service)

Every host service program exports a single entry point with a consistent name (`Process`) and a consistent interface:

```rpgle
ctl-opt nomain actgrp(*new);

/include qcpysrc,HBSSVCPR    // shared interface copybook

dcl-proc Process export;
  dcl-pi *n;
    pParms    pointer value;
    pResp     pointer value;
    W_Service char(40) const;
    W_Version char(40) const;
  end-pi;

  // cast pParms/pResp to service-specific DS based on pointer
  // ... service logic ...

end-proc;
```

The `nomain` keyword means this is a service program module — no `*entry` plist, no standalone execution.

---

### 2. Shared Interface Copybook (qcpysrc,HBSSVCPR)

Defines the standard call interface used by both the handler and any test harnesses. The handler's `dcl-pr` uses `extproc(gSvcPtr)` so the pointer drives dispatch:

```rpgle
// qcpysrc,HBSSVCPR
// Standard BSL host service call interface
// Handler uses extproc(gSvcPtr); service programs use this for dcl-pi

dcl-pr HBSService extproc(gSvcPtr);
  pParms    pointer value;
  pResp     pointer value;
  W_Service char(40) const;
  W_Version char(40) const;
end-pr;
```

Both the handler and any test harnesses include this copybook. Any interface change requires updating one place.

---

### 3. Handler Module-Level Declarations

```rpgle
// -------------------------------------------------------
// Service program dispatch - procedure pointer cache
// -------------------------------------------------------

// QLE API: activate a bound service program by name
dcl-pr QleActBndPgm extproc('QleActBndPgm');
  ActMark   pointer;
  SrvPgmNm  char(10)  const;
  LibName   char(10)  const;
  ActOpts   uns(10)   value;
  ErrCode   char(256) options(*varsize);
end-pr;

// QLE API: resolve an exported procedure name to a pointer
dcl-pr QleGetExp extproc('QleGetExp');
  ActMark   pointer        value;
  SpcName   char(256)      options(*varsize:*omit) const;
  ExpName   char(256)      options(*varsize)       const;
  ExpType   int(10)        value;
  ProcPtr   pointer(*proc);
  ErrCode   char(256)      options(*varsize);
end-pr;

// Registration cache
dcl-ds ServiceMap dim(100) qualified;
  Name    char(40);
  ProcPtr pointer(*proc);
end-ds;
dcl-s ServiceCount int(10) inz(0);

// Current dispatch pointer - set by GetServicePtr before each call
dcl-s gSvcPtr pointer(*proc);

// Call interface - driven by gSvcPtr at runtime
/include qcpysrc,HBSSVCPR
```

---

### 4. GetServicePtr Procedure

```rpgle
// -------------------------------------------------------
// GetServicePtr - resolve service name to procedure pointer
// Returns *null and logs error if activation fails
// -------------------------------------------------------
dcl-proc GetServicePtr;
  dcl-pi *n pointer(*proc);
    p_Name char(40) value;
  end-pi;

  dcl-s i       int(10);
  dcl-s ActMark pointer;
  dcl-ds ErrDS;
    ErrBytes_Provided  int(10)  inz(256);
    ErrBytes_Available int(10);
    ErrMsgId           char(7);
    ErrReserved        char(1);
    ErrMsgDta          char(244);
  end-ds;

  // Return cached pointer if already registered
  for i = 1 to ServiceCount;
    if ServiceMap(i).Name = p_Name;
      return ServiceMap(i).ProcPtr;
    endif;
  endfor;

  // Guard against cache overflow
  if ServiceCount >= %elem(ServiceMap);
    hbstools_CommLog(600008:'ServiceMap full - cannot register: '
                            + %trimr(p_Name));
    return *null;
  endif;

  // First encounter - activate service program
  ErrBytes_Provided = 256;
  QleActBndPgm(ActMark : %trimr(p_Name) : '*LIBL' : 0 : ErrDS);
  if ErrBytes_Available > 0;
    hbstools_CommLog(600008:'QleActBndPgm failed for: '
                            + %trimr(p_Name) + ' Msg: ' + ErrMsgId);
    return *null;
  endif;

  // Resolve the exported 'Process' entry point
  ErrBytes_Provided = 256;
  QleGetExp(ActMark : *omit : 'Process' : 1 :
            ServiceMap(ServiceCount + 1).ProcPtr : ErrDS);
  if ErrBytes_Available > 0;
    hbstools_CommLog(600008:'QleGetExp failed for: '
                            + %trimr(p_Name) + ' Msg: ' + ErrMsgId);
    return *null;
  endif;

  // Cache and return
  ServiceCount += 1;
  ServiceMap(ServiceCount).Name = p_Name;
  return ServiceMap(ServiceCount).ProcPtr;

end-proc;
```

---

### 5. Per-Transaction Call in Handler

```rpgle
// Resolve (or retrieve cached) procedure pointer
gSvcPtr = GetServicePtr(gSrvcNam);
if gSvcPtr = *null;
  // activation failed - return error response to caller
  hbstools_CommLog(550021:'Service not found: ' + %trimr(gSrvcNam));
  // ... build error response ...
  return;
endif;

// Bound call through procedure pointer - no AG overhead
HBSService(pParms : pResp : W_Service : W_Version);
```

---

### 6. Cache Invalidation in Handler Main Loop

```rpgle
// On explicit RELOAD command via control queue
if %subst(w_dta30:1:6) = 'RELOAD';
  ServiceCount = 0;    // clear entire cache
  hbstools_CommLog(660001:'Service map reloaded');
endif;

// On dataq read timeout (w_qlen = 0 after 60-second wait)
if w_qlen = 0;
  ServiceCount = 0;    // clear cache - next calls re-activate fresh
  iter;
endif;
```

Setting `ServiceCount = 0` is sufficient — existing `ServiceMap` entries are simply overwritten on next registration. No need to explicitly null out the array.

---

### 7. Build Steps for Each Host Service Program

```
CRTSQLRPGI OBJ(&L/&ON) SRCFILE(&L/QRPGLESRC) OBJTYPE(*MODULE) ...
CRTSRVPGM  SRVPGM(&L/&ON) MODULE(&L/&ON) EXPORT(*ALL) ACTGRP(*NEW)
```

No BND source file needed. `EXPORT(*ALL)` exports every procedure in the module — since each service program has exactly one exported procedure (`Process`), this is equivalent to an explicit exports file with no maintenance overhead.

---

## Notes on HBSHANDLR Activation Group

HBSHANDLR must always be `ACTGRP(*NEW)`:
- It is the entry point of a submitted batch job
- It runs for hours across hundreds or thousands of transactions
- `*CALLER` would place it in the default activation group — no proper cleanup semantics
- A named AG (e.g. `'BSL'`) would cause multiple concurrent handler jobs to share static storage — a data integrity bug identical to the one found in HBSCHILD1

`*NEW` gives each handler job a fully isolated, self-contained activation group with proper lifecycle management.
