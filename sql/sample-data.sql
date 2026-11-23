-- Sample data for Ticket Booking System
-- Run after schema.sql in the selected bookmyshow_db database.
-- Fixed IDs make the examples easy to query. Re-running this file will
-- conflict with existing rows; use a fresh assignment database.
SET NAMES utf8mb4;
SET time_zone = '+00:00';

START TRANSACTION;

INSERT INTO CUSTOMER
(customer_id, customer_name, customer_email, phone_number)
VALUES
(1, 'Aarav Sharma', 'aarav.sharma@example.com', '+919876500001'),
(2, 'Meera Iyer', 'meera.iyer@example.com', '+919876500002'),
(3, 'Kabir Verma', 'kabir.verma@example.com', '+919876500003');

INSERT INTO THEATRE
(theatre_id, theatre_name, address, city, state, postal_code, country_code)
VALUES
(1, 'CineSquare Central', 'Indirapuram Habitat Centre', 'Ghaziabad', 'Uttar Pradesh', '201014', 'IN'),
(2, 'Metro Screens', 'Pacific Mall, Sahibabad', 'Ghaziabad', 'Uttar Pradesh', '201010', 'IN');

INSERT INTO AUDITORIUM (auditorium_id, theatre_id, auditorium_name)
VALUES
(1, 1, 'Screen 1'),
(2, 1, 'Screen 2'),
(3, 2, 'Screen 1');

INSERT INTO SEAT (seat_id, auditorium_id, seat_row, seat_number, seat_type)
VALUES
(1, 1, 'A', 1, 'EXECUTIVE'),
(2, 1, 'A', 2, 'EXECUTIVE'),
(3, 1, 'A', 3, 'PREMIUM'),
(4, 1, 'A', 4, 'PREMIUM'),
(5, 1, 'B', 1, 'RECLINER'),
(6, 1, 'B', 2, 'RECLINER'),
(7, 1, 'B', 3, 'PREMIUM'),
(8, 1, 'B', 4, 'PREMIUM'),
(9, 2, 'A', 1, 'EXECUTIVE'),
(10, 2, 'A', 2, 'PREMIUM'),
(11, 3, 'A', 1, 'RECLINER'),
(12, 3, 'A', 2, 'PREMIUM');

INSERT INTO MOVIE
(movie_id, movie_title, duration_minutes, language, certification, release_date)
VALUES
(1, 'The Last Horizon', 142, 'Hindi', 'UA', '2026-10-30'),
(2, 'Beyond the Monsoon', 128, 'English', 'U', '2026-11-06'),
(3, 'City of Stars', 116, 'Hindi', 'UA', '2026-11-13');

-- Future showtimes relative to the assignment sample date; all times UTC.
INSERT INTO `SHOW`
(show_id, movie_id, auditorium_id, start_time, end_time, base_price, currency, status)
VALUES
(1, 1, 1, '2026-12-01 10:00:00.000000', '2026-12-01 12:22:00.000000', 220.00, 'INR', 'SCHEDULED'),
(2, 2, 1, '2026-12-01 14:00:00.000000', '2026-12-01 16:08:00.000000', 250.00, 'INR', 'SCHEDULED'),
(3, 3, 2, '2026-12-01 18:00:00.000000', '2026-12-01 19:56:00.000000', 200.00, 'INR', 'SCHEDULED'),
(4, 1, 3, '2026-12-02 11:00:00.000000', '2026-12-02 13:22:00.000000', 280.00, 'INR', 'SCHEDULED');

-- Booking 1: confirmed booking with two seats.
-- Booking 2: pending booking with one active held seat.
-- Booking 3: cancelled booking with successful payment and completed refund.
INSERT INTO BOOKING
(booking_id, customer_id, show_id, status, total_amount, currency, refund_cutoff_at,
 created_at, confirmed_at, expired_at, cancelled_at)
VALUES
(1, 1, 1, 'CONFIRMED', 470.00, 'INR', '2026-12-01 09:00:00.000000',
 '2026-11-23 08:00:00.000000', '2026-11-23 08:02:00.000000', NULL, NULL),
(2, 2, 1, 'PENDING', 220.00, 'INR', '2026-12-01 09:00:00.000000',
 '2026-11-23 08:10:00.000000', NULL, NULL, NULL),
(3, 3, 3, 'CANCELLED', 200.00, 'INR', '2026-12-01 17:00:00.000000',
 '2026-11-22 09:00:00.000000', '2026-11-22 09:02:00.000000', NULL, '2026-11-22 10:00:00.000000');

INSERT INTO SEAT_HOLD
(hold_id, booking_id, show_id, seat_id, status, created_at, expires_at, price_at_hold)
VALUES
(1, 1, 1, 1, 'CONVERTED', '2026-11-23 08:00:00.000000', '2026-11-23 08:05:00.000000', 220.00),
(2, 1, 1, 3, 'CONVERTED', '2026-11-23 08:00:00.000000', '2026-11-23 08:05:00.000000', 250.00),
(3, 2, 1, 2, 'ACTIVE', '2026-11-23 08:10:00.000000', '2026-11-23 08:15:00.000000', 220.00),
(4, 3, 3, 9, 'CONVERTED', '2026-11-22 09:00:00.000000', '2026-11-22 09:05:00.000000', 200.00);

-- Current claims only: confirmed claims and the currently active hold.
INSERT INTO SHOW_SEAT_CLAIM
(show_id, seat_id, auditorium_id, booking_id, hold_id, claim_type, created_at, expires_at)
VALUES
(1, 1, 1, 1, 1, 'CONFIRMED', '2026-11-23 08:00:00.000000', NULL),
(1, 3, 1, 1, 2, 'CONFIRMED', '2026-11-23 08:00:00.000000', NULL),
(1, 2, 1, 2, 3, 'HOLD', '2026-11-23 08:10:00.000000', '2026-11-23 08:15:00.000000');

INSERT INTO BOOKING_SEAT
(booking_seat_id, booking_id, show_id, seat_id, auditorium_id, price_paid, status, created_at, cancelled_at)
VALUES
(1, 1, 1, 1, 1, 220.00, 'CONFIRMED', '2026-11-23 08:02:00.000000', NULL),
(2, 1, 1, 3, 1, 250.00, 'CONFIRMED', '2026-11-23 08:02:00.000000', NULL),
(3, 3, 3, 9, 2, 200.00, 'CANCELLED', '2026-11-22 09:02:00.000000', '2026-11-22 10:00:00.000000');

INSERT INTO PAYMENT
(payment_id, booking_id, payment_provider, provider_payment_id, idempotency_key,
 amount, currency, status, created_at, succeeded_at, failed_at, failure_reason)
VALUES
(1, 1, 'DEMO_PAY', 'demo_pay_0001', 'booking-1-attempt-1', 470.00, 'INR', 'SUCCESS',
 '2026-11-23 08:01:00.000000', '2026-11-23 08:02:00.000000', NULL, NULL),
(2, 2, 'DEMO_PAY', NULL, 'booking-2-attempt-1', 220.00, 'INR', 'PENDING',
 '2026-11-23 08:11:00.000000', NULL, NULL, NULL),
(3, 3, 'DEMO_PAY', 'demo_pay_0003', 'booking-3-attempt-1', 200.00, 'INR', 'SUCCESS',
 '2026-11-22 09:01:00.000000', '2026-11-22 09:02:00.000000', NULL, NULL);

INSERT INTO PAYMENT_WEBHOOK_EVENT
(webhook_event_id, payment_id, payment_provider, provider_event_id, event_type, payload,
 processing_status, received_at, processed_at, attempt_count, last_error)
VALUES
(1, 1, 'DEMO_PAY', 'evt_demo_0001', 'payment.succeeded',
 JSON_OBJECT('demo', TRUE, 'payment_reference', 'demo_pay_0001'),
 'PROCESSED', '2026-11-23 08:02:00.000000', '2026-11-23 08:02:01.000000', 1, NULL),
(2, 3, 'DEMO_PAY', 'evt_demo_0003', 'payment.succeeded',
 JSON_OBJECT('demo', TRUE, 'payment_reference', 'demo_pay_0003'),
 'PROCESSED', '2026-11-22 09:02:00.000000', '2026-11-22 09:02:01.000000', 1, NULL);

INSERT INTO REFUND
(refund_id, payment_id, payment_provider, provider_refund_id, idempotency_key,
 amount, currency, status, created_at, processed_at, failure_reason)
VALUES
(1, 3, 'DEMO_PAY', 'demo_refund_0003', 'refund-payment-3', 200.00, 'INR', 'SUCCESS',
 '2026-11-22 10:01:00.000000', '2026-11-22 10:02:00.000000', NULL);

INSERT INTO TICKET
(ticket_id, booking_seat_id, ticket_code, status, issued_at, cancelled_at, used_at)
VALUES
(1, 1, 'DEMO-TKT-000001', 'ISSUED', '2026-11-23 08:02:00.000000', NULL, NULL),
(2, 2, 'DEMO-TKT-000002', 'ISSUED', '2026-11-23 08:02:00.000000', NULL, NULL),
(3, 3, 'DEMO-TKT-000003', 'CANCELLED', '2026-11-22 09:02:00.000000', '2026-11-22 10:00:00.000000', NULL);

COMMIT;
