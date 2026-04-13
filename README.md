# RPG-LE Subfile Program with SQL Integration

This project demonstrates a comprehensive RPG-LE subfile program that integrates SQL for database operations on IBM i systems. The program provides employee maintenance functionality with search capabilities and basic CRUD operations.

## 🚀 Features

- **Page-at-a-Time Subfile**: Memory-efficient paging with 14 records per page
- **Real-time Lastname Filter**: Filter displayed records instantly using F5
- **Dual Search System**: Initial search + real-time subfile filtering
- **SQL Integration**: Uses embedded SQL with OFFSET/FETCH for pagination
- **Navigation Controls**: Page Up/Down keys for seamless browsing
- **Search Functionality**: Filter employees by department and last name  
- **CRUD Operations**: Create, Read, Update, and Delete employee records
- **Modern RPG-LE**: Uses free-form RPG syntax and structured programming
- **Performance Optimized**: Loads only current page data for large datasets
- **Error Handling**: Comprehensive SQL error handling and user feedback

## 📁 Project Structure

```
SubfileProgram/
├── src/
│   ├── SUBFLPGM.RPGLE    # Main RPG-LE program
│   └── SUBFLSF.DSPF      # Display file (DDS)
├── docs/
│   └── (documentation files)
├── .github/
│   └── copilot-instructions.md
└── README.md
```

## 🔧 Installation & Setup

### Prerequisites

- IBM i system with RPG-LE compiler
- SQL support enabled
- EMPLOYEE table in your library (see Database Setup below)

### DDS Safety Preflight

To catch common fixed-format DDS problems before compile (column alignment,
overlong lines, tabs, and broken literals), run:

```bash
bash tools/check_dspf_safety.sh
```

To check only one display file:

```bash
bash tools/check_dspf_safety.sh src/TESTJWTCFG.DSPF
```

### Database Setup

Create the EMPLOYEE table with the following structure:

```sql
CREATE TABLE EMPLOYEE (
    EMPNO DECIMAL(5,0) NOT NULL PRIMARY KEY,
    FIRSTNAME VARCHAR(20) NOT NULL,
    LASTNAME VARCHAR(20) NOT NULL,
    DEPT CHAR(3) NOT NULL,
    SALARY DECIMAL(9,2) NOT NULL
);

-- Sample data
INSERT INTO EMPLOYEE VALUES 
(12345, 'John', 'Smith', 'IT', 65000.00),
(12346, 'Jane', 'Doe', 'HR', 58000.00),
(12347, 'Bob', 'Johnson', 'ACC', 52000.00),
(12348, 'Alice', 'Brown', 'IT', 72000.00),
(12349, 'Charlie', 'Wilson', 'MKT', 48000.00);
```

### Compilation Steps

1. **Compile the Display File:**
```
CRTDSPF FILE(MYLIB/SUBFLSF) SRCFILE(MYLIB/QDDSSRC) SRCMBR(SUBFLSF)
```

2. **Compile the RPG Program:**
```
CRTRPGMOD MODULE(MYLIB/SUBFLPGM) SRCFILE(MYLIB/QRPGLESRC) SRCMBR(SUBFLPGM)
CRTPGM PGM(MYLIB/SUBFLPGM) MODULE(MYLIB/SUBFLPGM) SRCFILE(MYLIB/QSRVSRC)
```

## 🎯 Usage

### Running the Program

```
CALL MYLIB/SUBFLPGM
```

### Program Flow

1. **Search Screen**: Enter search criteria (optional)
   - Department: 3-character department code
   - Last Name: Partial or full last name
   - Press Enter to search, F3 to exit

2. **Subfile Display**: Review employee records (14 per page)
   - **Filter Field**: Type lastname filter and press F5 to apply
   - Use options 2, 4, or 5 on employees
   - Page Up/Page Down to navigate between pages
   - F5 to refresh with new filter
   - Press Enter to process options
   - F3 to exit, F12 to return to search

### Available Options

- **F5 (Filter)**: Apply lastname filter to current results
- **Option 2 (Change)**: Increases employee salary by 5%
- **Option 4 (Delete)**: Removes employee from database  
- **Option 5 (Display)**: Shows detailed employee information

## 🏗️ Technical Details

### Key Components

#### Display File (SUBFLSF.DSPF)
- **SFL**: Subfile record format for employee data
- **SFLCTL**: Subfile control format with function keys
- **SFLHEAD**: Search criteria input screen
- **SFLFOOTER**: Function key instructions
- **SFLMSG**: Message display area

#### RPG Program (SUBFLPGM.RPGLE)
- **InitializePaging()**: Calculates total records and pages with filters
- **LoadCurrentPage()**: Loads specific page using SQL OFFSET/FETCH
- **BuildFilterCondition()**: Combines search and filter criteria
- **GetSearchCriteria()**: Handles search screen input
- **DisplaySubfilePage()**: Manages page display with filter field
- **ProcessPageInput()**: Handles options, navigation, and F5 filtering
- **UpdateEmployee()**: SQL update operations
- **DeleteEmployee()**: SQL delete operations  
- **DisplayEmployee()**: SQL select for detailed display

### SQL Features Used

- **Dynamic WHERE Clauses**: Runtime filter combination and building
- **Pagination**: OFFSET and FETCH FIRST for efficient page loading
- **Record Counting**: COUNT(*) queries with combined filter conditions
- **Dynamic Cursors**: Runtime cursor creation with positioning
- **Prepared Statements**: Dynamic SQL execution with parameters
- **Multiple Filter Layers**: Search criteria + real-time filtering
- **Error Handling**: SQLCODE checking for robust error management
- **Calculated Fields**: CASE statements for derived data (STATUS field)
- **Pattern Matching**: LIKE operator for flexible searching

### RPG-LE Best Practices

- **Free-form Syntax**: Modern RPG coding style
- **Modular Design**: Separate procedures for different functions
- **Template Data Structures**: Reusable data definitions
- **Proper Initialization**: Clear variable and indicator management
- **Error Messaging**: User-friendly error feedback

## 🔍 Code Highlights

### Dynamic Filter Building
```rpg
P BuildFilterCondition B
D BuildFilterCondition PI           100A   VARYING

  WhereClause = '1=1';
  
  // Add department filter from search
  IF SRCDEPT <> '';
    WhereClause += ' AND DEPT = ''' + %TRIM(SRCDEPT) + '''';
  ENDIF;
  
  // Add lastname filters (search + real-time filter)
  IF SRCLNAME <> '';
    WhereClause += ' AND UPPER(LASTNAME) LIKE ''%' + 
                   %UPPER(%TRIM(SRCLNAME)) + '%''';
  ENDIF;
  
  IF CURRENTFILTER <> '';
    WhereClause += ' AND UPPER(LASTNAME) LIKE ''%' + 
                   %UPPER(%TRIM(CURRENTFILTER)) + '%''';
  ENDIF;
  
  RETURN WhereClause;
P BuildFilterCondition E
```

### Dynamic SQL with Combined Filters
```rpg
SQLSTMT = 'SELECT EMPNO, FIRSTNAME, LASTNAME, DEPT, SALARY, ' +
          'CASE WHEN SALARY >= 50000 THEN ''ACTIVE'' ' +
          'ELSE ''REVIEW'' END AS STATUS ' +
          'FROM EMPLOYEE WHERE ' + FilterCondition + ' ' +
          'ORDER BY LASTNAME, FIRSTNAME ' +
          'OFFSET ? ROWS FETCH FIRST ? ROWS ONLY';
```

### Filter and Navigation Handling
```rpg
SELECT;
  WHEN *IN05; // F5 - Refresh with filter
    IF %TRIM(FILTER) <> CURRENTFILTER;
      FILTERCHANGED = *ON;
      RELOAD = *ON;
    ENDIF;
  WHEN *IN25; // Page Down
    IF PAGENUM < TOTALPAGES;
      PAGENUM += 1;
    ENDIF;
  WHEN *IN26; // Page Up
    IF PAGENUM > 1;
      PAGENUM -= 1;
    ENDIF;
ENDSL;
```

### Total Record Count for Pagination
```rpg
EXEC SQL SELECT COUNT(*) INTO :TOTALRECS
  FROM EMPLOYEE
  WHERE (DEPT = :SRCDEPT OR :SRCDEPT = '')
    AND (UPPER(LASTNAME) LIKE '%' || UPPER(:SRCLNAME) || '%' 
         OR :SRCLNAME = '');

TOTALPAGES = %DIV(TOTALRECS - 1 : PAGESIZE) + 1;
```

## 🛠️ Customization

### Adding New Fields
1. Update the EMPLOYEE table structure
2. Modify the EmpDS data structure in the RPG program
3. Update the display file to include new fields
4. Adjust SQL statements to handle new columns

### Additional Options
- Add new option processing in the ProcessInput() procedure
- Create new procedures for complex operations
- Implement additional validation logic

### Enhanced Search
- Add more search criteria fields to SFLHEAD
- Modify the cursor SQL to include new WHERE conditions
- Update LoadSubfile() procedure accordingly

## 📚 Resources

- [IBM RPG-LE Reference](https://www.ibm.com/docs/en/i/7.4?topic=languages-ile-rpg)
- [IBM SQL for i Reference](https://www.ibm.com/docs/en/i/7.4?topic=i-sql)
- [DDS Reference](https://www.ibm.com/docs/en/i/7.4?topic=specifications-dds-concepts)

## 🤝 Contributing

Feel free to enhance this program by:
- Adding more sophisticated search options
- Implementing data validation
- Adding audit trail functionality
- Creating additional maintenance screens

## 📄 License

This project is provided as an educational example for IBM i development.

---

*Generated by GitHub Copilot - September 30, 2025*