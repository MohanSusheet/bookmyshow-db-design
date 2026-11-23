# Ticket Booking System — Database Assignment

## Overview
A MySQL 8 / InnoDB relational database for a cinema ticket-booking workflow. The schema models customers, theatres, auditoriums, physical seats, movies, shows, bookings, temporary seat holds, current show-seat claims, confirmed booking seats, payment attempts, webhook events, refunds and tickets.

## Requirements
- MySQL 8.0.16 or later (project owner reports server 8.0.46).
- InnoDB.
- MySQL command-line client or MySQL Workbench.
- All `DATETIME(6)` values are treated as UTC.

## Project layout
```text
.
├── README.md
├── docs/
│   ├── database-design.md
│   ├── er-diagram.md
│   ├── er-diagram.png
│   ├── normalization.md
│   ├── KeysConstraintsAndIndices.md
│   ├── Step-3.4-Status-Values-and-Lifecycle-Transitions.md
│   ├── concurrency-design.md
│   └── load-test-plan.md
└── sql/
    ├── schema.sql
    ├── sample-data.sql
    ├── showtimes-query.sql
    └── validation-tests.sql
```

## Setup and execution
Create/select the database:
```sql
CREATE DATABASE bookmyshow_db
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_as_ci;
USE bookmyshow_db;
```

From the MySQL client, execute:
```sql
SOURCE /sql/schema.sql;
SOURCE /sql/sample-data.sql;
```
The sample data uses fixed primary-key values and is intended for a fresh schema. Do not rerun it over existing seed rows.

Run the showtimes query:
```sql
SOURCE /absolute/path/to/sql/showtimes-query.sql;
```
Edit `@search_city` and `@show_date` in that file as required.

Run structural validation:
```sql
SOURCE /absolute/path/to/sql/validation-tests.sql;
```
The negative-test statements are commented out intentionally. Execute them one at a time in a disposable database; each is expected to fail.

## Key design decisions
- A movie and a scheduled show are separate entities.
- A theatre contains auditoriums; an auditorium contains physical seats.
- Seat availability is scoped to `(show_id, seat_id)`.
- One booking can contain multiple seats.
- `SEAT_HOLD` preserves temporary hold history; `SHOW_SEAT_CLAIM` represents current ownership; `BOOKING_SEAT` records confirmed allocation history.
- The primary key on `SHOW_SEAT_CLAIM(show_id, seat_id)` prevents more than one current claim for a show-seat pair.
- Multiple payment attempts are allowed per booking.
- Provider webhook events are deduplicated by provider/event ID.
- Refunds are represented separately; this assignment schema permits one full-refund record per payment.
- `TICKET` is associated with an individual booking-seat allocation.

## Project status and limitations

- MySQL server version 8.0.46.
- All 14 tables created successfully using InnoDB.
- Metadata checks for primary/unique keys, foreign keys, CHECK constraints, indexes and missing primary keys returned expected results.
- Sample-data insertion and result inspection.
- Showtime-query execution and result inspection.
- Negative constraint tests.
- Concurrent booking tests and load tests.

Important: this repository contains a database schema, seed data, queries, validation scripts and design documentation. It does not include a running Java/Spring Boot or other application service, a payment-provider integration, a background expiry worker, or an executed load-test report. Booking lifecycle rules that cannot be expressed by constraints are documented as transaction/application responsibilities.