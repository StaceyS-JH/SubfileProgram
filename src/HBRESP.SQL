-- =================================================================
-- HBRESP: Response Data File
-- =================================================================
CREATE OR REPLACE TABLE HBRESP (
    HSGUID          CHAR(36)      NOT NULL,       -- FK to HBSTRANS.HTGUID (= w_guid2)
    HSBODY          CLOB(16M),                    -- Outbound JSON payload

    PRIMARY KEY(HSGUID)
);

LABEL ON TABLE HBRESP IS 'BSL Response Data';
