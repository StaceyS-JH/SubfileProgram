# HB2360 Program Analysis

## Purpose
HB2360 is a NetTeller account-listing query program. It reads a request buffer, validates customer and parameter setup, builds account-level details and option flags, and sends one output record per account to a data queue.

## High-Level Behavior
1. Reads entry parameters and parses request data from BUFFER.
2. Opens required files and verifies required setup records.
3. Determines runtime mode from BLOBFLAG.
4. Selects output queue name based on mode.
5. Iterates customer accounts and applies visibility/business rules.
6. Builds a 512-byte output record for each account.
7. Sends each record to data queue via QSNDDTAQ.
8. Finalizes counts/errors and executes common close logic.

## Entry Parameter Interface

| # | Parameter | Type/Length | Direction | Notes |
|---|---|---|---|---|
| 1 | QUERY# | 16A | Input | Used at close to derive 3-char request id for logging/reporting. |
| 2 | RELEASE | 16A | Input | Accepted; no active business use found. |
| 3 | VERSION | 16A | Input | Accepted; no active business use found. |
| 4 | PLATFORID | 16A | Input | Accepted; no active business use found. |
| 5 | HOSTETIME | 16A | Input | Accepted; no active business use found. |
| 6 | HOSTALARM | 16A | Input | Accepted; no active business use found. |
| 7 | TRACKID | 16A | Input | Accepted; no active business use found. |
| 8 | NETTELLID | 16A | Input | Accepted; no active business use found. |
| 9 | BUFLENGTH | 16A | Input | Accepted; parsing uses fixed offsets in BUFFER. |
| 10 | BUFFER | 4096A | Input | Main inbound payload parsed by FORMBUFF. |
| 11 | RESLENGTH | 6A | Output | Returned count of output account records. |
| 12 | RECSIZE | 6A | Output/Working | Set to 000450; passed to display summary flow. |
| 13 | QUEERR | 2A | Output | Error code when failures occur. |
| 14 | BLOBFLAG | 1A | Input | Runtime mode selector (for queue/display behavior). |
| 15 | QNAME (via DATAQ parm structure) | 10A | Input | Provided by caller but runtime queue is reset internally. |

## BUFFER Layout (FORMBUFF)

| Offset | Length | Field | Purpose |
|---:|---:|---|---|
| 1 | 12 | NETID | Customer/NetTeller id used for account retrieval. |
| 13 | 10 | USSIGN | User signon/security context. |
| 23 | 20 | RSUDO | Optional related-account filter (blank = full account list). |

## Main Outputs

| Output | Destination | Meaning |
|---|---|---|
| Account records | Data queue (QSNDDTAQ) | One 512-byte record per eligible account. |
| RESLENGTH | Entry parameter | Number of records produced. |
| QUEERR | Entry parameter | 2-char error code for failure path. |
| Display summary call | HB2150 (mode D only, no error) | Receives request id/count/queue/record-size summary data. |

## Data Queue Selection

| Condition | Queue Constant Used |
|---|---|
| MODE <> D | HB512DQ |
| MODE = D | HBDSPDQ512 |

## 512-Byte Output Record Layout (OUTBUFF)

| Seq | Field | Length |
|---:|---|---:|
| 1 | Record marker | 1 |
| 2 | Account name (OUTRSUDO) | 20 |
| 3 | Account number (OUTACCTNO) | 16 |
| 4 | Account type (OUTACTYPE) | 1 |
| 5 | Activity options (OUTACCTAC) | 26 |
| 6 | Status text (OUTST) | 10 |
| 7 | Branch (OUTBRANCH) | 3 |
| 8 | Service charge/type (OUTSCCODE) | 3 |
| 9 | Ledger balance (OUTCBAL) | 14 |
| 10 | Collected balance (OUTCOLBAL) | 14 |
| 11 | Available balance (OUTAVLBAL) | 14 |
| 12 | Sweep balance (OUTSWEEPBL) | 14 |
| 13 | LOC balance (OUTLOCBAL) | 14 |
| 14 | OD limit balance (OUTODLMTBL) | 14 |
| 15 | Mutual fund balance (OUTMFBAL) | 14 |
| 16 | Bounce protection balance (OUTBPBAL) | 14 |
| 17 | Misc 1 balance (OUTMISC1BL) | 14 |
| 18 | Misc 2 balance (OUTMISC2BL) | 14 |
| 19 | Yesterday balance (OUTYESTBAL) | 14 |
| 20 | Statement balance (OUTSTMTBAL) | 14 |
| 21 | Transfer balance flag (OUTTRBALFL) | 1 |
| 22 | Earliest date (OUTEARDATE) | 6 |
| 23 | As-of date (OUTASOFDAT) | 6 |
| 24 | Routing number (OUTROUT) | 9 |
| 25 | Alternate name 1 (OUTALTNAM1) | 40 |
| 26 | Alternate name 2 (OUTALTNAM2) | 40 |
| 27 | Sort options (OPTS26) | 26 |
| 28 | EyeWire flag | 1 |
| 29 | EyeWire format | 1 |
| 30 | Language code | 3 |
| 31 | Language description | 20 |

## Error Code Mapping

| Code | Condition |
|---|---|
| 01 | Required HBPARG read fails. |
| 02 | Required HBPAR1* reads fail (HBPAR1G/HBPAR1E). |
| 03 | Required DDPAR1 or HBMAST read fails. |
| 04 | No account list found or RSUDO account not found. |
| 11 | File open failures or API call failures (including DD5005/LN5010/LN5015 paths). |
| 25 | Cash management profile validation fails (HBCLUS path). |
| 99 | Unmonitored exception trapped in PSSR. |

## Key Subroutines

| Subroutine | Role |
|---|---|
| OPENFILES | Opens all required files and sets error 11 if any open fails. |
| FORMBUFF | Parses NETID, USSIGN, RSUDO from BUFFER. |
| LOADAC | Loads transfer eligibility arrays for account-type transfer logic. |
| GETACC | Dispatches to account-type specific retrieval (DDA, Loan, CD, SDB, Non-JHA). |
| GETDDA | Retrieves DDA/Savings/X-club data and calls DD5005 for balances. |
| GETLN | Retrieves loan data and calls LN5010/LN5015 for available balance logic. |
| GETCD | Retrieves CD data and status/date handling. |
| GETSD | Retrieves safe deposit information. |
| GETNJH | Retrieves non-JHA account details. |
| GETINF | Builds common account output fields and derived display values. |
| GETOPT | Builds option flags by entitlement, account status, and feature checks. |
| OUTBUFF | Packs and sends 512-byte output record to queue. |
| SENDDUMMY | Sends masked/dummy record for inaccessible/filtered account entries. |
| CHECKCLSD | Applies closed-account retention window logic. |
| CLOSEDD5005 | Explicitly closes DD5005 relationship/file state when used. |
| CLOSEPGM (from HBSTAND copybook) | Standard close, error reporting, summary return, LR/return. |

## Account-Type Processing Notes

| Account Type | Logic Highlights |
|---|---|
| D/S/X | Uses DD files and DD5005 API balances; supports status/date filtering and IBT validation flags. |
| L/O | Uses LN files, LN5010/LN5015 for available amounts, and additional payment/advance restrictions. |
| T | Uses CD files; redeemed/maturity date logic influences closed-account skip behavior. |
| B | Uses safe-deposit files; open-status gating applies. |
| Non-JHA | Uses JHMAST/JHTNEW fallback and sets simplified balance behavior. |

## Notable External Calls

| Program/API | Use |
|---|---|
| QCLRDTAQ | Clears target queue before result build. |
| QSNDDTAQ | Sends each packed output record. |
| DD5005 | Deposit account balance/relationship calculations. |
| LN5010 / LN5015 | Loan available-balance calculations. |
| JHDATB / JhMdyToJul | Date window conversion for closed-account filtering. |
| HB2399 | Error logging on failure close path (via HBSTAND close logic). |
| HB2150 | Display-mode summary callback when successful. |

## Summary
HB2360 is a queue-based account listing engine that applies extensive entitlement and account-status business rules, returns fixed-format account records, and reports completion/error status through entry parameters. The primary caller contract is BUFFER in, queue records out, with RESLENGTH and QUEERR signaling completion and error state.
