-- =================================================================
-- HBSTRANS: Transaction Master File
-- =================================================================
CREATE OR REPLACE TABLE HBSTRANS (
    HTGUID          CHAR(36)      NOT NULL,       -- Primary Key: The unique GUID for this transaction
    HTRQPGUID       CHAR(36),                     -- Request's Parent GUID (for searching)
    HTRQAGUID       CHAR(36),                     -- Request's Activity GUID (for searching)
    HTTYPE          VARCHAR(10)   NOT NULL,       -- Transaction Type ('INCOMING', 'OUTGOING')
    HTSNAME         VARCHAR(40)   NOT NULL WITH DEFAULT '',  -- Service Name (e.g., GetAcctDetail)
    HTPNAME         CHAR(10)      NOT NULL WITH DEFAULT '',  -- Program Name (e.g., HBSCHILD1, HBSPUSH)
    HTRCVTS         TIMESTAMP,                    -- Timestamp when the request was first received
    HTSNDTS         TIMESTAMP,                    -- Timestamp when the final response was sent
    HTRCVSTS        CHAR(1)       NOT NULL,       -- Receive Status (P:Processing, C:Complete, E:Error, N:N/A)
    HTSNDSTS        CHAR(1)       NOT NULL,       -- Send Status (P:Processing, C:Complete, E:Error, N:N/A)
    HTATTEMPTS      SMALLINT      DEFAULT 0,      -- Retry attempts for sending a response
    HTRQHEADER      VARCHAR(1024),                -- Inbound HTTP request header
    HTSNDHEADER     VARCHAR(1024),                -- Outbound HTTP response header
    HTADDTS         TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP, -- Row add timestamp
    HTMNTTS         TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP, -- Row maintenance timestamp

    PRIMARY KEY(HTGUID)
);

LABEL ON TABLE HBSTRANS IS 'BSL Transaction Master';
