-- =================================================================
-- HBSTRANS: Transaction Master File
-- =================================================================
CREATE OR REPLACE TABLE HBSTRANS (
    HTGUID          CHAR(36)      NOT NULL,                           -- Primary Key: The unique GUID for this transaction
    HTRQPGUID       CHAR(36)      NOT NULL WITH DEFAULT '',           -- Request's Parent GUID (for searching)
    HTRQAGUID       CHAR(36)      NOT NULL WITH DEFAULT '',           -- Request's Activity GUID (for searching)
    HTTYPE          CHAR(10)      NOT NULL WITH DEFAULT '',          -- Transaction Type ('INCOMING', 'OUTGOING')
    HTSNAME         VARCHAR(40)   NOT NULL WITH DEFAULT '',           -- Service Name (e.g., GetAcctDetail)
    HTPNAME         CHAR(10)      NOT NULL WITH DEFAULT '',           -- Program Name (e.g., HBSCHILD1, HBSPUSH)
    HTRCVTS         TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP, -- Timestamp when the request was first received
    HTSNDTS         TIMESTAMP     NOT NULL DEFAULT '0001-01-01-00.00.00.000000', -- Timestamp when the final response was sent (sentinel = not yet sent)
    HTRCVSTS        CHAR(1)       NOT NULL WITH DEFAULT '',          -- Receive Status (P:Processing, C:Complete, E:Error, N:N/A)
    HTSNDSTS        CHAR(1)       NOT NULL WITH DEFAULT '',          -- Send Status (P:Processing, C:Complete, E:Error, N:N/A)
    HTATTEMPTS      SMALLINT      NOT NULL DEFAULT 0,                 -- Retry attempts for sending a response
    HTREQHDR        VARCHAR(1024) NOT NULL WITH DEFAULT '',           -- Inbound HTTP request header
    HTRESHDR        VARCHAR(1024) NOT NULL WITH DEFAULT '',           -- Outbound HTTP response header
    HTADDTS         TIMESTAMP     NOT NULL 
                                  DEFAULT CURRENT_TIMESTAMP Implicitly Hidden, -- Row add timestamp
    HTMNTTS         TIMESTAMP     NOT NULL 
                                  for each row on update as row change timestamp
                                  Implicitly Hidden, -- Row maintenance timestamp

    PRIMARY KEY(HTGUID)
);

LABEL ON TABLE HBSTRANS IS 'BSL Transaction Master';
