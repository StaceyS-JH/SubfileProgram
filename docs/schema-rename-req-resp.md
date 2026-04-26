# Table Schema Update: Request and Response Rename

## Overview

As part of the BSL subsystem rewrite, the HBSTRANS table columns and the request/response CLOB tables were renamed to better reflect their purpose. The old names were tied to the legacy HBSRECV/HBSSEND model; the new names align with the unified HBSTRANS (IN/OUT) model using request/response terminology.

---

## Column Renames — HBSTRANS

| Old Name    | New Name    | Description                          |
|-------------|-------------|--------------------------------------|
| `HTRCVTS`   | `HTREQTS`   | Timestamp when request was received  |
| `HTRCVSTS`  | `HTREQSTS`  | Status of the inbound request        |
| `HTSNDTS`   | `HTRESTS`  | Timestamp when response was sent     |
| `HTSNDSTS`  | `HTRESSTS` | Status of the outbound response      |

---

## Table Renames — CLOB Storage

| Old Table | New Table  | Key Column            | Description               |
|-----------|------------|-----------------------|---------------------------|
| `HBSREQ`  | `HBSREQD`  | `HRGUID` → `HTGUID`   | Request body (CLOB)       |
| `HBRESP`  | `HBSRESD`  | `HSGUID` → `HTGUID`   | Response body (CLOB)      |

---

## Files Updated

### HBSTRANS.SQL
- DDL column definitions updated to new names.
- `HTRESTS` default set to `'0001-01-01-00.00.00.000000'` (never sent sentinel).

### HBSREQ.SQL
- `CREATE OR REPLACE TABLE` target changed from `HBSREQ` to `HBSREQD`.

### HBRESP.SQL
- `CREATE OR REPLACE TABLE` target changed from `HBRESP` to `HBSRESD`.

### HBSDB.SQLRPGLE
- `Build_In_List` SQL: `HTRCVSTS`→`HTREQSTS`, `HTRCVTS`→`HTREQTS`, `HTRESSTS`→`HTRESSTS`, `HTRESTS`→`HTRESTS` (ORDER BY).
- `Build_Out_List` SQL: `HTSNDSTS`→`HTRESSTS`, `HTSNDTS`→`HTRESTS` (cast + ORDER BY).
- `Show_In` filter: `HTRCVSTS`→`HTREQSTS`, `HTSNDSTS`→`HTRESSTS`, date range uses `HTREQTS`.
- `Show_In` default WHERE: `HTRCVTS`→`HTREQTS`.
- `Show_Out` filter: `HTSNDSTS`→`HTRESSTS`, date range uses `HTRESTS`.
- `Show_In` Reset option: `htreqsts`/`htrespsts`, delete from `hbsresd`.
- `Show_Out` option 2 update: `htrespsts`.
- `ShowDetail` SQL: `HTREQSTS`, `HTRESSTS`, `HTREQTS`, `HTRESTS`.
- NTQuery select: `from HBSREQD`.
- `ViewCLOB` cases: `HBSREQD`, `HBSRESD`.

### HBSPUSH.sqlrpgle
- Join: `HBSREQ`→`HBSREQD`.
- `UpdtSndStat` update: `HTSNDSTS`→`HTRESSTS`.
- Response write: `HBRESP`→`HBSRESD` (update and insert).
- `LoadResend` cursor WHERE: `HTSNDSTS`→`HTRESSTS`.

### HBSCHILD1.SQLRPGLE
- `ReadSQL` select: `from HBSRESD`.
- `UpdtStat` update: `HTSNDSTS`→`HTRESSTS`, `HTSNDTS`→`HTRESTS`.
- `UpdtStatR` update: `HTRCVSTS`→`HTREQSTS`, `HTRCVTS`→`HTREQTS`.
- `WriteRecv` insert into HBSTRANS: `HTRCVSTS`→`HTREQSTS`, `HTSNDSTS`→`HTRESSTS`.
- `WriteRecv` insert: `HBSREQ`→`HBSREQD` (×2 locations).

### HBSCMEVT.sqlrpgle
- HBSTRANS insert column list: `HTSNDSTS`→`HTRESSTS`.
- Request body insert: `HBSREQ`→`HBSREQD`.

### HBSHANDLR.SQLRPGLE
- `UpdtSndStat` update: `HTSNDSTS`→`HTRESSTS`.
- `WrtTrans` update: `HTRCVSTS`→`HTREQSTS`, `HTSNDSTS`→`HTRESSTS`.
- `WrtSend` delete/insert: `HBRESP`→`HBSRESD`.
- `WrtSend` update timestamp: `HTSNDTS`→`HTRESTS`.

### HBSWORK.SQLRPGLE
- `GetSRWorkData` select: `from HBSRESD`.
- `GetRQWorkData` select: `from HBSREQD`, `HTRCVSTS`→`HTREQSTS`.
- `GetMNWorkData` select: `from HBSREQD`, `HTRCVSTS`→`HTREQSTS`.

### HBSWRITER.RPGLE
- `WriteReq` insert: `HBSREQ`→`HBSREQD`.
- `WriteResp` insert: `HBRESP`→`HBSRESD`.

### TSTHBSWRTR.RPGLE
- HBSTRANS insert column list: `HTRCVSTS`→`HTREQSTS`, `HTSNDSTS`→`HTRESSTS`.

---

## Notes

- The `HTTYPE` column (`'IN'`/`'OUT'`) was unchanged.
- No library qualifiers were added; the job's library list resolves the correct library at runtime.
- The physical SQL source file names (`HBSREQ.SQL`, `HBRESP.SQL`) were not renamed on disk, only their DDL content was updated.
- All RPG programs include the standard SQL options block (`Commit=*None`, `CloSqlCsr=*EndMod`, `DatFmt=*ISO`).
