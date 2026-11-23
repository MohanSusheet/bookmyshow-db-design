# BookMyShow — Database Normalization

## 1. Purpose

Database normalization organizes relational data to minimize unnecessary duplication and prevent insertion, update, and deletion anomalies.

For the BookMyShow ticket-booking system, normalization helps us maintain a consistent representation of:

- Movies, theatres, auditoriums, and physical seats.
- Shows and their schedules.
- Customers and bookings.
- Temporary seat holds and current seat ownership.
- Confirmed seat allocations and their prices.
- Payment attempts, webhook events, and tickets.

This document explains the normalization decisions behind the logical model and distinguishes those decisions from additional physical-design choices needed to handle concurrent bookings.

## 2. First Normal Form (1NF)

A relation satisfies First Normal Form when each attribute contains a single value from its intended domain and repeating groups are not stored in individual columns.

### Problematic design

Consider a booking table containing multiple seat identifiers in one field.

| booking_id | customer_name | movie_title | seats |
|---|---|---|---|
| 101 | Amit | Inception | A1, A2, A3 |
| 102 | Priya | Interstellar | B4, B5 |

The `seats` column stores a collection rather than one seat identifier.

This creates several problems:

- Individual seat identifiers cannot be validated through ordinary foreign keys.
- Searching for a particular seat requires parsing a string.
- Adding or removing a seat requires modifying the collection.
- Counting seats and enforcing seat-level constraints become more complicated.

### Design

We separate the booking from its seat allocations.

**BOOKING**

| booking_id | customer_id | show_id | status |
|---|---|---|---|
| 101 | 10 | 501 | CONFIRMED |
| 102 | 11 | 502 | CONFIRMED |

**BOOKING_SEAT**

| booking_seat_id | booking_id | show_id | seat_id | price_paid |
|---|---|---|---|---:|
| 1001 | 101 | 501 | 1 | 250.00 |
| 1002 | 101 | 501 | 2 | 250.00 |
| 1003 | 101 | 501 | 3 | 300.00 |
| 1004 | 102 | 502 | 4 | 200.00 |
| 1005 | 102 | 502 | 5 | 200.00 |

Each `BOOKING_SEAT` row represents one allocated seat.

**Result:** The design supports bookings containing multiple seats without storing repeating groups in a single field.

## 3. Second Normal Form (2NF)

A relation satisfies Second Normal Form when:

1. It satisfies 1NF.
2. Every non-key attribute depends on the whole of every candidate key, rather than only part of a composite candidate key.

### Example

Consider this hypothetical relation:

`SHOW_SEAT(show_id, seat_id, movie_title, seat_number, seat_type, price_paid)`

Suppose its candidate key is `(show_id, seat_id)`.

Some functional dependencies are:

- `show_id → movie_title`
- `seat_id → seat_number, seat_type`
- `(show_id, seat_id) → price_paid`

Here, `movie_title` depends only on `show_id`, while `seat_number` and `seat_type` depend only on `seat_id`.

These are partial dependencies on components of the composite key.

### Design

We separate these facts into their appropriate relations:

- `MOVIE` stores movie metadata.
- `SHOW` identifies a scheduled screening.
- `SEAT` stores physical seat details.
- `BOOKING_SEAT` records the seat allocated to a booking and the price charged.

This avoids repeatedly storing movie and physical-seat attributes for every screening or booking.

### Why retain `price_paid`?

The price charged for a confirmed seat is a transaction-specific fact.

The price configured for a show may change after a customer books a ticket. Therefore, the historical amount paid must be preserved in `BOOKING_SEAT.price_paid`.

It should not be reconstructed from the current show price.

## 4. Third Normal Form (3NF)

A relation satisfies Third Normal Form when it satisfies 2NF and non-key attributes do not depend transitively on a candidate key through other non-key attributes.

### Example

Consider a hypothetical relation:

`SHOW(show_id, movie_id, movie_title, auditorium_id, theatre_id, theatre_name, start_time)`

Its dependencies include:

- `show_id → movie_id, auditorium_id, start_time`
- `movie_id → movie_title`
- `auditorium_id → theatre_id`
- `theatre_id → theatre_name`

The movie title is determined by `movie_id`, and the theatre name is determined by `theatre_id`.

Repeating these attributes in every show row introduces unnecessary duplication.

### Design

We maintain separate relations:

- `MOVIE` stores movie information.
- `THEATRE` stores theatre information.
- `AUDITORIUM` identifies an auditorium and its parent theatre.
- `SHOW` stores screening and scheduling information.

Descriptive information can be retrieved with joins when required.

For example:

```sql
SELECT
    s.show_id,
    m.title AS movie_title,
    t.name AS theatre_name,
    a.name AS auditorium_name,
    s.start_time
FROM `SHOW` AS s
JOIN MOVIE AS m
    ON m.movie_id = s.movie_id
JOIN AUDITORIUM AS a
    ON a.auditorium_id = s.auditorium_id
JOIN THEATRE AS t
    ON t.theatre_id = a.theatre_id;
```

This retrieves related descriptive information without duplicating it in `SHOW`.

## 5. Functional Dependencies in the Logical Model

The following are the principal functional dependencies implied by our proposed model. They assume the relevant identifiers are primary keys.

| Relation | Functional dependency | Meaning |
|---|---|---|
| `CUSTOMER` | `customer_id → name, email, phone` | A customer identifier determines that customer's stored details. |
| `THEATRE` | `theatre_id → name, address, city` | A theatre identifier determines its details. |
| `AUDITORIUM` | `auditorium_id → theatre_id, name` | An auditorium identifier determines its parent theatre and name. |
| `SEAT` | `seat_id → auditorium_id, seat_number, seat_type` | A seat identifier determines its physical location and attributes. |
| `MOVIE` | `movie_id → title, duration_minutes, language, certification` | A movie identifier determines its metadata. |
| `SHOW` | `show_id → movie_id, auditorium_id, start_time, end_time, base_price, status` | A show identifier determines its scheduled screening details. |
| `BOOKING` | `booking_id → customer_id, show_id, status, created_at, confirmed_at` | A booking identifier determines its booking details. |
| `SEAT_HOLD` | `hold_id → booking_id, show_id, seat_id, status, created_at, expires_at` | A hold identifier determines a temporary-hold record. |
| `SHOW_SEAT_CLAIM` | `(show_id, seat_id) → booking_id, hold_id, claim_type, created_at, expires_at` | A show-seat pair determines its current claim, if one exists. |
| `BOOKING_SEAT` | `booking_seat_id → booking_id, show_id, seat_id, price_paid, status` | An allocation identifier determines its allocation record. |
| `PAYMENT` | `payment_id → booking_id, provider_reference, amount, status, created_at` | A payment identifier determines a payment attempt. |
| `PAYMENT_WEBHOOK_EVENT` | `webhook_event_id → payment_id, provider_event_id, event_type, received_at, processing_status` | A webhook-event identifier determines its recorded event. |
| `TICKET` | `ticket_id → booking_seat_id, ticket_code, status, issued_at` | A ticket identifier determines its issuance record. |

Additional candidate keys may exist. For example, a ticket code should be unique, and a provider event identifier should be unique within its provider's scope.

The final schema must define these candidate keys and their uniqueness rules explicitly.

## 6. Why Does BOOKING_SEAT Include show_id?

The logical booking relationship already determines the show:

`BOOKING_SEAT → BOOKING → SHOW`

Therefore, `show_id` is derivable from `booking_id`.

Adding `show_id` to `BOOKING_SEAT` introduces controlled redundancy. It is not strictly necessary to identify the allocation in the logical model.

We have nevertheless chosen to include it to make the show-seat relationship explicit and facilitate database-level integrity constraints.

This choice requires an important safeguard: the database must prevent a booking-seat row from referring to a show different from the show associated with its booking.

A foreign key on `booking_id` and another on `show_id` independently would not enforce that condition.

During physical schema design, we will establish a suitable composite-key and foreign-key strategy to enforce consistency.

This is a deliberate integrity-oriented design choice, not a claim that storing `show_id` is required for 3NF.

## 7. Why Do We Need SHOW_SEAT_CLAIM?

Normalization and concurrency control solve different problems.

A normalized design does not, by itself, prevent two customers from claiming the same seat concurrently.

We therefore introduce `SHOW_SEAT_CLAIM` as a physical-design mechanism.

### 7.1 SHOW_SEAT_CLAIM

This table represents current ownership of a seat for a show.

Its composite primary key is:

`(show_id, seat_id)`

Only one current claim can exist for a particular show-seat pair.

A claim can represent either:

- A temporary hold.
- A confirmed seat allocation.

The table is authoritative for current ownership.

### 7.2 SEAT_HOLD

`SEAT_HOLD` records the lifecycle of temporary holds.

It preserves information such as:

- Which booking attempt requested the hold.
- Which seat and show were involved.
- When the hold was created.
- When it expires.
- Whether it expired, was released, or was consumed by confirmation.

Expired hold records can remain for auditing without preventing future bookings.

### 7.3 BOOKING_SEAT

`BOOKING_SEAT` records the allocated seat, associated booking, show, historical status, and price paid.

It preserves the booking history even after a cancellation releases the current claim.

### 7.4 Why not combine everything into one table?

We need to distinguish three different facts:

1. A temporary hold was attempted.
2. A seat is currently claimed.
3. A seat was allocated to a booking.

These facts have different lifecycles.

Combining all of them into a single historical table would complicate the enforcement of uniqueness for current claims while retaining expired and cancelled records.

Separating these responsibilities provides a clearer design, provided that the tables are updated consistently.

## 8. Normalization Versus Physical Design

The introduction of `SHOW_SEAT_CLAIM` is a physical-design decision driven by concurrency, not a requirement of 1NF, 2NF, or 3NF.

The distinction is important:

| Concern | Primary mechanism |
|---|---|
| Avoid storing multiple seat identifiers in one field | Relational design and 1NF |
| Avoid partial dependencies | Relational design and 2NF |
| Avoid problematic transitive dependencies | Relational design and 3NF |
| Prevent conflicting current seat claims | Primary key or unique constraint on the claim table |
| Ensure a booking and its show are consistent | Foreign-key constraints |
| Release expired holds safely | Transactional application logic |
| Prevent double-booking during concurrent requests | Transactions, locking, and unique constraints |
| Process duplicate payment webhooks safely | Unique event identifiers and idempotent processing |
| Prevent overlapping shows in an auditorium | Appropriate scheduling validation and concurrency control |

The additional physical structures are justified by the booking system's operational requirements, not by normalization alone.

## 9. Transactional Integrity Requirements

The physical schema and application logic must enforce the following rules.

### Atomic multi-seat holds

When a customer requests several seats, all requested claims must be acquired successfully, or none of the claims acquired by that attempt may remain.

Rollback must never release another customer's claim.

### Five-minute expiry

A temporary hold expires if payment has not succeeded within five minutes.

Expired claims must be released safely. Expiry processing must verify the identity and state of the claim before removing it.

### Booking confirmation

Payment success must not automatically confirm a booking if its seats have already been released and reallocated.

The confirmation transaction must validate that the booking still owns the required claims.

### Cancellation

Cancelling a booking must release its current claims while preserving the historical booking and allocation records.

### Webhook idempotency

A payment-provider event must not apply the same logical state transition more than once.

The database must enforce the appropriate uniqueness of provider event identifiers, and event processing must be transactional.

### Auditorium consistency

Every claimed or allocated seat must belong to the auditorium in which the associated show is scheduled.

### Show scheduling

Two shows must not overlap in the same auditorium. This requires more than a simple foreign key.

## 10. Normalization Summary

The proposed logical model separates:

- Cinema catalog information from scheduled screenings.
- Physical seats from show-specific seat availability.
- Booking attempts from individual seat allocations.
- Temporary holds from confirmed allocations.
- Payment attempts from payment-provider events.
- Seat allocations from individual tickets.

These separations reduce duplication, make the relationships explicit, and preserve historical information.

The additional `SHOW_SEAT_CLAIM` table provides a mechanism for enforcing current seat ownership. Its correctness depends on appropriate database constraints and transactional logic, which will be finalized during physical schema design.