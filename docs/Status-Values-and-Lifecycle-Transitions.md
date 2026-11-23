# Step 3.4 — Status Values and Lifecycle Transitions

## 1. Purpose

This document records the status values, allowed lifecycle transitions, cancellation rules, and refund-eligibility policy agreed for the BookMyShow-style ticket-booking database assignment.

**Database target:** MySQL 8+ with InnoDB.

The design keeps booking, payment, and refund lifecycles separate. Related operations must be coordinated through reliable transactional workflows.

---

## 2. Booking Statuses

The `BOOKING` entity will use these status values:

| Status | Meaning |
|---|---|
| `PENDING` | Booking has been created and its selected seats are temporarily held while payment is completed. |
| `CONFIRMED` | Payment succeeded and the booking's seat claims were successfully confirmed. |
| `EXPIRED` | The booking's temporary seat hold expired before confirmation. |
| `CANCELLED` | The booking was cancelled by the customer or system. |

### 2.1 Allowed transitions

| Current status | Next status | Condition / trigger |
|---|---|---|
| — | `PENDING` | A new booking is created and the required seats are held. |
| `PENDING` | `CONFIRMED` | Payment succeeds and the booking's seat claims are still valid and can be confirmed. |
| `PENDING` | `EXPIRED` | The five-minute seat-hold period expires before the booking is confirmed. |
| `PENDING` | `CANCELLED` | The customer or system cancels the pending booking. |
| `CONFIRMED` | `CANCELLED` | The customer cancels the confirmed booking before showtime, subject to the cancellation policy. |

All transitions not listed above are disallowed.

In particular:
- An `EXPIRED` booking cannot become `CONFIRMED` or `PENDING` again.
- A `CANCELLED` booking cannot become `CONFIRMED` or `PENDING` again.
- A customer who wants to retry after expiry or cancellation must create a new booking.
- A failed payment attempt does not, by itself, change the booking status to `EXPIRED` or `CANCELLED`. The customer may retry payment while the seat hold remains valid.

A payment-success notification arriving after the booking's seat claims have expired or been released must not automatically confirm the booking. The system must reconcile the payment safely (for example, by initiating a refund where appropriate) without taking seats that may have been allocated to another customer.

---

## 3. Confirmed-Booking Cancellation Policy

Confirmed bookings are cancellable, subject to a configurable cutoff before the show's start time.

### 3.1 Agreed policy

The initial business-policy value is:

**Cancellation cutoff: 60 minutes before showtime.**

A customer may cancel a confirmed booking at any time before the show starts. Refund eligibility depends on whether cancellation occurs strictly before the cutoff.

Let:
- `show_start_time` = scheduled start time of the show.
- `cancellation_time` = time at which the cancellation is accepted.
- `cancellation_cutoff_minutes` = configured policy value, initially `60`.

A booking is eligible for a refund only when:

```text
cancellation_time < show_start_time - INTERVAL cancellation_cutoff_minutes MINUTE
```

**A cancellation made exactly 60 minutes before showtime is not eligible for a refund.**

### 3.2 Policy outcomes

| Cancellation timing | Cancellation allowed? | Refund eligible? |
|---|---:|---:|
| More than 60 minutes before showtime | Yes | Yes |
| Exactly 60 minutes before showtime | Yes | No |
| Less than 60 minutes before showtime, but before showtime | Yes | No |
| At or after showtime | No | No |

The 60-minute value is a business-policy setting, not a hardcoded database constraint. Keeping it configurable allows the business to change the cutoff without redesigning the schema.

The cancellation service evaluates eligibility using the show's scheduled start time and the accepted cancellation timestamp. The implementation should use a consistent server-side time source and timezone convention.

---

## 4. Separate Booking, Payment, and Refund Lifecycles

Booking status, payment status, and refund status represent different business concerns and must not be combined into one status column.

### 4.1 Booking lifecycle

The booking lifecycle uses:
- `PENDING`
- `CONFIRMED`
- `EXPIRED`
- `CANCELLED`

### 4.2 Payment lifecycle

Each payment attempt has its own status. The agreed initial payment statuses are:
- `PENDING`
- `SUCCESS`
- `FAILED`

A booking may have multiple payment attempts, including retries after a failed attempt. Each attempt is represented by a separate `PAYMENT` record.

### 4.3 Refund lifecycle

Refund processing is tracked independently from booking cancellation. The agreed conceptual refund statuses are:
- `NOT_APPLICABLE`
- `PENDING`
- `SUCCESS`
- `FAILED`

Examples:
- A booking may be `CANCELLED` while its refund is still `PENDING`.
- A booking may be `CANCELLED` with refund status `NOT_APPLICABLE` because it was cancelled inside the one-hour no-refund window.
- A refund may fail even though the booking cancellation itself was accepted.

The exact physical representation of refunds (for example, a separate refund table versus refund attributes associated with a payment) remains a schema-design decision to finalize before DDL implementation. The lifecycles must remain logically independent either way.

---

## 5. Responsibilities During Cancellation

Accepting a cancellation involves more than updating `BOOKING.status`.

The cancellation workflow must coordinate the following:

1. Validate that the booking is currently `CONFIRMED`.
2. Validate that the show has not started.
3. Calculate refund eligibility using the configured cutoff.
4. Change the booking status to `CANCELLED`.
5. Release the booking's confirmed seat claims so those seats can become available for other bookings.
6. If eligible, initiate refund processing and track its result independently.
7. If not eligible, record that no refund is applicable.

Database changes belonging to the same local operation should be performed transactionally. An external payment-provider call cannot participate in the MySQL transaction; refund initiation therefore needs reliable asynchronous processing, retry handling, and idempotency.

Cancellation must also be coordinated with concurrent booking and seat-claim operations. The implementation must prevent two customers from owning the same show-seat claim and ensure cancellation and seat reallocation do not produce inconsistent ownership.

---

## 6. Database Enforcement Versus Application Logic

The database should enforce integrity rules that can be expressed reliably through primary keys, foreign keys, unique constraints, and supported `CHECK` constraints.

Lifecycle transition rules and time-dependent business rules require more than a simple static constraint:
- Allowed booking status transitions must be enforced by the application workflow (or a carefully designed database procedure/trigger if the implementation chooses that approach).
- Refund eligibility depends on the cancellation timestamp, show start time, and configurable policy value; it belongs in the cancellation business logic.
- Seat-claim release and booking cancellation must be coordinated transactionally.
- External refund processing requires asynchronous, retryable, idempotent handling.

A status column's allowed values alone do not guarantee that a row follows a valid transition sequence.

---

## 7. Decisions Finalized in This Step

| Area | Agreed decision |
|---|---|
| Database | MySQL 8+ with InnoDB |
| Booking statuses | `PENDING`, `CONFIRMED`, `EXPIRED`, `CANCELLED` |
| Initial booking status | `PENDING` |
| Successful confirmation | Only after payment succeeds and seat claims are still valid |
| Hold expiry | A pending booking becomes `EXPIRED` when its five-minute hold expires without confirmation |
| Failed payment | Does not automatically expire or cancel the booking; payment retry is possible while the hold remains valid |
| Pending cancellation | A pending booking may become `CANCELLED` |
| Confirmed cancellation | Confirmed bookings may be cancelled before showtime |
| Cancellation cutoff | Configurable; initially 60 minutes before showtime |
| Refund boundary | Refund only if cancellation is strictly earlier than showtime minus the configured cutoff |
| Exactly at cutoff | Cancellation is allowed, but refund is not eligible |
| After showtime | Cancellation is not permitted |
| Refund lifecycle | Separate from booking and payment lifecycles |
| Seat claims on cancellation | Confirmed seat claims must be released as part of the coordinated cancellation workflow |
| Late payment success | Must not reclaim seats after the original claims have been released; payment must be reconciled safely |

---

## 8. Not Yet Finalized

The following items belong to the next seat-hold lifecycle discussion and are intentionally not treated as finalized here:

- Exact `SEAT_HOLD.status` values and allowed transitions.
- Whether expired hold records are updated in place and retained as history (the current design direction is to retain history).
- Exact mechanism and timing for releasing expired rows from `SHOW_SEAT_CLAIM`.
- Detailed handling of a payment-success event racing with hold expiry.
- Exact physical schema for refund records and refund attempts.

These decisions should be settled before finalizing the corresponding DDL and transaction workflows.


# Step 3.5–3.12: Remaining Design Decisions

## Purpose

This document consolidates the remaining database and application design decisions for the BookMyShow-style ticket booking system.

The objective is to finalize the booking, seat-hold, payment, refund, ticketing, concurrency, and show-scheduling workflows before beginning SQL implementation.

### Database target

- MySQL 8+
- InnoDB storage engine
- Transactional operations for booking, payment confirmation, expiry, and cancellation
- UTC timestamps for persistent data

---

# Step 3.5 – Seat Hold Lifecycle and Expiry

## 3.5.1 Seat Hold Statuses

A `SEAT_HOLD` represents the temporary reservation of an individual seat as part of a booking.

The following statuses are finalized:

| Status | Meaning |
|---|---|
| `ACTIVE` | Seat is temporarily held for a pending booking. |
| `CONVERTED` | Temporary hold has been converted into a confirmed booking allocation. |
| `EXPIRED` | Hold expired because the booking was not confirmed within the allowed time. |
| `RELEASED` | Hold was explicitly released before expiry, such as when a pending booking was cancelled. |

### Allowed transitions

```text
                 ┌───────────┐
                 │   ACTIVE  │
                 └─────┬─────┘
                       |
          ┌────────────┼────────────┐
          |            |            |
          v            v            v
     CONVERTED       EXPIRED      RELEASED
```

Terminal states:

- `CONVERTED`
- `EXPIRED`
- `RELEASED`

A terminal hold cannot become active again.

A converted hold remains `CONVERTED` even if the confirmed booking is subsequently cancelled. The hold records the historical conversion; cancellation is represented through the booking and booking-seat lifecycles.

## 3.5.2 Booking-Level Hold Policy

A booking can contain multiple seats. All seats belonging to the same booking must be held and expired together.

Final decisions:

1. A booking has a five-minute hold duration.
2. One `SEAT_HOLD` row is created for each seat in the booking.
3. All hold rows belonging to a booking share the same expiry timestamp.
4. The expiry timestamp is calculated using database time.
5. The booking is confirmed only when all its seat holds are valid.
6. Partial expiry or partial confirmation is not permitted.

For example, if a customer selects three seats, all three must be held successfully. If one seat cannot be acquired, the entire acquisition operation fails.

## 3.5.3 Booking Expiry Behaviour

When a pending booking expires:

- `BOOKING.status` changes from `PENDING` to `EXPIRED`.
- All associated `ACTIVE` seat holds change to `EXPIRED`.
- All corresponding temporary claims are deleted from `SHOW_SEAT_CLAIM`.
- No partial seat release is permitted.

The expiry operation must execute within a single database transaction.

## 3.5.4 Expiry Execution Strategy

A hybrid expiry strategy is adopted.

**Request-time expiry handling**

When a customer attempts to acquire a seat, the system checks whether an existing claim has expired. If it belongs to an expired booking, the system processes that booking's expiry before making the seat available.

**Background expiry worker**

A periodic background worker scans for pending bookings whose hold expiry timestamp has passed and processes them.

The worker is responsible for cleaning up abandoned holds, but it is not the sole mechanism for making expired seats available.

Both mechanisms must invoke the same transaction-safe expiry operation.

Additional rules:

- Database time is the source of truth.
- Conditional updates and row-level locks must prevent conflicting expiry and confirmation operations.
- The worker must not delete confirmed claims.
- `SKIP LOCKED` may be used for batch processing where supported by the deployed MySQL version.

## 3.5.5 Late Payment Webhooks

A payment provider may report a successful payment after the booking's hold has expired.

The following rule is adopted:

**The validity of the booking's seat claims at confirmation time takes precedence over the payment provider's payment timestamp.**

If the booking has expired or its claims have been released:

1. The successful payment must still be recorded.
2. The expired booking must not be reactivated.
3. Previously released seats must not be reclaimed automatically.
4. The payment must be reconciled.
5. A refund should normally be initiated for the successful payment.

This prevents a late webhook from taking seats away from another customer.

## 3.5.6 Multi-Seat Acquisition

Acquiring multiple seats is an all-or-nothing operation.

The system must:

1. Begin a database transaction.
2. Validate the requested seats.
3. Handle any expired claims encountered.
4. Attempt to insert all required temporary claims.
5. Create the corresponding seat-hold records.
6. Commit only if every requested seat is successfully acquired.

If any seat is unavailable or a concurrent transaction wins the claim:

- Roll back the entire acquisition.
- Do not retain partial holds.
- Do not delete claims belonging to another booking.

The application must not rely only on a preliminary availability query. Database uniqueness constraints must arbitrate concurrent acquisition attempts.

---

# Step 3.6 – SHOW_SEAT_CLAIM Design

## 3.6.1 Purpose

`SHOW_SEAT_CLAIM` represents the current ownership of a physical seat for a particular show.

It is not a historical table.

The table prevents two customers from holding or booking the same seat for the same show.

### Primary key

```text
(show_id, seat_id)
```

This guarantees that only one current claim can exist for a particular show-seat combination.

## 3.6.2 Claim Types

The `claim_type` column supports:

| Claim type | Meaning |
|---|---|
| `HOLD` | Seat is temporarily held by a pending booking. |
| `CONFIRMED` | Seat belongs to a confirmed booking. |

### Column behaviour

| Claim type | `hold_id` | `expires_at` |
|---|---|---|
| `HOLD` | Not null | Not null |
| `CONFIRMED` | Not null | Null |

The `hold_id` is retained after conversion to maintain a direct audit relationship between the current claim and the original seat hold.

A row-level CHECK constraint can enforce the relationship between `claim_type` and `expires_at`.

## 3.6.3 Relationship Validation

The following consistency rules must hold:

- A `HOLD` claim references an `ACTIVE` seat hold.
- A `CONFIRMED` claim references a `CONVERTED` seat hold.
- The referenced hold must belong to the same booking, show, and seat as the claim.
- The booking must belong to the same show.

Composite foreign keys should enforce the relationships that can be represented structurally.

Cross-table status consistency cannot be enforced through a normal MySQL CHECK constraint. It must be maintained transactionally by the application.

## 3.6.4 Claim Conversion

When payment succeeds and the booking is eligible for confirmation:

- The claim's `claim_type` changes from `HOLD` to `CONFIRMED`.
- `expires_at` becomes `NULL`.
- The associated seat hold changes from `ACTIVE` to `CONVERTED`.
- The booking changes from `PENDING` to `CONFIRMED`.

All changes must commit together.

## 3.6.5 Confirmed Claim Release

Confirmed claims may only be released through the authorized booking-cancellation workflow.

The expiry worker must never remove a confirmed claim.

When a confirmed booking is cancelled:

1. Change the booking status to `CANCELLED`.
2. Change all associated booking-seat records to `CANCELLED`.
3. Invalidate the associated tickets.
4. Delete all corresponding confirmed claims.
5. Preserve the converted seat-hold records.
6. Create a refund request if the booking satisfies the refund policy.

All database changes must be transactional.

---

# Step 3.7 – Payment, Webhook, and Refund Design

## 3.7.1 Payment Attempts

A booking may have multiple payment attempts.

This supports retrying payment after failures without overwriting the previous attempt.

The `PAYMENT` table must therefore not have a unique constraint on `booking_id`.

### Payment statuses

| Status | Meaning |
|---|---|
| `INITIATED` | Payment attempt has been created. |
| `PENDING` | Payment provider is processing the request. |
| `SUCCESS` | Payment has been successfully captured. |
| `FAILED` | Payment attempt has failed. |

### Allowed transitions

```text
NEW
 |
 v
INITIATED
 |
 v
PENDING
 |       \
 v        v
SUCCESS  FAILED
```

A failed payment attempt is terminal. A retry creates a new payment record.

Out-of-order provider notifications must not allow an older failure event to overwrite a successful payment.

## 3.7.2 Booking Confirmation Through Payment

Payment success is necessary but not sufficient for booking confirmation.

The system must verify that:

- The booking is still `PENDING`.
- All required seat holds are still `ACTIVE`.
- All corresponding claims still exist.
- All claims are still valid and unexpired.
- The payment amount and booking amount are consistent.

Only then can the booking be confirmed.

The booking row must be locked during confirmation to prevent concurrent payment attempts from confirming the same booking independently.

If multiple payment attempts are successfully captured for one booking, only one may be applied to the booking. Additional successful captures must be reconciled and refunded.

## 3.7.3 Payment Webhook Idempotency

Payment providers may deliver the same webhook multiple times.

The following unique constraint is required:

```text
UNIQUE(payment_provider, provider_event_id)
```

The `PAYMENT_WEBHOOK_EVENT` table stores incoming events and their processing status.

### Webhook statuses

| Status | Meaning |
|---|---|
| `RECEIVED` | Event has been received and persisted. |
| `PROCESSING` | Event is currently being processed. |
| `PROCESSED` | Event has been successfully applied. |
| `FAILED` | Processing failed and may require retry or investigation. |

### Processing rules

1. Verify the authenticity/signature of the incoming webhook.
2. Persist the event using its provider event ID.
3. If the event already exists, do not apply its business effect again.
4. Lock the relevant records before applying state transitions.
5. Apply only valid payment and booking transitions.
6. Mark the event as processed in the same database transaction as the corresponding business-state changes.

Webhook idempotency must protect business operations, not merely prevent duplicate event insertion.

Transient failures should be retryable.

## 3.7.4 Refund Lifecycle

Refunds are represented through a separate `REFUND` table.

A refund is not the same as booking cancellation or payment failure.

### Refund statuses

| Status | Meaning |
|---|---|
| `PENDING` | Refund request has been created. |
| `PROCESSING` | Refund is being processed by the payment provider. |
| `SUCCESS` | Refund has been completed. |
| `FAILED` | Refund attempt has failed. |

### Refund scope

For this assignment:

- Only full refunds are supported.
- Partial refunds are out of scope.
- One full-refund request is permitted per successful payment.
- `UNIQUE(payment_id)` enforces this rule.

The refund amount must not exceed the captured payment amount. This is a cross-table business rule and must be validated transactionally.

### Recommended refund columns

- `refund_id`
- `payment_id`
- `amount`
- `status`
- `provider_refund_id`
- `idempotency_key`
- `created_at`
- `updated_at`
- Optional error details

Constraints:

- `payment_id` is unique.
- `provider_refund_id` is unique when populated.
- `idempotency_key` is unique.

## 3.7.5 Refund Processing Strategy

External payment-provider calls must not be made while holding database transaction locks.

The adopted workflow is:

1. Create a durable refund record with status `PENDING`.
2. Commit the database transaction.
3. A background worker picks up pending refund requests.
4. The worker calls the payment provider using the stable idempotency key.
5. The provider response is persisted.
6. The refund status is updated accordingly.

Retries must reuse the same idempotency key.

A transactional outbox is a stronger production-grade option. For this assignment, a durable pending refund record and retry worker are sufficient.

## 3.7.6 Late Successful Payments

A successful payment received after booking expiry is not treated as a normal booking confirmation.

The system must:

- Preserve the successful payment record.
- Keep the booking expired.
- Avoid reclaiming the seats.
- Create or schedule a refund reconciliation request.

This refund is due to an unsuccessful booking outcome, not a customer cancellation.

---

# Step 3.8 – BOOKING_SEAT and TICKET Design

## 3.8.1 BOOKING_SEAT Purpose

`BOOKING_SEAT` represents the historical allocation of a seat to a confirmed booking.

Temporary seat ownership is represented by:

- `SEAT_HOLD`
- `SHOW_SEAT_CLAIM`

A `BOOKING_SEAT` record is created only when the booking is successfully confirmed.

This avoids creating permanent booking-seat allocations for temporary holds that may expire.

## 3.8.2 BOOKING_SEAT Statuses

| Status | Meaning |
|---|---|
| `CONFIRMED` | Seat allocation belongs to a confirmed booking. |
| `CANCELLED` | Seat allocation was cancelled. |

### Rules

- One row represents one seat in a booking.
- All booking-seat rows for a booking are created in the same confirmation transaction.
- `price_paid` stores the historical price paid for that seat.
- The historical price must not change if the seat's current price or pricing policy changes later.
- Cancellation updates the existing record rather than deleting it.

## 3.8.3 Seat and Show Consistency

A seat must belong to the auditorium in which the show is scheduled.

This relationship must be validated.

There are two implementation approaches:

**Approach A – Composite foreign keys with auditorium ID**

Include `auditorium_id` in `BOOKING_SEAT` and use composite foreign keys to enforce that the seat and show belong to the same auditorium.

This introduces controlled redundancy but provides stronger database-level integrity.

**Approach B – Transactional application validation**

Do not store `auditorium_id` in `BOOKING_SEAT`. Validate the relationship through the show and seat records during confirmation.

This avoids redundant data but relies on application transaction logic.

The final DDL should choose one approach consistently. The preferred direction is to enforce the relationship through composite keys where practical, provided the additional column does not complicate the model unnecessarily.

## 3.8.4 TICKET Design

A ticket represents the admission entitlement associated with one confirmed booking-seat allocation.

Relationship:

```text
BOOKING_SEAT 1 -------- 1 TICKET
```

Constraints:

- `TICKET.booking_seat_id` is a foreign key.
- `booking_seat_id` is unique.
- `ticket_code` is unique.
- `TICKET` does not duplicate `booking_id`; it can be derived through `BOOKING_SEAT`.

A ticket is created in the same transaction that confirms the booking and creates its booking-seat records.

## 3.8.5 Ticket Statuses

| Status | Meaning |
|---|---|
| `ISSUED` | Ticket is valid for admission. |
| `CANCELLED` | Ticket was invalidated because the booking was cancelled. |
| `USED` | Ticket was scanned and used for admission. |

Allowed transitions:

```text
ISSUED
  |
  +------> CANCELLED
  |
  +------> USED
```

A cancelled or used ticket cannot return to `ISSUED`.

Full gate-scanning infrastructure is outside the scope of this assignment.

Ticket codes should be generated application-side using a secure, collision-resistant generator. The database unique constraint remains the final protection against duplicate codes.

---

# Step 3.9 – Transaction Management and Concurrency

## 3.9.1 Core Invariants

The implementation must preserve these invariants:

1. A show-seat combination has at most one current claim.
2. A booking acquires all requested seats or none.
3. A booking can be confirmed only when all required claims remain valid.
4. Expired and cancelled bookings cannot be reactivated.
5. A late payment webhook cannot reclaim released seats.
6. The expiry worker cannot remove confirmed claims.
7. Only one payment attempt can successfully confirm a booking.
8. Confirmed cancellation releases all associated claims atomically.
9. Duplicate webhooks and refund retries cannot apply the same business effect twice.

## 3.9.2 Seat Acquisition Transaction

The seat-acquisition workflow must:

1. Begin a transaction.
2. Lock or validate the relevant booking and seat data.
3. Process expired claims when necessary.
4. Attempt to insert all required `HOLD` claims.
5. Create the corresponding `ACTIVE` seat-hold records.
6. Commit only if all requested seats are acquired.

The primary key on `SHOW_SEAT_CLAIM(show_id, seat_id)` is the final concurrency guard.

A preliminary SELECT for availability is not sufficient because two concurrent transactions may observe the same seat as available.

Any conflict must roll back the entire acquisition.

## 3.9.3 Booking Confirmation Transaction

The confirmation workflow must:

1. Lock the booking.
2. Lock its seat holds and claims in deterministic seat order.
3. Validate payment status and amount.
4. Validate that all required claims still exist.
5. Validate that all holds are active and unexpired using database time.
6. Convert all claims to `CONFIRMED`.
7. Convert all holds to `CONVERTED`.
8. Create all `BOOKING_SEAT` records.
9. Create all associated `TICKET` records.
10. Change the booking to `CONFIRMED`.
11. Commit all changes together.

If any validation fails, the transaction must roll back.

## 3.9.4 Expiry Transaction

Expiry must be atomic at booking level.

The expiry operation must:

- Lock the pending booking.
- Verify that it is still pending and expired.
- Change all active holds to expired.
- Delete only its temporary `HOLD` claims.
- Change the booking status to `EXPIRED`.
- Commit the changes together.

The operation must not affect claims belonging to other bookings.

## 3.9.5 Cancellation Transaction

Confirmed booking cancellation must:

- Lock the booking and associated records.
- Verify cancellation eligibility.
- Change the booking status to `CANCELLED`.
- Change all booking-seat records to `CANCELLED`.
- Change issued tickets to `CANCELLED`.
- Delete the corresponding confirmed claims.
- Create a refund request only when eligible.
- Commit all database changes together.

Converted seat holds remain converted as historical records.

## 3.9.6 Locking and Deadlock Handling

Use a consistent locking order wherever practical.

Recommended order:

1. Booking
2. Seat holds
3. Show-seat claims
4. Booking-seat records
5. Tickets
6. Payment/refund records as required

Webhook event records may also need locking. The final implementation must review lock ordering across webhook, confirmation, expiry, and cancellation workflows to minimize deadlocks.

Additional rules:

- Lock multiple seats in deterministic order, such as ascending `seat_id`.
- Do not perform external network calls while database locks are held.
- Retry the entire transaction a bounded number of times for transient deadlock or lock-timeout errors.
- Do not retry genuine business conflicts as if they were database failures.
- Make all retryable operations idempotent.

---

# Step 3.10 – Show Scheduling and Overlap Prevention

## 3.10.1 Scheduling Rule

Two shows must not overlap in the same auditorium.

Shows in different auditoriums may overlap.

Use half-open time intervals:

```text
[start_time, end_time)
```

This means a show ending at 14:00 and another beginning at 14:00 do not overlap.

## 3.10.2 Overlap Condition

An existing show overlaps with a proposed show when:

```sql
existing.start_time < proposed.end_time
AND existing.end_time > proposed.start_time
```

The proposed show must be rejected if an overlapping show exists in the same auditorium.

## 3.10.3 Concurrency Protection

A simple overlap query is insufficient when two administrators schedule shows concurrently.

Both transactions could observe no conflicting show and insert overlapping records.

Therefore:

1. Begin a transaction.
2. Lock the parent `AUDITORIUM` row using `SELECT ... FOR UPDATE`.
3. Check for overlapping shows in that auditorium.
4. Insert or update the show only when no overlap exists.
5. Commit.

This serializes scheduling operations for the same auditorium.

The same procedure must be used for:

- Creating a show.
- Rescheduling a show.
- Changing a show's end time.
- Changing a show's duration.

## 3.10.4 Database Constraints and Index

Add a CHECK constraint:

```sql
CHECK (end_time > start_time)
```

Recommended index:

```text
SHOW(auditorium_id, start_time)
```

MySQL does not provide a native exclusion constraint equivalent to PostgreSQL's range exclusion constraints. The parent-row locking strategy therefore provides the required concurrency protection.

---

# Step 3.11 – Final Schema Review and Validation

Before writing the final DDL, validate the following.

## 3.11.1 Final Table Inventory

| Table | Responsibility |
|---|---|
| `CUSTOMER` | Stores customer information. |
| `THEATRE` | Stores theatre information. |
| `AUDITORIUM` | Stores screens/auditoriums within a theatre. |
| `SEAT` | Stores physical seats within an auditorium. |
| `MOVIE` | Stores movie information. |
| `SHOW` | Stores scheduled movie shows. |
| `BOOKING` | Stores booking-level information and lifecycle. |
| `SEAT_HOLD` | Stores temporary seat-hold history. |
| `SHOW_SEAT_CLAIM` | Stores current seat ownership for a show. |
| `BOOKING_SEAT` | Stores confirmed seat allocations and historical prices. |
| `PAYMENT` | Stores payment attempts. |
| `PAYMENT_WEBHOOK_EVENT` | Stores provider webhook events for idempotent processing. |
| `REFUND` | Stores refund requests and their lifecycle. |
| `TICKET` | Stores tickets issued for confirmed booking seats. |

## 3.11.2 Key and Constraint Validation

Validate:

- Primary keys and unique constraints.
- Foreign-key column types, lengths, and signedness.
- Composite foreign keys referencing the exact corresponding primary or unique keys.
- Composite foreign-key column order.
- Nullable composite foreign-key behaviour.
- Child-side indexes for foreign keys.
- CHECK constraints supported and enforced by the deployed MySQL version.
- No accidental duplicate indexes.
- Deliberate `ON DELETE` and `ON UPDATE` behaviour.

## 3.11.3 Data Types

Recommended conventions:

| Data | Recommended type |
|---|---|
| Surrogate IDs | Consistent integer type, such as `BIGINT` |
| Monetary amounts | `DECIMAL`, never `FLOAT` or `DOUBLE` |
| Timestamps | `DATETIME(6)` |
| Statuses | `VARCHAR` with CHECK constraints or another consistently applied representation |
| Ticket codes | `VARCHAR` with a unique constraint |

Use consistent data types across primary and foreign keys.

## 3.11.4 Timezone Strategy

Store persistent timestamps in UTC.

- Application database connections should use UTC.
- Expiry calculations must use database time.
- Refund-cutoff calculations must use a consistent time source.
- Convert timestamps to the appropriate local timezone only for presentation.

This avoids inconsistencies caused by different application-server timezones.

## 3.11.5 Refund Cutoff Snapshot

The default refund cutoff is 60 minutes before showtime.

The cutoff applies to refund eligibility, not cancellation eligibility.

Store a `refund_cutoff_at` snapshot on the booking when it is created.

This preserves the policy applicable to the booking even if the configurable refund policy changes later.

Refund eligibility:

```text
cancellation_time < refund_cutoff_at
```

Exactly at the cutoff, the booking is not eligible for a refund.

The customer may still cancel a confirmed booking before showtime, but a cancellation after the refund cutoff does not generate a refund request.

## 3.11.6 Index Review

The following secondary indexes are planned:

| Table | Index | Purpose |
|---|---|---|
| `SHOW` | `(movie_id, start_time)` | Find shows for a movie by time. |
| `SHOW` | `(auditorium_id, start_time)` | Find auditorium schedules and check overlaps. |
| `BOOKING` | `(customer_id, created_at)` | Retrieve a customer's booking history. |
| `SEAT_HOLD` | `(status, expires_at)` | Find active holds eligible for expiry processing. |
| `PAYMENT` | `(booking_id, created_at)` | Retrieve payment attempts for a booking. |
| `PAYMENT_WEBHOOK_EVENT` | `(processing_status, received_at)` | Find webhook events requiring processing or retry. |
| `BOOKING_SEAT` | `(booking_id)` | Retrieve seats belonging to a booking, if not already covered by another index. |

Additional considerations:

- Primary keys already create indexes.
- Unique constraints already create unique indexes.
- InnoDB may automatically create indexes required by foreign keys.
- Inspect existing indexes before adding duplicates.
- Use `EXPLAIN` against important application queries before finalizing the index set.

## 3.11.7 Historical Data Retention

Business and transaction history must not be physically deleted during normal application operations.

Preserve:

- Bookings.
- Seat holds.
- Booking-seat allocations.
- Tickets.
- Payment attempts.
- Webhook events.
- Refund records.

`SHOW_SEAT_CLAIM` is different because it represents current ownership rather than historical ownership. Its rows may be deleted when a hold expires or a confirmed booking is cancelled.

Avoid cascading deletes that could remove financial or booking history unintentionally.

---

# Step 3.12 – Documentation Reconciliation and Implementation Plan

## 3.12.1 Documentation to Maintain

The following documentation files form the design baseline:

```text
docs/
├── database-design.md
├── er-diagram.md
├── er-diagram.png
├── normalization.md
├── KeysConstraintsAndIndices.md
├── Step-3.4-Status-Values-and-Lifecycle-Transitions.md
└── Step-3.5-to-3.12-Remaining-Design-Decisions.md
```

## 3.12.2 Documentation Reconciliation Checklist

Before SQL implementation, ensure all documentation is consistent.

- [ ] Add `REFUND` to the entity inventory.
- [ ] Update the ER diagram to include `REFUND`.
- [ ] Ensure the ER diagram distinguishes current seat claims from historical seat holds.
- [ ] Document `SHOW_SEAT_CLAIM` as the current ownership table.
- [ ] Document `SEAT_HOLD` as the hold-history table.
- [ ] Document `BOOKING_SEAT` as confirmed allocation history.
- [ ] Ensure `TICKET` references `BOOKING_SEAT`, not `BOOKING` directly.
- [ ] Document multiple payment attempts per booking.
- [ ] Document webhook idempotency.
- [ ] Document refund lifecycle separately from booking cancellation.
- [ ] Clarify that the one-hour rule is a refund cutoff, not a cancellation cutoff.
- [ ] Document that confirmed bookings can be cancelled before showtime.
- [ ] Document that post-cutoff cancellations do not generate refunds.
- [ ] Document booking-level, all-or-nothing hold expiry.
- [ ] Document late successful payment reconciliation.
- [ ] Ensure all status values match the final DDL.
- [ ] Ensure all key, constraint, and index names match the implementation.

## 3.12.3 SQL Implementation Sequence

Once the documentation is reconciled, implementation proceeds in this order.

### Phase 1 – Schema

Create:

```text
sql/schema.sql
```

Include:

- Table definitions.
- Primary keys.
- Foreign keys.
- Unique constraints.
- CHECK constraints.
- Required indexes.

Create tables in dependency order so foreign keys can be defined cleanly.

### Phase 2 – Sample Data

Create:

```text
sql/sample-data.sql
```

Populate representative data for:

- Customers.
- Theatres.
- Auditoriums.
- Seats.
- Movies.
- Shows.

Include enough records to test multiple theatres, multiple auditoriums, different seat categories, and overlapping show schedules.

### Phase 3 – Application Queries

Create:

```text
sql/showtimes-query.sql
```

Include the queries required to retrieve:

- Movies.
- Shows for a movie.
- Shows by theatre.
- Available seats for a show.
- Booking history for a customer.
- Payment attempts for a booking.
- Tickets for a confirmed booking.

### Phase 4 – Constraint Validation

Validate:

- Primary and foreign key relationships.
- Unique constraints.
- CHECK constraints.
- Composite foreign keys.
- Show scheduling overlap prevention.
- Seat ownership uniqueness.
- Index coverage.

### Phase 5 – Transaction Workflows

Implement and validate:

1. All-or-nothing multi-seat acquisition.
2. Booking-level seat hold creation.
3. Booking expiry.
4. Payment initiation and retry.
5. Webhook idempotency.
6. Booking confirmation.
7. Ticket issuance.
8. Confirmed booking cancellation.
9. Refund creation and retry.
10. Late payment reconciliation.

### Phase 6 – README

Update the repository README with:

- Project overview.
- Database technology.
- Entity and relationship summary.
- Setup instructions.
- SQL execution order.
- Important business rules.
- Transaction and concurrency design.
- Sample queries.
- Known scope limitations.

---

# Final Design Principles

The following principles guide the implementation:

1. **Database-enforced integrity:** Use primary keys, foreign keys, unique constraints, and CHECK constraints wherever they can enforce the required rules.
2. **Transactional consistency:** Multi-table booking, confirmation, expiry, and cancellation operations must be atomic.
3. **No partial bookings:** A booking either acquires all requested seats or none.
4. **Separate lifecycles:** Booking, seat hold, current seat claim, payment, refund, booking-seat allocation, and ticket lifecycles must remain distinct.
5. **Idempotency:** Retried requests and duplicate provider webhooks must not produce duplicate business effects.
6. **Historical accuracy:** Preserve completed and cancelled transaction records rather than deleting them.
7. **Concurrency safety:** Use database uniqueness and row-level locking rather than relying only on application-side availability checks.
8. **Minimal redundancy:** Avoid storing values that can be derived unless controlled redundancy materially improves integrity or query design.
9. **Consistent time handling:** Use UTC and database time for expiry and cutoff decisions.
10. **Implementation consistency:** The DDL, application logic, ER diagram, and documentation must describe the same model.

---

## Completion Criteria

The remaining design-decision phase is considered complete when:

- All lifecycle statuses and transitions are finalized.
- Booking-level hold and expiry behaviour is documented.
- Current seat ownership and historical seat allocation are clearly separated.
- Payment, webhook, and refund behaviour is defined.
- Ticket issuance and cancellation behaviour is defined.
- Concurrency and transaction invariants are documented.
- Show scheduling overlap prevention is defined.
- The final entity inventory and index plan are reconciled across documents.
