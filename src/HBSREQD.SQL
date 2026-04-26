-- =================================================================
-- HBSREQD: Request Data File
-- =================================================================
CREATE OR REPLACE TABLE HBSREQD (
    HRGUID          CHAR(36)      NOT NULL,       -- Logical link to HBSTRANS.HTGUID
    HRTS            TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP, -- Write timestamp
    HRBODY          CLOB(16M)     ALLOCATE(4096),       -- Inbound JSON payload; 100% of payloads fit inline

    PRIMARY KEY(HRGUID)
);

LABEL ON TABLE HBSREQD IS 'BSL Request Data';
