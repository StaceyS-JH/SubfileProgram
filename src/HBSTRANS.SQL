-- =================================================================
-- HBSTRANS: Transaction Master File
-- =================================================================
CREATE OR REPLACE TABLE HBSTRANS (
    HTGUID          CHAR(36)      NOT NULL,                           -- Primary Key: The unique GUID for this transaction
    HTRQPGUID       CHAR(36)      NOT NULL WITH DEFAULT '',           -- Request's Parent GUID (for searching)
    HTRQAGUID       CHAR(36)      NOT NULL WITH DEFAULT '',           -- Request's Activity GUID (for searching)
    HTTYPE          CHAR(10)      NOT NULL WITH DEFAULT '',           -- Transaction Type ('IN', 'OUT')
    HTSNAME         VARCHAR(40)   NOT NULL WITH DEFAULT '',           -- Service Name (e.g., GetAcctDetail)
    HTPNAME         CHAR(10)      NOT NULL WITH DEFAULT '',           -- Program Name (e.g., HBSCHILD1, HBSPUSH)
    HTREQTS         TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP, -- Timestamp when the request was created/received
    HTRESTS         TIMESTAMP     NOT NULL DEFAULT '0001-01-01-00.00.00.000000', -- Timestamp when the response was sent/received (sentinel = not yet)
    HTREQSTS        CHAR(1)       NOT NULL WITH DEFAULT '',           -- Request Status (IN: received state; OUT: queued state)
    HTRESSTS        CHAR(1)       NOT NULL WITH DEFAULT '',           -- Response Status (IN: sent state; OUT: push result)
    HTATTEMPTS      SMALLINT      NOT NULL DEFAULT 0,                 -- Retry attempts (OUT: push retries)
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
