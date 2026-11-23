## Proposed primary keys

| Table | Proposed primary key | Reason |
|---|---|---|
| `CUSTOMER` | `customer_id` | Stable customer identifier |
| `THEATRE` | `theatre_id` | Stable theatre identifier |
| `AUDITORIUM` | `auditorium_id` | Stable auditorium identifier |
| `SEAT` | `seat_id` | Stable physical seat identifier |
| `MOVIE` | `movie_id` | Stable movie identifier |
| `SHOW` | `show_id` | Unique scheduled screening |
| `BOOKING` | `booking_id` | Unique booking attempt |
| `SEAT_HOLD` | `hold_id` | Unique hold record |
| `SHOW_SEAT_CLAIM` | `(show_id, seat_id)` | Only one current claim per seat and show |
| `BOOKING_SEAT` | `booking_seat_id` | Unique historical allocation record |
| `PAYMENT` | `payment_id` | Unique payment attempt |
| `PAYMENT_WEBHOOK_EVENT` | `webhook_event_id` | Unique stored webhook event |
| `TICKET` | `ticket_id` | Unique ticket record |

Note: `customer_email` is made unique(and case-insensitive) for the following reasons:
1. Prevents duplicate accounts using the same email.
2. Makes email-based customer lookup straightforward.
3. Supports email as a login identifier if we choose to use it that way.

## Establishing the basic foreign keys

Consider the following relationships in ticket-booking system:

| Child table | Foreign key | References | Purpose |
|---|---|---|---|
| `AUDITORIUM` | `theatre_id` | `THEATRE(theatre_id)` | Every auditorium belongs to a theatre. |
| `SEAT` | `auditorium_id` | `AUDITORIUM(auditorium_id)` | Every physical seat belongs to an auditorium. |
| `SHOW` | `movie_id` | `MOVIE(movie_id)` | Every show screens a movie. |
| `SHOW` | `auditorium_id` | `AUDITORIUM(auditorium_id)` | Every show takes place in an auditorium. |
| `BOOKING` | `customer_id` | `CUSTOMER(customer_id)` | Every booking belongs to a customer. |
| `SEAT_HOLD` | `booking_id` | `BOOKING(booking_id)` | Every hold belongs to a booking attempt. |
| `PAYMENT` | `booking_id` | `BOOKING(booking_id)` | Every payment attempt belongs to a booking. |
| `PAYMENT_WEBHOOK_EVENT` | `payment_id` | `PAYMENT(payment_id)` | Every webhook event relates to a payment. |


# Consolidated

## Keys, Constraints, and Indexes

**Database:** MySQL 8+ with InnoDB\
**Purpose:** Consolidated record of the key, integrity, uniqueness, and
indexing decisions made for the ticket-booking database.

> **Status note:** This document captures decisions agreed during the
> design discussion. Items marked **Planned / validate in DDL** are the
> intended design but still need to be checked against the final table
> definitions and MySQL's exact foreign-key/index requirements. It is
> not yet the executable schema.

## 1. Primary keys

  -------------------------------------------------------------------------
  Table                     Primary key             Why
  ------------------------- ----------------------- -----------------------
  `CUSTOMER`                `customer_id`           Stable internal
                                                    identity for each
                                                    customer.

  `THEATRE`                 `theatre_id`            Stable identity for
                                                    each theatre.

  `AUDITORIUM`              `auditorium_id`         Stable identity for
                                                    each auditorium.

  `SEAT`                    `seat_id`               Stable identity for
                                                    each physical seat.

  `MOVIE`                   `movie_id`              Stable identity for
                                                    each movie.

  `SHOW`                    `show_id`               Stable identity for
                                                    each scheduled
                                                    screening.

  `BOOKING`                 `booking_id`            Identifies a customer's
                                                    booking attempt.

  `SEAT_HOLD`               `hold_id`               Identifies one
                                                    hold-lifecycle record.

  `SHOW_SEAT_CLAIM`         `(show_id, seat_id)`    Allows at most one
                                                    current claim for a
                                                    show-seat pair.

  `BOOKING_SEAT`            `booking_seat_id`       Identifies one seat
                                                    allocated to a booking.

  `PAYMENT`                 `payment_id`            Identifies an
                                                    individual payment
                                                    attempt; retries get
                                                    separate rows.

  `PAYMENT_WEBHOOK_EVENT`   `webhook_event_id`      Identifies one recorded
                                                    webhook event.

  `TICKET`                  `ticket_id`             Identifies one issued
                                                    ticket record.


## 2. Unique and check constraints
---------------------------------------------------------------
  Table                     Constraint
  ------------------------- ------------------------------------------------- ------------------------- -----------------------
  `CUSTOMER`                `UNIQUE(customer_email)`; email must be non-null  Agreed; exact             One email identifies at
                            and uniqueness must be case-insensitive           collation/normalization   most one customer.
                                                                              to implement              Avoid capitalization
                                                                                                        variants bypassing
                                                                                                        uniqueness.

  `AUDITORIUM`              `UNIQUE(theatre_id, auditorium_name)`; both       Agreed                    Names such as
                            columns non-null                                                            `Screen 1` may repeat
                                                                                                        across theatres, but
                                                                                                        not within the same
                                                                                                        theatre.

  `SEAT`                    `UNIQUE(auditorium_id, seat_row, seat_number)`;   Agreed                    A physical position
                            position columns non-null                                                   must be unique within
                                                                                                        an auditorium. A
                                                                                                        separate `seat_label`
                                                                                                        is unnecessary; it can
                                                                                                        be derived for display.

  `SEAT`                    `CHECK (seat_number > 0)`                         Agreed design rule;       Seat numbers must be
                                                                              validate in DDL           positive.

  `SHOW`                    `UNIQUE(show_id, auditorium_id)`                  Planned / validate in DDL Provides a referenced
                                                                                                        composite key for
                                                                                                        enforcing
                                                                                                        show--auditorium
                                                                                                        consistency.

  `SEAT`                    `UNIQUE(seat_id, auditorium_id)`                  Planned / validate in DDL Provides a referenced
                                                                                                        composite key for
                                                                                                        enforcing
                                                                                                        seat--auditorium
                                                                                                        consistency.

  `BOOKING`                 `UNIQUE(booking_id, show_id)`                     Planned / validate in DDL Allows child tables to
                                                                                                        reference a booking and
                                                                                                        its show together.

  `SEAT_HOLD`               `UNIQUE(hold_id, booking_id, show_id, seat_id)`   Planned / validate in DDL Allows a claim to
                                                                                                        reference a hold only
                                                                                                        when hold, booking,
                                                                                                        show, and seat match.

  `PAYMENT_WEBHOOK_EVENT`   `UNIQUE(payment_provider, provider_event_id)`     Agreed                    Prevents duplicate
                                                                                                        records for the same
                                                                                                        event from the same
                                                                                                        provider without
                                                                                                        assuming provider event
                                                                                                        IDs are globally
                                                                                                        unique.

  `TICKET`                  `UNIQUE(ticket_code)`                             Agreed                    Each ticket has a
                                                                                                        unique validation code.

  `TICKET`                  `UNIQUE(booking_seat_id)`                         Agreed                    At most one ticket
                                                                                                        record can exist per
                                                                                                        allocated seat. Retain
                                                                                                        cancelled/invalidated
                                                                                                        ticket history rather
                                                                                                        than issuing another
                                                                                                        record for the same
                                                                                                        allocation.

  `SHOW_SEAT_CLAIM`         `CHECK`/conditional rules for `claim_type`,       Required; exact DDL       A temporary hold claim
                            `hold_id`, and `expires_at`                       pending                   must reference a hold
                                                                                                        and have an expiry; a
                                                                                                        confirmed claim must
                                                                                                        not have a temporary
                                                                                                        expiry. Must account
                                                                                                        for MySQL `CHECK` and
                                                                                                        nullable-column
                                                                                                        behavior.

### 2.1 Email uniqueness details

Implement case-insensitive uniqueness using a suitable MySQL collation
or a normalized email value with a unique constraint. Application-side
normalization should be consistent with the database rule. Whitespace
handling and the exact normalization policy remain to be specified.

### 2.2 Show scheduling rule

Shows in the same auditorium must not overlap. This is a business
invariant, **not** solved by a normal unique key on
`(auditorium_id, start_time)`, because shows with different start times
can still overlap. It will need transactional scheduling validation and
appropriate locking/serialization.

## 3. Foreign keys and composite relationships

The following are the agreed relationship rules. Composite referenced
keys listed above must be present where needed.

  ------------------------------------------------------------------------------------------------------
  Child table               Foreign key / relationship                           Why
  ------------------------- ---------------------------------------------------- -----------------------
  `AUDITORIUM`              `theatre_id` → `THEATRE(theatre_id)`                 Every auditorium
                                                                                 belongs to an existing
                                                                                 theatre.

  `SEAT`                    `auditorium_id` → `AUDITORIUM(auditorium_id)`        Every physical seat
                                                                                 belongs to an existing
                                                                                 auditorium.

  `SHOW`                    `movie_id` → `MOVIE(movie_id)`                       Every show screens an
                                                                                 existing movie.

  `SHOW`                    `auditorium_id` → `AUDITORIUM(auditorium_id)`        Every show occurs in an
                                                                                 existing auditorium.

  `BOOKING`                 `customer_id` → `CUSTOMER(customer_id)`              Every booking belongs
                                                                                 to an existing
                                                                                 customer.

  `SEAT_HOLD`               `booking_id` → `BOOKING(booking_id)` and             A hold belongs to a
                            `(booking_id, show_id)` →                            booking and must use
                            `BOOKING(booking_id, show_id)`                       that booking's show.
                                                                                 The single-column FK
                                                                                 may be redundant once
                                                                                 the composite FK is
                                                                                 present; avoid
                                                                                 duplicate enforcement
                                                                                 if the composite FK is
                                                                                 sufficient.

  `BOOKING_SEAT`            `(booking_id, show_id)` →                            Allocated seats must
                            `BOOKING(booking_id, show_id)`                       belong to the booking's
                                                                                 show.

  `SHOW_SEAT_CLAIM`         `(show_id, auditorium_id)` →                         Claim show must belong
                            `SHOW(show_id, auditorium_id)`                       to the recorded
                                                                                 auditorium.

  `SHOW_SEAT_CLAIM`         `(seat_id, auditorium_id)` →                         Claimed seat must
                            `SEAT(seat_id, auditorium_id)`                       belong to the same
                                                                                 auditorium that hosts
                                                                                 the show.

  `SHOW_SEAT_CLAIM`         `(booking_id, show_id)` →                            Claim must belong to
                            `BOOKING(booking_id, show_id)`                       the same show as its
                                                                                 booking.

  `SHOW_SEAT_CLAIM`         `(hold_id, booking_id, show_id, seat_id)` →          When a hold is
                            `SEAT_HOLD(hold_id, booking_id, show_id, seat_id)`   referenced, it must
                                                                                 match the claim's
                                                                                 booking, show, and
                                                                                 seat. Must be
                                                                                 implemented carefully
                                                                                 because `hold_id` is
                                                                                 nullable for confirmed
                                                                                 claims.

  `PAYMENT`                 `booking_id` → `BOOKING(booking_id)`                 Every payment attempt
                                                                                 belongs to an existing
                                                                                 booking. Multiple
                                                                                 attempts per booking
                                                                                 are allowed.

  `PAYMENT_WEBHOOK_EVENT`   `payment_id` → `PAYMENT(payment_id)`                 Every webhook event
                                                                                 references an existing
                                                                                 payment.

  `TICKET`                  `booking_seat_id` → `BOOKING_SEAT(booking_seat_id)`  A ticket belongs to an
                                                                                 allocated seat; its
                                                                                 booking is derived
                                                                                 through `BOOKING_SEAT`,
                                                                                 avoiding redundant
                                                                                 booking data.

### 3.1 Controlled redundancy for integrity

`BOOKING_SEAT` and `SHOW_SEAT_CLAIM` include `show_id` even though it
can be derived from the booking or related records. This controlled
redundancy supports composite foreign keys that enforce booking--show
consistency and show--seat--auditorium consistency in the database.

`SHOW` will **not** store `theatre_id` because it can be derived through
`SHOW.auditorium_id → AUDITORIUM.theatre_id`. This avoids unnecessary
duplication and a new consistency rule.

## 4. Indexes for query and operational patterns

  ---------------------------------------------------------------------------------------------------------
  Table                     Proposed index                       Purpose             Status / notes
  ------------------------- ------------------------------------ ------------------- ----------------------
  `SHOW`                    `(movie_id, start_time)`             Find shows for a    Planned; supports the
                                                                 movie within a time main movie/time access
                                                                 range.              pattern.

  `SHOW`                    `(auditorium_id, start_time)`        Retrieve auditorium Planned; assess
                                                                 schedules and help  overlap-check query
                                                                 with schedule       and locking strategy.
                                                                 validation.         

  `BOOKING`                 `(customer_id, created_at)`          Retrieve a          Planned; define
                                                                 customer's bookings `created_at` in the
                                                                 newest first.       table.

  `SEAT_HOLD`               `(status, expires_at)`               Find holds eligible Planned; evaluate
                                                                 for expiry          selectivity and
                                                                 processing.         expiry-worker query.

  `BOOKING_SEAT`            `(booking_id)`                       Retrieve seats      Planned only if no
                                                                 associated with a   existing index has
                                                                 booking.            `booking_id` as its
                                                                                     leftmost column; a
                                                                                     composite index may
                                                                                     already cover this
                                                                                     access pattern.

  `PAYMENT`                 `(booking_id, created_at)`           Retrieve payment    Planned; define
                                                                 attempts for a      `created_at` in the
                                                                 booking in time     table.
                                                                 order.              

  `PAYMENT_WEBHOOK_EVENT`   `(processing_status, received_at)`   Find                Planned; define
                                                                 pending/retryable   processing status and
                                                                 webhook events.     received timestamp.

  `SHOW_SEAT_CLAIM`         Child-side index beginning with      Support the         Required if not
                            `(seat_id, auditorium_id)`           composite FK to     already covered by
                                                                 `SEAT`.             another suitable
                                                                                     index. The PK
                                                                                     `(show_id, seat_id)`
                                                                                     does not cover this
                                                                                     column order.

  `SHOW_SEAT_CLAIM`         Existing PK `(show_id, seat_id)`     Look up a claim for Already provided by
                                                                 a show-seat pair    the primary key; do
                                                                 and enforce one     not duplicate.
                                                                 current claim per   
                                                                 pair.               


### 4.1 Indexes supplied by keys

Avoid adding separate indexes on: - `CUSTOMER(customer_email)` if the
unique constraint already creates it. -
`AUDITORIUM(theatre_id, auditorium_name)` if the unique constraint
already creates it. - `SEAT(auditorium_id, seat_row, seat_number)` if
the unique constraint already creates it. -
`PAYMENT_WEBHOOK_EVENT(payment_provider, provider_event_id)` if the
unique constraint already creates it. - `TICKET(ticket_code)` and
`TICKET(booking_seat_id)` if their unique constraints already create
them.

InnoDB may automatically create a child-side index to support a foreign
key. Before adding explicit indexes, inspect the final index definitions
to avoid redundant ones. The final index set should be validated against
the assignment's required queries and representative `EXPLAIN` plans
where possible.

**Status:** This is the consolidated design record, not yet the final
executable DDL.
