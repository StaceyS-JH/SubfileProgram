-- =================================================================
-- HBSREQ: Request Data File
-- =================================================================
CREATE OR REPLACE TABLE HBSREQ (
    HRGUID          CHAR(36)      NOT NULL,       -- Logical link to HBSTRANS.HTGUID
    HRBODY          CLOB(16M),                    -- Inbound JSON payload

    PRIMARY KEY(HRGUID)
);

LABEL ON TABLE HBSREQ IS 'BSL Request Data';
