-- ==============================================================
-- Table:       JWTCFG_ACTIVE
-- Source:      JWTCFGA.SQL  (<= 10 chars as requested)
-- Description: Runtime selector table for JWT profile activation
--              by function/use-case.
--
-- Design notes:
--   - One row per FUNCTION_ID (primary key)
--   - JWTLABEL points to the row in JWTCFG to use at runtime
--   - ACTIVE controls whether this function mapping is enabled
-- ============================================================== 

CREATE OR REPLACE TABLE JWTCFG_ACTIVE (

    FUNCTION_ID VARCHAR(64)  NOT NULL,
    JWTLABEL    VARCHAR(36)  NOT NULL,
    ACTIVE      CHAR(1)      NOT NULL DEFAULT 'Y',

    CHGUSR      VARCHAR(128) NOT NULL DEFAULT USER,
    CHGTS       TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT JWTCFGA_PK PRIMARY KEY (FUNCTION_ID),
    CONSTRAINT JWTCFGA_C1 CHECK (ACTIVE IN ('Y', 'N'))
);

-- Fast lookup by label (admin/reporting joins)
CREATE INDEX JWTCFGA_I1
    ON JWTCFG_ACTIVE (JWTLABEL);

-- Table and column labels for IBM i tooling
LABEL ON TABLE JWTCFG_ACTIVE
    IS 'JWT Active by Function';

LABEL ON COLUMN JWTCFG_ACTIVE (
    FUNCTION_ID IS 'Function ID',
    JWTLABEL    IS 'JWT Label',
    ACTIVE      IS 'Active',
    CHGUSR      IS 'Changed By',
    CHGTS       IS 'Changed TS'
);

-- ============================================================== 
-- Optional hard-enforcement:
-- If JWTCFG.JWTLABEL is unique in your environment, you can add
-- a foreign key from JWTCFG_ACTIVE.JWTLABEL to JWTCFG.JWTLABEL.
--
-- Example (enable after verifying uniqueness):
--   CREATE UNIQUE INDEX JWTCFG_U2 ON JWTCFG (JWTLABEL);
--   ALTER TABLE JWTCFG_ACTIVE
--     ADD CONSTRAINT JWTCFGA_FK1
--     FOREIGN KEY (JWTLABEL)
--     REFERENCES JWTCFG (JWTLABEL);
-- ============================================================== 
