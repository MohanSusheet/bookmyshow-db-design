-- Structural and data validation checks
USE bookmyshow_db;

-- A. All 14 tables and their storage engines
SELECT TABLE_NAME, ENGINE
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_TYPE = 'BASE TABLE'
ORDER BY TABLE_NAME;

-- B. Primary and unique constraints
SELECT TABLE_NAME, CONSTRAINT_NAME, CONSTRAINT_TYPE
FROM information_schema.TABLE_CONSTRAINTS
WHERE CONSTRAINT_SCHEMA = DATABASE()
  AND CONSTRAINT_TYPE IN ('PRIMARY KEY', 'UNIQUE')
ORDER BY TABLE_NAME, CONSTRAINT_TYPE, CONSTRAINT_NAME;

-- C. Foreign keys, including composite-key column order
SELECT TABLE_NAME, CONSTRAINT_NAME, COLUMN_NAME,
       REFERENCED_TABLE_NAME, REFERENCED_COLUMN_NAME, ORDINAL_POSITION
FROM information_schema.KEY_COLUMN_USAGE
WHERE CONSTRAINT_SCHEMA = DATABASE()
  AND REFERENCED_TABLE_NAME IS NOT NULL
ORDER BY TABLE_NAME, CONSTRAINT_NAME, ORDINAL_POSITION;

-- D. CHECK constraints
SELECT tc.TABLE_NAME, tc.CONSTRAINT_NAME, cc.CHECK_CLAUSE
FROM information_schema.TABLE_CONSTRAINTS tc
JOIN information_schema.CHECK_CONSTRAINTS cc
  ON tc.CONSTRAINT_SCHEMA = cc.CONSTRAINT_SCHEMA
 AND tc.CONSTRAINT_NAME = cc.CONSTRAINT_NAME
WHERE tc.CONSTRAINT_SCHEMA = DATABASE()
  AND tc.CONSTRAINT_TYPE = 'CHECK'
ORDER BY tc.TABLE_NAME, tc.CONSTRAINT_NAME;

-- E. Index inventory
SELECT TABLE_NAME, INDEX_NAME, NON_UNIQUE,
       GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX SEPARATOR ', ') AS INDEX_COLUMNS
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA = DATABASE()
GROUP BY TABLE_NAME, INDEX_NAME, NON_UNIQUE
ORDER BY TABLE_NAME, INDEX_NAME;

-- F. Missing-primary-key check: expected result is zero rows
SELECT t.TABLE_NAME
FROM information_schema.TABLES t
LEFT JOIN information_schema.TABLE_CONSTRAINTS tc
  ON t.TABLE_SCHEMA = tc.CONSTRAINT_SCHEMA
 AND t.TABLE_NAME = tc.TABLE_NAME
 AND tc.CONSTRAINT_TYPE = 'PRIMARY KEY'
WHERE t.TABLE_SCHEMA = DATABASE()
  AND t.TABLE_TYPE = 'BASE TABLE'
  AND tc.CONSTRAINT_NAME IS NULL;

-- G. Sample-data counts: should return rows from all 14 tables
SELECT 'CUSTOMER' AS table_name, COUNT(*) AS row_count FROM CUSTOMER
UNION ALL SELECT 'THEATRE', COUNT(*) FROM THEATRE
UNION ALL SELECT 'AUDITORIUM', COUNT(*) FROM AUDITORIUM
UNION ALL SELECT 'SEAT', COUNT(*) FROM SEAT
UNION ALL SELECT 'MOVIE', COUNT(*) FROM MOVIE
UNION ALL SELECT 'SHOW', COUNT(*) FROM `SHOW`
UNION ALL SELECT 'BOOKING', COUNT(*) FROM BOOKING
UNION ALL SELECT 'SEAT_HOLD', COUNT(*) FROM SEAT_HOLD
UNION ALL SELECT 'SHOW_SEAT_CLAIM', COUNT(*) FROM SHOW_SEAT_CLAIM
UNION ALL SELECT 'BOOKING_SEAT', COUNT(*) FROM BOOKING_SEAT
UNION ALL SELECT 'PAYMENT', COUNT(*) FROM PAYMENT
UNION ALL SELECT 'PAYMENT_WEBHOOK_EVENT', COUNT(*) FROM PAYMENT_WEBHOOK_EVENT
UNION ALL SELECT 'REFUND', COUNT(*) FROM REFUND
UNION ALL SELECT 'TICKET', COUNT(*) FROM TICKET;

-- H. Business-level consistency spot checks
-- Confirmed booking totals should equal their booking-seat sum for this seed.
SELECT b.booking_id, b.total_amount, SUM(bs.price_paid) AS allocated_total
FROM BOOKING b
JOIN BOOKING_SEAT bs ON bs.booking_id = b.booking_id
WHERE b.status = 'CONFIRMED'
GROUP BY b.booking_id, b.total_amount;

-- Current claim rows should point to matching hold records and booking/show/seat.
SELECT c.show_id, c.seat_id, c.claim_type, h.status AS hold_status
FROM SHOW_SEAT_CLAIM c
JOIN SEAT_HOLD h
  ON h.hold_id = c.hold_id
 AND h.booking_id = c.booking_id
 AND h.show_id = c.show_id
 AND h.seat_id = c.seat_id;

-- I. Negative tests (run individually; each statement is expected to fail).
-- Use a disposable test database or rollback each test. Do not execute all
-- failing statements in one batch without handling errors.

-- Duplicate customer email (expect duplicate-key error):
-- INSERT INTO CUSTOMER(customer_name, customer_email)
-- VALUES ('Duplicate', 'AARAV.SHARMA@example.com');

-- Invalid seat type (expect CHECK constraint error):
-- INSERT INTO SEAT(auditorium_id, seat_row, seat_number, seat_type)
-- VALUES (1, 'Z', 99, 'BALCONY');

-- Invalid show time range (expect CHECK constraint error):
-- INSERT INTO `SHOW`(movie_id, auditorium_id, start_time, end_time, base_price)
-- VALUES (1, 1, '2026-12-03 12:00:00', '2026-12-03 11:00:00', 100);

-- Orphan auditorium (expect foreign-key error):
-- INSERT INTO AUDITORIUM(theatre_id, auditorium_name)
-- VALUES (999999, 'Invalid Screen');

-- Duplicate current claim for same show-seat (expect duplicate-key error):
-- INSERT INTO SHOW_SEAT_CLAIM
-- (show_id, seat_id, auditorium_id, booking_id, hold_id, claim_type, expires_at)
-- VALUES (1, 1, 1, 1, 1, 'CONFIRMED', NULL);
