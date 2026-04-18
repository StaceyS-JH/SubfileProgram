-- =================================================================
-- HBRESP: Response Data File
-- =================================================================
CREATE OR REPLACE TABLE HBRESP (
    HSGUID          CHAR(36)      NOT NULL,       -- FK to HBSTRANS.HTGUID (= w_guid2)
    HSATTMPT        NUMERIC(3,0)  NOT NULL WITH DEFAULT 0, -- Retry attempt number
    HSHEADER        VARCHAR(1024),                -- Full outbound HTTP header
    HSBODY          CLOB(2M),                     -- Outbound JSON payload

    PRIMARY KEY(HSGUID)
);

LABEL ON TABLE HBRESP IS 'BSL Response Data';
