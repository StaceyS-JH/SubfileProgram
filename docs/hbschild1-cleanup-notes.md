# HBSCHILD1 Cleanup Notes

Global variables declared at module level that appear to be unused.
Verify before removing — RPG is case-insensitive so search results are reliable,
but confirm nothing is referenced in the original production member we don't have locally.

---

## Likely Unused: Leftover Keyed Data Queue Variables

These were used with keyed RCVDTAQ calls in the original program.
The global declarations are shadowed by identical local variables inside `CheckQue`.

| Variable | Line | Declaration |
|---|---|---|
| `w_keyord` | 183 | `char(2) inz('EQ')` |
| `w_keylen` | 184 | `packed(3,0) inz(0)` |
| `w_keydata` | 185 | `char(10) inz(*blanks)` |
| `w_sendlen` | 186 | `packed(3,0) inz(8)` |
| `w_sendinf` | 187 | `char(8) inz(*blanks)` |
| `w_pqlen` | 228 | `packed(5) inz(10)` |
| `w_pqkeylen` | 229 | `packed(3) inz(10)` |
| `w_pqkeydta` | 230 | `char(10)` |
| `w_pqdata` | 231 | `char(10)` |
| `w_qdata2` | 227 | `char(36)` — `w_qlen2` IS used in RcvDtaq call; this companion var is not |
| `w_dta` | 179 | `char(10)` — distinct from `w_dtaqnm` and `w_dtaqctl` which are used |
| `w_dtactl` | 180 | `char(10)` — distinct from `w_dtaqctl` which is used |

---

## Likely Unused: Leftover Socket/SSL Setup Variables

| Variable | Line | Declaration |
|---|---|---|
| `ChildSocket10` | 151 | `char(10)` — socket switched to `ChildSocketID int(10)` |
| `ChildSocket4` | 152 | `char(4)` |
| `HBSBuffer` | 156 | `char(256) based(BufferPtr)` — `BufferPtr` is also never set |
| `HowManyMore` | 154 | `int(5,0)` |
| `ErrorCode` | 167 | `int(10)` |
| `Data` | 158 | `char(1024)` |

---

## Likely Unused: Receive-Side Processing Variables

| Variable | Line | Declaration |
|---|---|---|
| `rcvbuffer` | 221 | `char(1000)` — distinct from `rcvbuff` (the real socket receive buffer) |
| `cnvrtrcv` | 222 | `varchar(1000)` |
| `rcvrslt` | 223 | `varchar(32767)` |
| `r_attmpt` | 220 | `packed(3)` — attempt counter; `pAttempt` (passed to WrtSend) is the used one |
| `w_content#` | 194 | `int(10)` |
| `w_reqparsed` | 195 | `int(10)` |

---

## Likely Unused: Miscellaneous

| Variable | Line | Declaration |
|---|---|---|
| `null` | 175 | `char(1) inz(x'00')` — never passed to any call |
| `errcee` | 208 | `char(1)` |
| `MsgSize` | 214 | `int(10)` |
| `pIgnoreMsg` | 215 | `pointer(*proc) inz(%paddr('JHIGNM'))` — error handler never registered |
| `iPos` | 250 | `int(10) inz(1)` |
| `RCVErr` | 260 | `char(200)` |
| `gIndx` | 265 | `int(10)` — GSK server list index; array never loaded |
| `gSrvrNam` | 266 | `char(20) dim(10)` — GSK server name array; never loaded |

---

---

## CheckQue Proc — Refactor to Match HBSHANDLR Pattern

`CheckQue` in HBSCHILD1 uses the legacy `RcvDtaqKey` API. HBSHANDLR has an equivalent
proc (`CheckKeyQue`) that was already corrected to use `QSYS2.RECEIVE_DATA_QUEUE` SQL.
HBSCHILD1 should be aligned.

### Current HBSCHILD1 `CheckQue` (lines 1463–1502)
- Fixed-format `P/D` proc definition with `opdesc`
- Calls legacy `RcvDtaqKey` API with 13 positional parameters
- Takes only queue name as parameter; library (`w_dtaqlib`) and key (`psjobnm`) pulled from globals implicitly
- 8 unused local variables: `ck_datqnm`, `ck_datlib`, `w_len`, `w_wait`, `w_keyord` (inz('NE') but 'EQ' is hardcoded inline), `w_sendlen`, `w_sendinf`, `DataQLen`, `Qdlen`
- Error DS `w_ErrDS` (4 subfields) declared but result never checked

### Target pattern from HBSHANDLR `CheckKeyQue` (lines 913–942)
- Free-format `dcl-proc`
- `QSYS2.RECEIVE_DATA_QUEUE` SQL table function — no API call, no error DS needed
- Three explicit params: `p_dtaqnm`, `p_dtaqlib`, `p_keydata`
- `sqlstate = '02000'` check handles no-data case cleanly
- No local variables at all

### Changes needed
1. Replace `RcvDtaqKey` API call with `QSYS2.RECEIVE_DATA_QUEUE` SQL (same as HBSHANDLR)
2. Convert proc from fixed-format `P/D` to free-format `dcl-proc`
3. Add `p_dtaqlib` and `p_keydata` parameters; remove implicit global references
4. Drop all 8 local variables and the error DS
5. Rename `CheckQue` → `CheckKeyQue` for consistency
6. Update the prototype (line 283) and both call sites:
   - Line 497: `CheckQue(w_dtaqctl)` → `CheckKeyQue(w_dtaqctl:w_dtaqlib:psjobnm)`
   - Line 908: `CheckQue(w_dtaqctl)` → `CheckKeyQue(w_dtaqctl:w_dtaqlib:psjobnm)`

---

---

## RecvDta Procedure — Issues and Simplifications

### Issue 1: `hbiconv` called unconditionally — BUG for SSL path (line 991)

```rpgle
hbiconv(jha_ccsid_UTF_8:jha_ccsid_EBCDIC :pbuffer:etoasize);
PBUFFER += result;
```

This conversion runs after both `hbssock_Read` (SSL) and `recv` (plain socket). The GSKit
`hbssock_Read` already returns data in EBCDIC — it handles CCSID translation internally.
Calling `hbiconv` on already-EBCDIC data corrupts the buffer for the SSL path.

**Fix:** Move `hbiconv` inside the `else` (non-SSL) branch, executed only after a successful
`recv()` call. The SSL path should not call it at all.

```rpgle
// Corrected structure:
If gSecurity = *on;
  result = hbssock_Read(...);   // returns EBCDIC — no conversion needed
else;
  result = recv(...);
  if result > 0;
    hbiconv(jha_ccsid_UTF_8:jha_ccsid_EBCDIC:pbuffer:etoasize);
  endif;
endif;
```

---

### Issue 2: Dead code in SSL result=0 handling (lines 922–933)

```rpgle
If result = 0;
  If rcvLen = 0;
    result = -1;
  else;
  If rcvlen > 0;       // <-- unreachable: if rcvLen=0 was false, rcvLen>0 is always true
    result = rcvLen;
    hbstools_CommLog(result:'Result 0 and rcvlen');
    result2 = 0;
  endif;
  endif;
```

The inner `If rcvLen > 0` is dead code — if `rcvLen = 0` was false, `rcvLen > 0` is the
only other possible state for a numeric field. Simplify to:

```rpgle
If result = 0;
  if rcvLen = 0;
    result = -1;   // nothing read, treat as error
  else;
    result = rcvLen;   // promote byte count into result
    result2 = 0;
  endif;
```

The `hbstools_CommLog` call on the success path is also suspect — logging every successful
SSL read will flood the comm log. Remove or gate it behind a debug flag.

---

### Issue 3: SSL error 502 (would-block) mapping is undocumented (lines 935–939)

```rpgle
if result = 502;
  result2 = 3406;   // map to errno "would block"
  result  = -1;
```

GSKit error 502 = SSL_ERROR_WANT_READ (non-blocking socket, no data yet). The code maps
it to errno 3406 so the `ENDSL` below handles it the same way as a plain-socket EWOULDBLOCK.
The logic is correct but has no comment explaining *why*. Add:

```rpgle
// GSKit 502 = SSL_ERROR_WANT_READ (equivalent to errno 3406 EWOULDBLOCK)
```

---

### Issue 4: `iToGet` loop terminator is misleading

`iToGet` is initialized to 10000, used as the recv buffer size, reset to 10000 at the bottom
of every cycle, and the outer loop tests `dow itoget > 0`. There is no path that sets it to 0
or below — the loop exits only via `Leave` statements. The `dow itoget > 0` condition is
never false in practice.

**Fix:** Change to `dow *on` and rely on the explicit `Leave` statements. Remove the
`ItoGet = 10000` reset at the bottom and declare `iToGet` as a constant or just inline 10000
in the `recv`/`hbssock_Read` calls.

---

---

## CheckHeader Procedure — Simplification Opportunity

The procedure is 80+ lines but the core work is straightforward: find `Content-Length:`,
extract the integer value, find the `{` (JSON start), calculate the message end position.

### What can be simplified

**The digit-extraction loop (lines ~640–660) is unnecessary.**
The current code walks characters one at a time, filters against a `numbers` constant, and
builds up a 4-char `w_contlen` field. This entire block can be replaced with a single
`%subst` + `%int` inside a monitor:

```rpgle
monitor;
  content_length = %int(%trim(%subst(w_buffer:w_clStart:w_clEnd - w_clStart)));
on-error;
  return 0;
endmon;
```

**The `SELECT` for finding line end runs each `%scan` twice** — once as the condition and
once to capture the result. Change to sequential `if`/`if`:

```rpgle
w_clEnd = %scan(CR:w_buffer:w_clStart);
if w_clEnd = 0;
  w_clEnd = %scan(LF:w_buffer:w_clStart);
endif;
```

**The `if w_start > 0` guard is unreachable** — the early return on `w_clStart = 0` already
handles the not-found case. Everything after it can be at the top level.

### Variables that can be removed after rewrite

| Variable | Type | Replaced by |
|---|---|---|
| `w_char` | `char(1)` | Not needed — loop eliminated |
| `w_contlen` | `char(4)` | Not needed — `%int(%subst(...))` used directly |
| `w_len` | `int(10)` | Not needed — assign directly to `content_length` |
| `w_endh` | `int(10)` | Rename to `w_clEnd` (same role, clearer name) |
| `w_pos` | `int(10)` | Not needed — loop eliminated |
| `w_indx1` | `int(10)` | Not needed — loop eliminated |
| `w_indx2` | `int(10)` | Not needed — loop eliminated |
| `numbers` | `const` | Not needed — loop eliminated |

**Net result:** 8 local variables/constants removed, 15-line digit-extraction loop replaced
by 4 lines, `SELECT` replaced by sequential `if`. Behavior is identical.

### Proposed rewrite

```rpgle
dcl-proc CheckHeader;
  dcl-pi *n int(10);
    i_buffer char(32000) value;
    w_starth  int(10) value;
  end-pi;

  dcl-s w_clStart int(10);   // position of first digit of Content-Length value
  dcl-s w_clEnd   int(10);   // position of line terminator after value

  dcl-c CL   const('Content-Length:');
  dcl-c CR   const(x'25');
  dcl-c LF   const(x'0d');
  dcl-c Json const('{');

  if w_starth = 1;
    morereq = 1;
  endif;

  bufferlen = %len(%trim(i_buffer));
  w_buffer  = i_buffer;
  w_start   = 0;
  w_end     = 0;

  // Locate Content-Length header line
  w_clStart = %scan(CL:w_buffer:w_starth);
  if w_clStart = 0;
    morereq = 0;
    return 0;
  endif;
  w_clStart += %len(CL);   // advance past 'Content-Length:' to the value

  // Find end of value line
  w_clEnd = %scan(CR:w_buffer:w_clStart);
  if w_clEnd = 0;
    w_clEnd = %scan(LF:w_buffer:w_clStart);
  endif;
  if w_clEnd = 0;
    return 0;
  endif;

  // Extract the integer — monitor handles any non-numeric content
  monitor;
    content_length = %int(%trim(%subst(w_buffer:w_clStart:w_clEnd - w_clStart)));
  on-error;
    return 0;
  endmon;

  // Find JSON start and calculate message end position
  jsonstrt = %scan(Json:w_buffer:w_clStart);

  if jsonstrt = 0 and content_length > 0;
    r_clob = '{"BaseRequest":null,"ResponseDetailCollection":[{' +
              '"ResponseCode": 600009' +
              ',"ResponseMessage":"Received Header no JSON"}],"Success":false}';
    h400err = *on;
    senddtaerr();
    hbstools_CommLog(600009:'Header and no json' + rcvbuff);
    h400err = *off;
    return 0;
  endif;

  if w_end = 0;
    w_end = %scan(MsgEnd:w_buffer:w_clStart);
    if w_end = 0 and totlrcv <= (jsonstrt + content_length) - 1;
      w_end = (jsonstrt + content_length) - 1;
    endif;
  endif;

  return morereq;

end-proc;
```

---

## Notes on Variables That Look Suspicious But Are Used

| Variable | Why it looks suspect | Where it's actually used |
|---|---|---|
| `totr` | Only declared in D-specs | `SendDta` send loop (lines 1267-1303, 1343-1360) |
| `retry` | Only declared in D-specs | `SendDta` send loop alongside `totr` |
| `PrmPtr` | Assigned but seemingly unused | `%addr(PrmJson)` in `WriteRecv` (line 1068) and `WriteEndr` (line 1438) |
| `RecvRetry` / `recvretry` | Two capitalizations | Same variable (RPG case-insensitive); heavily used in `RecvDta` |
| `rc` | Set but never assigned a non-zero value | Returned from `CheckQue` proc (line 1500) — always 0 |
| `w_qlen2` | Companion to unused `w_qdata2` | Passed to `RcvDtaq` call (line 1247) as the length parameter |
