# RPG-LE Subfile Programming Guide

## Overview
This document provides technical details and best practices for the RPG-LE subfile program with SQL integration.

## Current Project Baseline (April 2026)

The active codebase has standardized on the following interaction patterns:

- AID-byte key handling through workstation INFDS (`pressedKey` at position 369), instead of function-key indicators for business flow decisions.
- Message subfile error/status display at row 24 (`SFLMSGRCD` + `SFLMSGKEY` + `SFLPGMQ`) with footer keys on row 23.
- Explicit empty-subfile safeguards before `READC` processing to prevent session/device errors when no rows are loaded.
- Named display-attribute constants in RPG for P-field highlighting (default input vs error state), instead of scattered hard-coded hex values.

This baseline is used in JWTCFGM, KSCFGM, CRTKSD, and now LSTKSRCD.

## Subfile Processing Concepts

### Subfile Record Format (SFL)
- Contains the data fields displayed in each subfile line
- Uses option field for user selections
- References database fields using REFFLD keyword for consistency

### Subfile Control Format (SFLCTL)
- Controls subfile behavior and display
- SFLSIZ: Maximum number of records (999)
- SFLPAG: Number of records per page (14)
- Display indicators for subfile state (`SFLCLR`, empty suppression, `SFLEND(*MORE)`)

### Function Key Processing (Current Standard)
- Capture keys with INFDS AID byte (`pressedKey`)
- Define symbolic constants (`KEY_F3`, `KEY_F5`, etc.)
- Use `select/when` on `pressedKey` in the main loop and overlays
- Keep indicators focused on display control rather than command routing

### Subfile Loading Techniques

#### Page-at-a-Time Loading (Implemented)
```rpg
// Calculate page positioning
SkipRows = (PAGENUM - 1) * PAGESIZE;

// Use SQL OFFSET/FETCH for pagination
EXEC SQL DECLARE cursor FOR
  SELECT fields FROM table
  WHERE conditions
  ORDER BY sort_fields
  OFFSET :SkipRows ROWS
  FETCH FIRST :PAGESIZE ROWS ONLY;

// Load only current page
DOW SQLCODE = 0 AND RRN01 < PAGESIZE;
  EXEC SQL FETCH cursor INTO :record;
  IF SQLCODE = 0;
    Write SFL;
  ENDIF;
ENDDO;
```

#### Load-All Approach  
Simpler but memory intensive - not recommended for large datasets.

## SQL Integration Patterns

### Cursor Processing
Best for subfile loading:
```sql
DECLARE cursor_name CURSOR FOR
  SELECT fields
  FROM table  
  WHERE conditions
  ORDER BY sort_fields;
```

### Prepared Statements
Efficient for repetitive operations:
```rpg
EXEC SQL PREPARE stmt FROM :sql_string;
EXEC SQL EXECUTE stmt USING :parameters;
```

### Error Handling
Always check SQLCODE:
```rpg
IF SQLCODE < 0;
  // Handle error
  MSG = 'SQL Error: ' + %CHAR(SQLCODE);
ENDIF;
```

## Real-time Filtering Implementation

### Display File Filter Field
```dds
A            FILTER        20A  B  6 24DSPATR(UL)
A            CF05(05 'Refresh')
```

### Filter Processing Logic
```rpg
// Check for filter changes
IF %TRIM(FILTER) <> CURRENTFILTER;
  FILTERCHANGED = *ON;
  RELOAD = *ON;
  // Reset to page 1 when filter changes
  PAGENUM = 1;
ENDIF;
```

### Dynamic WHERE Clause Building
```rpg
P BuildFilterCondition B
  WhereClause = '1=1';
  
  // Combine search criteria and real-time filter
  IF SRCDEPT <> '';
    WhereClause += ' AND DEPT = ''' + %TRIM(SRCDEPT) + '''';
  ENDIF;
  
  // Multiple lastname filters can be combined
  IF SRCLNAME <> ''; // From search screen
    WhereClause += ' AND UPPER(LASTNAME) LIKE ''%' + 
                   %UPPER(%TRIM(SRCLNAME)) + '%''';
  ENDIF;
  
  IF CURRENTFILTER <> ''; // From subfile filter
    WhereClause += ' AND UPPER(LASTNAME) LIKE ''%' + 
                   %UPPER(%TRIM(CURRENTFILTER)) + '%''';
  ENDIF;
P BuildFilterCondition E
```

### Filter State Management
- **CURRENTFILTER**: Stores active filter value
- **FILTERCHANGED**: Tracks when filter needs to be applied
- **RELOAD**: Triggers reinitialization when filter changes

## Page Navigation Implementation

### Display File Keywords
- **SFLSIZ(14)**: Matches page size for memory efficiency
- **ROLLUP(25)**: Indicator 25 for Page Down key
- **ROLLDOWN(26)**: Indicator 26 for Page Up key

### Pagination Variables
```rpg
D PAGENUM         S             5P 0   // Current page number
D TOTALPAGES      S             5P 0   // Total pages calculated
D TOTALRECS       S             5P 0   // Total matching records
D PAGESIZE        C                   CONST(14)
```

### Page Calculation Logic
```rpg
// Get total record count first
EXEC SQL SELECT COUNT(*) INTO :TOTALRECS FROM table WHERE conditions;

// Calculate total pages
IF TOTALRECS > 0;
  TOTALPAGES = %DIV(TOTALRECS - 1 : PAGESIZE) + 1;
ELSE;
  TOTALPAGES = 0;
ENDIF;
```

### Navigation Processing
```rpg
SELECT;
  WHEN *IN25 AND PAGENUM < TOTALPAGES;  // Page Down
    PAGENUM += 1;
  WHEN *IN26 AND PAGENUM > 1;          // Page Up  
    PAGENUM -= 1;
  OTHER;
    // Show appropriate message
ENDSL;
```

## Performance Considerations

### SQL Optimization
- Use appropriate WHERE clauses
- Create indexes on frequently searched columns
- Limit result sets with reasonable boundaries
- Use FETCH FIRST n ROWS for large datasets

### Subfile Efficiency
- **Page-at-a-Time**: Only loads 14 records at once
- **Memory Optimization**: SFLSIZ matches SFLPAG for efficiency
- **SQL Optimization**: Uses OFFSET/FETCH instead of large cursors
- **Responsive UI**: Immediate page response without data loading delay

### Memory Management
- Clear arrays and data structures when done
- Close SQL cursors promptly
- Use OCCURS for fixed-size arrays vs. based templates

## Error Handling Best Practices

### Message Subfile Pattern (Recommended)

Use the same queue-driven pattern across interactive programs:

1. Send message text with `snd-msg %target(*caller)` from a small helper (for example, `SetError`).
2. Write message control format each interaction cycle (`write ...MSGCTL`).
3. Clear program messages after `exfmt` using `QMHRMVPM` (`*ALL`).
4. Use `SFLEND(*MORE)` on the message subfile for multi-message scenarios.

This pattern replaced fixed overlay message fields and provides consistent diagnostics UX.

### SQL Error Management
```rpg
Monitor;
  EXEC SQL operation;
  IF SQLCODE < 0;
    HandleSQLError(SQLCODE : SQLSTATE);
  ENDIF;
On-Error;
  // Handle RPG errors
EndMon;
```

### User-Friendly Messages
- Provide clear, actionable error messages
- Log technical details for debugging
- Use message files for multilingual support

## Security Considerations

### SQL Injection Prevention
- Always use parameter markers (?) in SQL
- Validate input data
- Use prepared statements for dynamic SQL

### Authorization
- Check user authority before operations
- Implement field-level security where needed
- Log security-sensitive operations

## Testing Strategies

### Unit Testing
- Test individual procedures separately
- Mock database operations for isolated testing
- Validate error handling paths

### Integration Testing
- Test complete user workflows
- Verify SQL performance with realistic data volumes
- Test concurrent user scenarios

### Data Validation Testing
- Test boundary conditions
- Verify referential integrity
- Test with invalid/missing data

## Maintenance Guidelines

### Code Organization
- Keep procedures focused and single-purpose
- Use meaningful variable names
- Document complex business logic
- Maintain consistent coding style

### Version Control
- Track changes to both RPG and DDS sources
- Document database schema changes
- Maintain deployment scripts

### Performance Monitoring
- Monitor SQL statement performance
- Track subfile load times
- Monitor memory usage patterns

## Advanced Filtering Techniques

### Multi-field Filtering
Expand filtering to multiple fields:
```rpg
// Add more filter fields to display file
A            DEPTFILTER     3A  B  7 24DSPATR(UL)
A            SALARYMIN      9P 2 B  8 24DSPATR(UL)

// Build complex WHERE clauses
IF DEPTFILTER <> '';
  WhereClause += ' AND DEPT = ''' + %TRIM(DEPTFILTER) + '''';
ENDIF;

IF SALARYMIN > 0;
  WhereClause += ' AND SALARY >= ' + %CHAR(SALARYMIN);
ENDIF;
```

### Filter History/Favorites
```rpg
// Store frequently used filters
D FilterHistory   DS                  OCCURS(10) TEMPLATE
D  FilterName                  20A
D  FilterValue                 50A

// Allow users to save/recall filters
SaveFilter(filter_name : current_filter);
RecallFilter(filter_name);
```

### Auto-complete Filtering
```rpg
// Suggest values as user types
EXEC SQL SELECT DISTINCT LASTNAME INTO :SuggestionArray
  FROM EMPLOYEE 
  WHERE UPPER(LASTNAME) LIKE UPPER(:partial_input) || '%'
  ORDER BY LASTNAME
  FETCH FIRST 10 ROWS ONLY;
```

## Advanced Pagination Techniques

### Bookmark-Based Pagination
For very large datasets, consider key-based positioning:
```rpg
// Instead of OFFSET, use WHERE clause with last key
WHERE key_field > :last_key_from_previous_page
ORDER BY key_field
FETCH FIRST :PAGESIZE ROWS ONLY;
```

### Caching Strategies
```rpg
// Cache next page for smoother navigation
IF page_direction = 'FORWARD';
  LoadPage(PAGENUM + 1 : next_page_cache);
ENDIF;
```

### Progressive Loading
```rpg
// Load additional pages in background
IF user_idle_time > threshold;
  PreloadAdjacentPages();
ENDIF;
```

## Advanced Techniques

### Dynamic Subfile Loading
Load subfiles based on runtime conditions:
```rpg
Select;
  When display_type = 'SUMMARY';
    LoadSummarySubfile();
  When display_type = 'DETAIL'; 
    LoadDetailSubfile();
EndSl;
```

### Multi-Format Subfiles
Different record formats in same subfile:
```dds
A          R SFLREC1                   SFL
A            FIELD1    10A  O  8  2
A          R SFLREC2                   SFL  
A            FIELD2    20A  O  8  2
```

### Conditional Field Display
Use indicators for dynamic field behavior:
```dds
A            FIELD1    10A  O  8  2DSPATR(UL : !50)
A                                  DSPATR(HI : 50)
```

## Troubleshooting Common Issues

### Subfile Not Displaying
- Check SFLDSP and SFLDSPCTL indicators
- Verify RRN (relative record number) management  
- Ensure subfile records were written
- Verify PAGENUM is within valid range (1 to TOTALPAGES)

### Empty Subfile Session/Device Errors
- Guard `READC` calls when the subfile is empty (for example, check `SflEmpty` first)
- Keep `SFLDSP` suppressed when no rows exist
- Reset `SFLEND(*MORE)` indicator off in empty/error paths
- Refresh subfile state before re-entering selection loops

### Page Navigation Issues
- Check ROLLUP/ROLLDOWN indicators (*IN25/*IN26)
- Verify TOTALPAGES calculation is correct
- Ensure OFFSET calculation: (PAGENUM-1) * PAGESIZE
- Check for proper cursor closure between pages

### Filtering Issues
- Verify F5 function key indicator (*IN05) is working
- Check filter field (FILTER) is properly bound to screen
- Ensure CURRENTFILTER variable is updated correctly
- Verify BuildFilterCondition() returns valid SQL syntax
- Test with special characters in filter (apostrophes, quotes)
- Check that PAGENUM resets to 1 when filter changes

## Program-Specific Architecture Notes

### CRTKSD + KSCFGM Create/Register Flow
- CRTKSD remains a standalone keystore-create screen/program that calls CRTKS.
- CRTKSD now supports optional outputs: created file, created library, function, and write-to-config flag.
- KSCFGM uses the write flag to decide whether to insert the newly created keystore into KSCFG.
- This supports both workflows: direct keystore creation only, or managed registration in KSCFG.

### LSTKSRCD Modernization
- LSTKSRCD now follows the same AID-key and message-subfile patterns as JWTCFGM/KSCFGM.
- LSTKSRCD empty-subfile handling includes explicit `READC` guards to avoid runtime device/session faults.

### Dynamic SQL Problems
- Validate generated WHERE clause syntax
- Check for SQL injection risks in filter values
- Ensure proper escaping of single quotes in filter text
- Test PREPARE statement with various filter combinations

### SQL Performance Problems  
- Analyze query execution plans
- Check for missing indexes
- Review WHERE clause efficiency

### Memory Issues
- Monitor OCCURS array sizes
- Check for unclosed cursors
- Verify proper cleanup in error paths

---

This guide serves as a reference for maintaining and extending the RPG-LE subfile program.