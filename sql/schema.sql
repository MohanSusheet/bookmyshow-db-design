
-- ============================================================
-- Ticket Booking System
-- File: sql/schema.sql
-- Database: MySQL 8.0.16+ / InnoDB
--
-- Important:
--   1. Select the target database before executing this script.
--   2. CHECK constraints require MySQL 8.0.16+ for enforcement.
--   3. All DATETIME values are stored and interpreted as UTC.
--   4. This script creates tables; it does not drop existing data.
-- ============================================================

SET NAMES utf8mb4;
SET time_zone = '+00:00';


-- ============================================================
-- 1. CUSTOMER
-- ============================================================

CREATE TABLE `CUSTOMER` (
    `customer_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `customer_name` VARCHAR(150) NOT NULL,
    `customer_email` VARCHAR(254)
        CHARACTER SET utf8mb4
        COLLATE utf8mb4_0900_as_ci NOT NULL,
    `phone_number` VARCHAR(20) NULL,

    `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    `updated_at` DATETIME(6) NOT NULL
        DEFAULT CURRENT_TIMESTAMP(6)
        ON UPDATE CURRENT_TIMESTAMP(6),

    CONSTRAINT `pk_customer`
        PRIMARY KEY (`customer_id`),

    CONSTRAINT `uq_customer_email`
        UNIQUE (`customer_email`)
) ENGINE = InnoDB;


-- ============================================================
-- 2. THEATRE
-- ============================================================

CREATE TABLE `THEATRE` (
    `theatre_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `theatre_name` VARCHAR(150) NOT NULL,
    `address` VARCHAR(500) NOT NULL,
    `city` VARCHAR(100) NOT NULL,
    `state` VARCHAR(100) NULL,
    `postal_code` VARCHAR(15) NULL,
    `country_code` CHAR(2) NOT NULL DEFAULT 'IN',

    `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    `updated_at` DATETIME(6) NOT NULL
        DEFAULT CURRENT_TIMESTAMP(6)
        ON UPDATE CURRENT_TIMESTAMP(6),

    CONSTRAINT `pk_theatre`
        PRIMARY KEY (`theatre_id`)
) ENGINE = InnoDB;


-- ============================================================
-- 3. AUDITORIUM
-- ============================================================

CREATE TABLE `AUDITORIUM` (
    `auditorium_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `theatre_id` BIGINT UNSIGNED NOT NULL,
    `auditorium_name` VARCHAR(100) NOT NULL,

    `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),

    CONSTRAINT `pk_auditorium`
        PRIMARY KEY (`auditorium_id`),

    CONSTRAINT `uq_auditorium_theatre_name`
        UNIQUE (`theatre_id`, `auditorium_name`),

    CONSTRAINT `fk_auditorium_theatre`
        FOREIGN KEY (`theatre_id`)
        REFERENCES `THEATRE` (`theatre_id`)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT
) ENGINE = InnoDB;


-- ============================================================
-- 4. SEAT
-- ============================================================

CREATE TABLE `SEAT` (
    `seat_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `auditorium_id` BIGINT UNSIGNED NOT NULL,
    `seat_row` VARCHAR(8) NOT NULL,
    `seat_number` SMALLINT UNSIGNED NOT NULL,
    `seat_type` VARCHAR(30) NOT NULL,

    `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),

    CONSTRAINT `pk_seat`
        PRIMARY KEY (`seat_id`),

    CONSTRAINT `uq_seat_position`
        UNIQUE (`auditorium_id`, `seat_row`, `seat_number`),

    -- Required as a referenced composite key for seat/auditorium
    -- consistency in SHOW_SEAT_CLAIM and BOOKING_SEAT.
    CONSTRAINT `uq_seat_id_auditorium`
        UNIQUE (`seat_id`, `auditorium_id`),

    CONSTRAINT `chk_seat_number_positive`
        CHECK (`seat_number` > 0),

    CONSTRAINT `chk_seat_type`
        CHECK (`seat_type` IN ('EXECUTIVE', 'PREMIUM', 'RECLINER')),

    CONSTRAINT `fk_seat_auditorium`
        FOREIGN KEY (`auditorium_id`)
        REFERENCES `AUDITORIUM` (`auditorium_id`)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT
) ENGINE = InnoDB;


-- ============================================================
-- 5. MOVIE
-- ============================================================

CREATE TABLE `MOVIE` (
    `movie_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `movie_title` VARCHAR(255) NOT NULL,
    `duration_minutes` SMALLINT UNSIGNED NOT NULL,
    `language` VARCHAR(50) NOT NULL,
    `certification` VARCHAR(20) NULL,
    `release_date` DATE NULL,

    `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    `updated_at` DATETIME(6) NOT NULL
        DEFAULT CURRENT_TIMESTAMP(6)
        ON UPDATE CURRENT_TIMESTAMP(6),

    CONSTRAINT `pk_movie`
        PRIMARY KEY (`movie_id`),

    CONSTRAINT `chk_movie_duration`
        CHECK (`duration_minutes` > 0)
) ENGINE = InnoDB;


-- ============================================================
-- 6. SHOW
-- ============================================================

CREATE TABLE `SHOW` (
    `show_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `movie_id` BIGINT UNSIGNED NOT NULL,
    `auditorium_id` BIGINT UNSIGNED NOT NULL,

    `start_time` DATETIME(6) NOT NULL,
    `end_time` DATETIME(6) NOT NULL,

    `base_price` DECIMAL(10, 2) NOT NULL,
    `currency` CHAR(3) NOT NULL DEFAULT 'INR',

    `status` VARCHAR(20) NOT NULL DEFAULT 'SCHEDULED',

    `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    `updated_at` DATETIME(6) NOT NULL
        DEFAULT CURRENT_TIMESTAMP(6)
        ON UPDATE CURRENT_TIMESTAMP(6),

    CONSTRAINT `pk_show`
        PRIMARY KEY (`show_id`),

    -- Required as a referenced composite key for auditorium
    -- consistency in SHOW_SEAT_CLAIM and BOOKING_SEAT.
    CONSTRAINT `uq_show_id_auditorium`
        UNIQUE (`show_id`, `auditorium_id`),

    CONSTRAINT `chk_show_time_range`
        CHECK (`end_time` > `start_time`),

    CONSTRAINT `chk_show_base_price`
        CHECK (`base_price` >= 0),

    CONSTRAINT `chk_show_status`
        CHECK (`status` IN ('SCHEDULED', 'CANCELLED', 'COMPLETED')),

    CONSTRAINT `fk_show_movie`
        FOREIGN KEY (`movie_id`)
        REFERENCES `MOVIE` (`movie_id`)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT `fk_show_auditorium`
        FOREIGN KEY (`auditorium_id`)
        REFERENCES `AUDITORIUM` (`auditorium_id`)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    INDEX `idx_show_movie_start`
        (`movie_id`, `start_time`),

    INDEX `idx_show_auditorium_start`
        (`auditorium_id`, `start_time`)
) ENGINE = InnoDB;


-- ============================================================
-- 7. BOOKING
-- ============================================================

CREATE TABLE `BOOKING` (
    `booking_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `customer_id` BIGINT UNSIGNED NOT NULL,
    `show_id` BIGINT UNSIGNED NOT NULL,

    `status` VARCHAR(20) NOT NULL DEFAULT 'PENDING',

    -- Checkout amount snapshot. Must equal the sum of the
    -- associated seat-hold prices, validated transactionally.
    `total_amount` DECIMAL(10, 2) NOT NULL,
    `currency` CHAR(3) NOT NULL DEFAULT 'INR',

    -- Snapshot of the applicable refund cutoff for this booking.
    -- Initially calculated as show start minus 60 minutes.
    `refund_cutoff_at` DATETIME(6) NOT NULL,

    `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    `updated_at` DATETIME(6) NOT NULL
        DEFAULT CURRENT_TIMESTAMP(6)
        ON UPDATE CURRENT_TIMESTAMP(6),

    `confirmed_at` DATETIME(6) NULL,
    `expired_at` DATETIME(6) NULL,
    `cancelled_at` DATETIME(6) NULL,

    CONSTRAINT `pk_booking`
        PRIMARY KEY (`booking_id`),

    -- Required by composite foreign keys in child tables.
    CONSTRAINT `uq_booking_id_show`
        UNIQUE (`booking_id`, `show_id`),

    CONSTRAINT `chk_booking_status`
        CHECK (`status` IN ('PENDING', 'CONFIRMED', 'EXPIRED', 'CANCELLED')),

    CONSTRAINT `chk_booking_total_amount`
        CHECK (`total_amount` >= 0),

    CONSTRAINT `fk_booking_customer`
        FOREIGN KEY (`customer_id`)
        REFERENCES `CUSTOMER` (`customer_id`)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT `fk_booking_show`
        FOREIGN KEY (`show_id`)
        REFERENCES `SHOW` (`show_id`)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    INDEX `idx_booking_customer_created`
        (`customer_id`, `created_at`),

    INDEX `idx_booking_show`
        (`show_id`)
) ENGINE = InnoDB;


-- ============================================================
-- 8. SEAT_HOLD
-- ============================================================

CREATE TABLE `SEAT_HOLD` (
    `hold_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,

    `booking_id` BIGINT UNSIGNED NOT NULL,
    `show_id` BIGINT UNSIGNED NOT NULL,
    `seat_id` BIGINT UNSIGNED NOT NULL,

    `status` VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',

    -- Original expiry is retained even after conversion or release.
    `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    `expires_at` DATETIME(6) NOT NULL,

    -- Per-seat price snapshot at the time of hold creation.
    `price_at_hold` DECIMAL(10, 2) NOT NULL,

    `updated_at` DATETIME(6) NOT NULL
        DEFAULT CURRENT_TIMESTAMP(6)
        ON UPDATE CURRENT_TIMESTAMP(6),

    CONSTRAINT `pk_seat_hold`
        PRIMARY KEY (`hold_id`),

    -- Prevent duplicate holds for the same seat within one booking.
    CONSTRAINT `uq_seat_hold_booking_show_seat`
        UNIQUE (`booking_id`, `show_id`, `seat_id`),

    -- Required for the composite FK from SHOW_SEAT_CLAIM.
    CONSTRAINT `uq_seat_hold_reference`
        UNIQUE (`hold_id`, `booking_id`, `show_id`, `seat_id`),

    CONSTRAINT `chk_seat_hold_status`
        CHECK (`status` IN ('ACTIVE', 'CONVERTED', 'EXPIRED', 'RELEASED')),

    CONSTRAINT `chk_seat_hold_price`
        CHECK (`price_at_hold` >= 0),

    CONSTRAINT `chk_seat_hold_expiry`
        CHECK (`expires_at` >= `created_at`),

    CONSTRAINT `fk_seat_hold_booking_show`
        FOREIGN KEY (`booking_id`, `show_id`)
        REFERENCES `BOOKING` (`booking_id`, `show_id`)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT `fk_seat_hold_seat`
        FOREIGN KEY (`seat_id`)
        REFERENCES `SEAT` (`seat_id`)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    INDEX `idx_seat_hold_status_expiry`
        (`status`, `expires_at`),

    INDEX `idx_seat_hold_seat`
        (`seat_id`)
) ENGINE = InnoDB;


-- ============================================================
-- 9. SHOW_SEAT_CLAIM
-- ============================================================

CREATE TABLE `SHOW_SEAT_CLAIM` (
    `show_id` BIGINT UNSIGNED NOT NULL,
    `seat_id` BIGINT UNSIGNED NOT NULL,

    `auditorium_id` BIGINT UNSIGNED NOT NULL,
    `booking_id` BIGINT UNSIGNED NOT NULL,
    `hold_id` BIGINT UNSIGNED NOT NULL,

    `claim_type` VARCHAR(15) NOT NULL,

    `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),

    -- Non-null for temporary HOLD claims.
    -- Null for CONFIRMED claims.
    `expires_at` DATETIME(6) NULL,

    CONSTRAINT `pk_show_seat_claim`
        PRIMARY KEY (`show_id`, `seat_id`),

    CONSTRAINT `chk_claim_type`
        CHECK (
            (`claim_type` = 'HOLD' AND `expires_at` IS NOT NULL)
            OR
            (`claim_type` = 'CONFIRMED' AND `expires_at` IS NULL)
        ),

    CONSTRAINT `fk_claim_show_auditorium`
        FOREIGN KEY (`show_id`, `auditorium_id`)
        REFERENCES `SHOW` (`show_id`, `auditorium_id`)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT `fk_claim_seat_auditorium`
        FOREIGN KEY (`seat_id`, `auditorium_id`)
        REFERENCES `SEAT` (`seat_id`, `auditorium_id`)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT `fk_claim_booking_show`
        FOREIGN KEY (`booking_id`, `show_id`)
        REFERENCES `BOOKING` (`booking_id`, `show_id`)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    -- The hold, booking, show, and seat must all match.
    CONSTRAINT `fk_claim_hold_reference`
        FOREIGN KEY (`hold_id`, `booking_id`, `show_id`, `seat_id`)
        REFERENCES `SEAT_HOLD` (`hold_id`, `booking_id`, `show_id`, `seat_id`)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    INDEX `idx_claim_seat_auditorium`
        (`seat_id`, `auditorium_id`),

    INDEX `idx_claim_booking_show`
        (`booking_id`, `show_id`),

    INDEX `idx_claim_hold_reference`
        (`hold_id`, `booking_id`, `show_id`, `seat_id`),

    INDEX `idx_claim_show_auditorium`
        (`show_id`, `auditorium_id`)
) ENGINE = InnoDB;


-- ============================================================
-- 10. BOOKING_SEAT
-- ============================================================

CREATE TABLE `BOOKING_SEAT` (
    `booking_seat_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,

    `booking_id` BIGINT UNSIGNED NOT NULL,
    `show_id` BIGINT UNSIGNED NOT NULL,
    `seat_id` BIGINT UNSIGNED NOT NULL,

    -- Controlled redundancy used to enforce show/seat auditorium
    -- consistency through composite foreign keys.
    `auditorium_id` BIGINT UNSIGNED NOT NULL,

    `price_paid` DECIMAL(10, 2) NOT NULL,

    `status` VARCHAR(20) NOT NULL DEFAULT 'CONFIRMED',

    `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    `cancelled_at` DATETIME(6) NULL,

    CONSTRAINT `pk_booking_seat`
        PRIMARY KEY (`booking_seat_id`),

    -- A booking cannot contain the same seat more than once.
    -- Historical rows for different bookings remain possible.
    CONSTRAINT `uq_booking_seat_booking_show_seat`
        UNIQUE (`booking_id`, `show_id`, `seat_id`),

    CONSTRAINT `chk_booking_seat_price`
        CHECK (`price_paid` >= 0),

    CONSTRAINT `chk_booking_seat_status`
        CHECK (`status` IN ('CONFIRMED', 'CANCELLED')),

    CONSTRAINT `fk_booking_seat_booking_show`
        FOREIGN KEY (`booking_id`, `show_id`)
        REFERENCES `BOOKING` (`booking_id`, `show_id`)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT `fk_booking_seat_show_auditorium`
        FOREIGN KEY (`show_id`, `auditorium_id`)
        REFERENCES `SHOW` (`show_id`, `auditorium_id`)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT `fk_booking_seat_seat_auditorium`
        FOREIGN KEY (`seat_id`, `auditorium_id`)
        REFERENCES `SEAT` (`seat_id`, `auditorium_id`)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    INDEX `idx_booking_seat_booking_show`
        (`booking_id`, `show_id`),

    INDEX `idx_booking_seat_show_auditorium`
        (`show_id`, `auditorium_id`),

    INDEX `idx_booking_seat_seat_auditorium`
        (`seat_id`, `auditorium_id`)
) ENGINE = InnoDB;


-- ============================================================
-- 11. PAYMENT
-- ============================================================

CREATE TABLE `PAYMENT` (
    `payment_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `booking_id` BIGINT UNSIGNED NOT NULL,

    `payment_provider` VARCHAR(64) NOT NULL,
    `provider_payment_id` VARCHAR(150) NULL,

    -- Unique request key used when initiating/retrying provider calls.
    `idempotency_key` VARCHAR(150) NOT NULL,

    `amount` DECIMAL(10, 2) NOT NULL,
    `currency` CHAR(3) NOT NULL DEFAULT 'INR',

    `status` VARCHAR(20) NOT NULL DEFAULT 'PENDING',

    `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    `updated_at` DATETIME(6) NOT NULL
        DEFAULT CURRENT_TIMESTAMP(6)
        ON UPDATE CURRENT_TIMESTAMP(6),

    `succeeded_at` DATETIME(6) NULL,
    `failed_at` DATETIME(6) NULL,

    `failure_reason` VARCHAR(1000) NULL,

    CONSTRAINT `pk_payment`
        PRIMARY KEY (`payment_id`),

    CONSTRAINT `uq_payment_provider_reference`
        UNIQUE (`payment_provider`, `provider_payment_id`),

    CONSTRAINT `uq_payment_provider_idempotency`
        UNIQUE (`payment_provider`, `idempotency_key`),

    -- Required to ensure webhook/refund provider matches its payment.
    CONSTRAINT `uq_payment_id_provider`
        UNIQUE (`payment_id`, `payment_provider`),

    CONSTRAINT `chk_payment_amount`
        CHECK (`amount` > 0),

    CONSTRAINT `chk_payment_status`
        CHECK (`status` IN ('PENDING', 'SUCCESS', 'FAILED')),

    CONSTRAINT `fk_payment_booking`
        FOREIGN KEY (`booking_id`)
        REFERENCES `BOOKING` (`booking_id`)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    INDEX `idx_payment_booking_created`
        (`booking_id`, `created_at`)
) ENGINE = InnoDB;


-- ============================================================
-- 12. PAYMENT_WEBHOOK_EVENT
-- ============================================================

CREATE TABLE `PAYMENT_WEBHOOK_EVENT` (
    `webhook_event_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,

    `payment_id` BIGINT UNSIGNED NOT NULL,
    `payment_provider` VARCHAR(64) NOT NULL,

    `provider_event_id` VARCHAR(150) NOT NULL,
    `event_type` VARCHAR(100) NOT NULL,

    `payload` JSON NOT NULL,

    `processing_status` VARCHAR(20) NOT NULL DEFAULT 'RECEIVED',

    `received_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    `processed_at` DATETIME(6) NULL,

    `attempt_count` SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    `last_error` VARCHAR(2000) NULL,

    CONSTRAINT `pk_payment_webhook_event`
        PRIMARY KEY (`webhook_event_id`),

    CONSTRAINT `uq_webhook_provider_event`
        UNIQUE (`payment_provider`, `provider_event_id`),

    CONSTRAINT `chk_webhook_processing_status`
        CHECK (
            `processing_status` IN (
                'RECEIVED',
                'PROCESSING',
                'PROCESSED',
                'FAILED'
            )
        ),

    CONSTRAINT `fk_webhook_payment_provider`
        FOREIGN KEY (`payment_id`, `payment_provider`)
        REFERENCES `PAYMENT` (`payment_id`, `payment_provider`)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    INDEX `idx_webhook_processing_received`
        (`processing_status`, `received_at`),

    INDEX `idx_webhook_payment_provider`
        (`payment_id`, `payment_provider`)
) ENGINE = InnoDB;


-- ============================================================
-- 13. REFUND
-- ============================================================

CREATE TABLE `REFUND` (
    `refund_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,

    `payment_id` BIGINT UNSIGNED NOT NULL,
    `payment_provider` VARCHAR(64) NOT NULL,

    `provider_refund_id` VARCHAR(150) NULL,
    `idempotency_key` VARCHAR(150) NOT NULL,

    `amount` DECIMAL(10, 2) NOT NULL,
    `currency` CHAR(3) NOT NULL DEFAULT 'INR',

    `status` VARCHAR(20) NOT NULL DEFAULT 'PENDING',

    `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    `updated_at` DATETIME(6) NOT NULL
        DEFAULT CURRENT_TIMESTAMP(6)
        ON UPDATE CURRENT_TIMESTAMP(6),

    `processed_at` DATETIME(6) NULL,
    `failure_reason` VARCHAR(1000) NULL,

    CONSTRAINT `pk_refund`
        PRIMARY KEY (`refund_id`),

    -- Assignment scope: one full-refund record per payment.
    CONSTRAINT `uq_refund_payment`
        UNIQUE (`payment_id`),

    CONSTRAINT `uq_refund_provider_reference`
        UNIQUE (`payment_provider`, `provider_refund_id`),

    CONSTRAINT `uq_refund_provider_idempotency`
        UNIQUE (`payment_provider`, `idempotency_key`),

    CONSTRAINT `chk_refund_amount`
        CHECK (`amount` > 0),

    CONSTRAINT `chk_refund_status`
        CHECK (
            `status` IN ('PENDING', 'PROCESSING', 'SUCCESS', 'FAILED')
        ),

    CONSTRAINT `fk_refund_payment_provider`
        FOREIGN KEY (`payment_id`, `payment_provider`)
        REFERENCES `PAYMENT` (`payment_id`, `payment_provider`)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    INDEX `idx_refund_status_created`
        (`status`, `created_at`),
        
    INDEX `idx_refund_payment_provider`
        (`payment_id`, `payment_provider`)
) ENGINE = InnoDB;


-- ============================================================
-- 14. TICKET
-- ============================================================

CREATE TABLE `TICKET` (
    `ticket_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,

    `booking_seat_id` BIGINT UNSIGNED NOT NULL,
    `ticket_code` VARCHAR(100) NOT NULL,

    `status` VARCHAR(20) NOT NULL DEFAULT 'ISSUED',

    `issued_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    `cancelled_at` DATETIME(6) NULL,
    `used_at` DATETIME(6) NULL,

    CONSTRAINT `pk_ticket`
        PRIMARY KEY (`ticket_id`),

    CONSTRAINT `uq_ticket_booking_seat`
        UNIQUE (`booking_seat_id`),

    CONSTRAINT `uq_ticket_code`
        UNIQUE (`ticket_code`),

    CONSTRAINT `chk_ticket_status`
        CHECK (`status` IN ('ISSUED', 'CANCELLED', 'USED')),

    CONSTRAINT `fk_ticket_booking_seat`
        FOREIGN KEY (`booking_seat_id`)
        REFERENCES `BOOKING_SEAT` (`booking_seat_id`)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT
) ENGINE = InnoDB;


-- ============================================================
-- END OF SCHEMA
-- ============================================================

-- Notes:
--
-- The following business rules require transactional application
-- logic in addition to these declarative constraints:
--
-- 1. All-or-nothing multi-seat acquisition.
-- 2. Five-minute booking-level hold expiry.
-- 3. Valid SEAT_HOLD status when a claim is HOLD/CONFIRMED.
-- 4. Booking, payment, and ticket lifecycle transitions.
-- 5. Booking total = sum of its seat-hold prices.
-- 6. Payment amount/currency = booking amount/currency.
-- 7. Refund amount <= captured payment amount.
-- 8. Only one successful payment attempt may confirm a booking.
-- 9. Late successful payments must not reclaim released seats.
-- 10. Show overlap prevention, using auditorium row locking.
-- 11. Refund eligibility using BOOKING.refund_cutoff_at.
--
-- Never delete a confirmed claim through the expiry worker.
-- Never cascade-delete booking/payment/refund/ticket history.
