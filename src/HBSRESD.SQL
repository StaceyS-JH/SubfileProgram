-- =================================================================
-- HBSRESD: Response Data File
-- =================================================================
CREATE OR REPLACE TABLE HBSRESD (
    HSGUID          CHAR(36)      NOT NULL,       -- FK to HBSTRANS.HTGUID (= w_guid2)
    HSTS            TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP, -- Write timestamp
    HSBODY          CLOB(16M),                    -- Outbound JSON payload

    PRIMARY KEY(HSGUID)
);

LABEL ON TABLE HBSRESD IS 'BSL Response Data';
