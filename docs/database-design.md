# Database Design --- Ticket Booking System

**Document status:** Initial design baseline\
**Purpose:** Consolidate the agreed business requirements, database
design decisions, core entities, relationships, and integrity rules
before implementing the MySQL schema.

------------------------------------------------------------------------

## 1. Scope and goals

This design describes the database for a cinema ticket-booking system
similar in core behavior to BookMyShow. It focuses on movie screenings,
auditorium seating, customer bookings, temporary seat holds, payments,
and ticket issuance.

The immediate goal is to agree on the logical model and its business
rules before writing executable SQL. This document is a design baseline;
implementation details such as exact SQL types, indexes, transaction
logic, and constraints will be finalized during schema design.

### Design goals

-   Represent movies, theatres, auditoriums, physical seats, and
    scheduled shows.
-   Allow customers to book multiple seats for one show.
-   Prevent two customers from successfully claiming or purchasing the
    same seat for the same show.
-   Support temporary seat holds with a five-minute expiry.
-   Treat a multi-seat hold as an all-or-nothing operation.
-   Keep temporary holds distinct from confirmed seat allocations.
-   Track payment attempts and payment-provider webhook events safely.
-   Preserve useful booking, hold, payment, and ticket history rather
    than relying on deleting expired records.

## 2. Agreed business requirements

### 2.1 Cinema structure

1.  A theatre can contain multiple auditoriums.
2.  An auditorium contains multiple physical seats.
3.  Each seat has an identifier within the auditorium and a seat type,
    such as Executive, Premium, or Recliner.
4.  A movie can have many shows.
5.  Each show screens one movie in one auditorium at a scheduled start
    and end time.
6.  An auditorium can host multiple shows at different times, but
    overlapping shows in the same auditorium must not be allowed.
7.  The same physical seat can be booked for different shows, because
    seat availability is specific to a show.

### 2.2 Customer and booking behavior

1.  A customer can create bookings for shows.
2.  A booking represents one customer's reservation/checkout attempt for
    one show.
3.  A booking can contain multiple selected seats.
4.  A customer may have more than one active booking attempt at a time;
    the design should not impose a one-active-booking-per-customer
    restriction.
5.  A booking groups the seats selected during one checkout attempt.
6.  Temporary seat holds and confirmed seat allocations are modeled
    separately because they represent different concepts and lifecycles.

### 2.3 Seat holds and concurrency

1.  A hold is tracked per individual seat and show, rather than as one
    unstructured hold for a group of seats.
2.  Each hold is associated with the booking attempt that requested it.
3.  A successful hold lasts five minutes, unless payment succeeds in
    time and the booking is confirmed.
4.  If the customer abandons checkout or payment does not succeed before
    expiry, the hold expires and the seats become available to other
    customers.
5.  Expired hold records may be retained for audit and troubleshooting.
    Expired records must not continue to block availability.
6.  Two customers may attempt to reserve the same seat concurrently. The
    system must ensure that no more than one conflicting active hold or
    confirmed allocation succeeds.
7.  Seat acquisition for a multi-seat request follows an
    **all-or-nothing** policy:
    -   If every requested seat can be held, all holds are acquired.
    -   If any requested seat cannot be held, the attempt must not
        retain only a subset of the requested seats.
    -   Any claims acquired by the failed attempt must be rolled back or
        released. The system must never release another customer's
        holds.
8.  The system should resolve contention promptly and report unavailable
    seats, rather than making a customer wait for another customer's
    five-minute hold to expire.

### 2.4 Payment and confirmation

1.  Payment is tracked separately from the booking because payment
    attempts and booking state are related but not identical.
2.  Only a verified payment success received within the hold's valid
    period may confirm the booking under the chosen expiry policy.
3.  A payment that succeeds after the hold has expired must not
    automatically confirm a booking if its seats may have been released
    or allocated to someone else.
4.  Late payment success requires a safe reconciliation path, such as
    refunding the payment or another explicitly defined recovery
    process. It must not cause double booking.
5.  Payment-provider webhook events must be tracked and processed
    idempotently so duplicate deliveries do not apply the same event
    more than once.
6.  The data model should preserve payment status and webhook-processing
    history for investigation and reconciliation.

### 2.5 Ticket issuance

1.  A confirmed booking can include multiple seat allocations.
2.  Tickets are issued for individual allocated seats, not just for the
    booking as a whole.
3.  Each issued ticket has a unique ticket code and a status that can
    support later lifecycle operations.

------------------------------------------------------------------------

## 3. Core entities and responsibilities

  -----------------------------------------------------------------------
  Entity                              Responsibility
  ----------------------------------- -----------------------------------
  `Customer`                          Stores customer identity and
                                      contact information.

  `Theatre`                           Stores cinema/theatre location and
                                      identifying information.

  `Auditorium`                        Represents a screen/auditorium
                                      belonging to a theatre.

  `Seat`                              Represents a physical seat within
                                      an auditorium, including its seat
                                      number and type.

  `Movie`                             Stores film information
                                      independently of its screenings.

  `Show`                              Represents a scheduled screening of
                                      one movie in one auditorium.

  `Booking`                           Groups a customer's reservation
                                      attempt for a particular show and
                                      tracks its lifecycle.

  `SeatHold`                          Represents a temporary claim on one
                                      seat for one show, including expiry
                                      and status.

  `BookingSeat`                       Associates a seat with a booking
                                      and records the allocation and
                                      price charged for that seat.

  `Payment`                           Records payment attempts, provider
                                      references, amounts, and outcomes
                                      for a booking.

  `PaymentWebhookEvent`               Records provider webhook events and
                                      their processing status for
                                      idempotency and auditability.

  `Ticket`                            Represents the ticket issued for an
                                      individual booking-seat allocation.
  -----------------------------------------------------------------------

### Why `Movie` and `Show` are separate

A movie is the film itself; a show is one scheduled screening of that
film. The same movie can have multiple shows at different times and in
different auditoriums or theatres. Combining these concepts would
duplicate movie information and make scheduling harder to model
correctly.

### Why `SeatHold` and `BookingSeat` are separate

A `SeatHold` is temporary and expires. A `BookingSeat` records which
seat is allocated to a booking after the booking is confirmed. Keeping
them separate clarifies their different lifecycles and allows expired
holds to remain in history without representing a confirmed purchase.

------------------------------------------------------------------------

## 4. Conceptual relationships and cardinalities

  -----------------------------------------------------------------------
  Relationship            Cardinality             Meaning
  ----------------------- ----------------------- -----------------------
  Theatre → Auditorium    One-to-many             A theatre contains one
                                                  or more auditoriums.

  Auditorium → Seat       One-to-many             An auditorium has
                                                  multiple physical
                                                  seats.

  Auditorium → Show       One-to-many over time   An auditorium hosts
                                                  multiple scheduled
                                                  shows.

  Movie → Show            One-to-many             A movie may be screened
                                                  in many shows.

  Customer → Booking      One-to-many             A customer may create
                                                  multiple bookings.

  Show → Booking          One-to-many             A show may receive many
                                                  booking attempts.

  Booking → SeatHold      One-to-many             A booking attempt can
                                                  hold multiple
                                                  individual seats.

  Show → SeatHold         One-to-many             A show has temporary
                                                  holds for different
                                                  seats.

  Seat → SeatHold         One-to-many over time   A physical seat may
                                                  have hold records for
                                                  different shows or at
                                                  different times.

  Booking → BookingSeat   One-to-many             A booking can contain
                                                  multiple seat
                                                  allocations.

  Show → BookingSeat      One-to-many             A show has multiple
                                                  allocated seats.

  Seat → BookingSeat      One-to-many over time   A physical seat can be
                                                  allocated in different
                                                  shows, but at most once
                                                  per show.

  Booking → Payment       One-to-many             A booking may have
                                                  multiple payment
                                                  attempts or records.

  Payment →               One-to-many             A payment can receive
  PaymentWebhookEvent                             multiple provider
                                                  events.

  BookingSeat → Ticket    Zero-or-one to one      A booking-seat
                                                  allocation may have one
                                                  ticket issued for it.
  -----------------------------------------------------------------------

The `Show` determines the movie and auditorium. The theatre for a show
can therefore be obtained through `Show → Auditorium → Theatre`.

------------------------------------------------------------------------

## 5. Initial entity attributes

These attributes are a starting point for logical modeling, not a
finalized SQL schema. Names and types may change during normalization
and constraint review.

### Customer

-   `customer_id` --- primary key
-   `name`
-   `email` --- candidate for a uniqueness constraint, subject to
    account policy
-   `phone`

### Theatre

-   `theatre_id` --- primary key
-   `name`
-   `address`
-   `city`

### Auditorium

-   `auditorium_id` --- primary key
-   `theatre_id` --- foreign key to `Theatre`
-   `name`

### Seat

-   `seat_id` --- primary key
-   `auditorium_id` --- foreign key to `Auditorium`
-   `seat_number`
-   `seat_type`

A likely rule is that `seat_number` is unique within an auditorium, not
globally across all auditoriums.

### Movie

-   `movie_id` --- primary key
-   `title`
-   `duration_minutes`
-   `language`
-   `certification`

Additional movie metadata may be added if needed.

### Show

-   `show_id` --- primary key
-   `movie_id` --- foreign key to `Movie`
-   `auditorium_id` --- foreign key to `Auditorium`
-   `start_time`
-   `end_time`
-   `base_price`
-   `status`

The design must prevent overlapping show schedules in the same
auditorium. This rule usually requires transactional/application-level
coordination in addition to ordinary foreign keys.

### Booking

-   `booking_id` --- primary key
-   `customer_id` --- foreign key to `Customer`
-   `show_id` --- foreign key to `Show`
-   `status`
-   `created_at`
-   `confirmed_at`

The exact status values and transitions remain to be defined. A booking
represents the reservation attempt as well as its subsequent outcome; it
is not a permanent seat hold by itself.

### SeatHold

-   `hold_id` --- primary key
-   `booking_id` --- foreign key to `Booking`
-   `show_id` --- foreign key to `Show`
-   `seat_id` --- foreign key to `Seat`
-   `status`
-   `created_at`
-   `expires_at`

Each record represents one seat hold. The model must ensure the
referenced seat belongs to the auditorium used by the show. It must also
prevent conflicting active holds for the same show-seat pair while
retaining historical expired holds.

### BookingSeat

-   `booking_seat_id` --- primary key
-   `booking_id` --- foreign key to `Booking`
-   `show_id` --- foreign key to `Show`
-   `seat_id` --- foreign key to `Seat`
-   `price_paid`

The `show_id` is derivable from `Booking`, so storing it here introduces
redundancy. It may be retained to support show-seat uniqueness
constraints, but if retained, the schema must enforce that it matches
the parent booking's show. This trade-off must be resolved before
finalizing `schema.sql`.

### Payment

-   `payment_id` --- primary key
-   `booking_id` --- foreign key to `Booking`
-   `provider_reference` --- candidate for a unique constraint when
    supplied by the provider
-   `amount`
-   `status`
-   `created_at`

Further fields may be needed for currency, payment provider, failure
details, and timestamps for successful or failed outcomes.

### PaymentWebhookEvent

-   `webhook_event_id` --- primary key
-   `payment_id` --- foreign key to `Payment`
-   `provider_event_id` --- unique identifier supplied by the payment
    provider
-   `event_type`
-   `received_at`
-   `processing_status`

The provider's event identifier should be unique within the appropriate
provider/account scope. If multiple providers are supported, the
uniqueness rule may need to include the provider identifier.

### Ticket

-   `ticket_id` --- primary key
-   `booking_seat_id` --- foreign key to `BookingSeat`
-   `ticket_code` --- unique
-   `status`
-   `issued_at`

The model should ensure that a booking-seat allocation cannot
accidentally receive multiple active tickets unless that behavior is
explicitly intended.

------------------------------------------------------------------------

## 6. Integrity and concurrency rules

The ER diagram alone does not enforce every business rule. The final
MySQL schema and application transaction design must address the
following.

### 6.1 Seat identity and show-seat identity

-   A physical seat belongs to exactly one auditorium.
-   A show belongs to exactly one auditorium.
-   The seat must belong to the auditorium where the show is scheduled.
-   Seat availability and allocation are scoped to `(show_id, seat_id)`,
    not `seat_id` alone.

### 6.2 Preventing conflicting holds

A simple unique constraint on `(show_id, seat_id)` in `SeatHold` would
prevent historical hold records from being retained, so it is not
sufficient by itself for the intended design.

Possible implementation approaches include a dedicated
current-availability/claim table with a unique `(show_id, seat_id)` key,
or another carefully designed transaction and locking strategy. The
implementation must guarantee that two concurrent requests cannot both
acquire the same seat. The final choice will be made during physical
schema design.

### 6.3 Preventing double booking

The database must enforce or safely coordinate the rule that one
`(show_id, seat_id)` can belong to at most one confirmed booking.
Application checks without appropriate database locking or constraints
are not sufficient under concurrency.

### 6.4 Atomic group holds

Acquiring multiple seats must be performed as one transaction or
equivalent atomic operation. If any requested seat cannot be acquired,
all claims made by that attempt must be rolled back or released.

### 6.5 Hold expiry

-   Each hold records its expiry timestamp.
-   Availability checks must treat expired holds as no longer active,
    even if a background expiry task has not yet updated their status.
-   A background task may update expired records for housekeeping and
    reporting, but correctness must not depend solely on that task
    running on time.
-   Expiry and payment confirmation must be coordinated so that a late
    payment cannot confirm a seat that has already been released and
    reallocated.

### 6.6 Idempotent payment processing

-   Repeated delivery of the same webhook event must not apply the same
    payment transition twice.
-   Webhook events should be persisted and processed with a unique
    provider event identifier.
-   Payment state transitions must be validated; an event should not
    blindly overwrite a newer or terminal state.
-   Payment success and booking confirmation must be handled safely if
    they race with hold expiry.

### 6.7 Scheduling and data consistency

-   Shows in the same auditorium must not overlap.
-   A `BookingSeat` must refer to a seat in the show's auditorium.
-   If `show_id` is stored redundantly in `BookingSeat`, it must match
    the show's identifier on the parent `Booking`.
-   A ticket must reference a valid booking-seat allocation.
-   Monetary values should use exact decimal types rather than
    floating-point types.

------------------------------------------------------------------------

## 7. Status and lifecycle decisions

The exact enum/check-constraint values are not finalized yet, but the
following concepts must be represented.

  -----------------------------------------------------------------------
  Entity                              Lifecycle concepts
  ----------------------------------- -----------------------------------
  `Booking`                           Reservation/checkout attempt,
                                      confirmed, expired or
                                      cancelled/failed as appropriate.

  `SeatHold`                          Active, released, expired, or
                                      converted/consumed upon successful
                                      confirmation.

  `Payment`                           Pending/in progress, succeeded,
                                      failed, or refunded where
                                      applicable.

  `PaymentWebhookEvent`               Received, processing, processed, or
                                      failed/retryable.

  `Ticket`                            Issued and potentially cancelled or
                                      otherwise invalidated.

  `Show`                              Scheduled and potentially cancelled
                                      or completed.
  -----------------------------------------------------------------------

These are lifecycle concepts, not a finalized list of allowed status
strings.

------------------------------------------------------------------------

## 8. Explicitly deferred decisions

The following are not yet settled and should be reviewed before the
schema is considered final:

1.  **Booking and hold status transitions:** exact states and which
    transitions are permitted.
2.  **Late payment recovery:** refund behavior, reconciliation workflow,
    and handling of provider callbacks arriving near or after expiry.
3.  **Concurrency implementation:** exact MySQL locking and constraint
    strategy for active holds and confirmed seat allocations.
4.  **`BookingSeat.show_id`:** whether to retain this redundant value to
    support uniqueness constraints or derive it through `Booking`.
5.  **Pricing:** whether price is stored at show level, seat-type level,
    booking-seat level, or a combination. The charged price must be
    preserved for historical bookings.
6.  **Seat types and pricing rules:** whether seat types are free-text
    values, constrained values, or normalized into a separate table.
7.  **Customer identity rules:** whether email and phone are required
    and unique, and how account changes are handled.
8.  **Cancellation and refund policies:** whether customers can cancel
    confirmed bookings and how that affects tickets and seats.
9.  **Operational details:** currency, timezone policy, audit
    timestamps, retention, and indexes.
10. **Scope of the first implementation:** whether to include refunds,
    cancellation workflows, and additional show/movie metadata in the
    initial schema.

------------------------------------------------------------------------

## 9. Proposed implementation sequence

1.  Reviewing this requirements baseline.
2.  Finalize the ER diagram and remove or justify any redundant
    attributes.
3.  Normalize the relational model and define primary keys, foreign
    keys, unique constraints, and check constraints.
4.  Decide the physical MySQL strategy for atomic multi-seat holds,
    expiry, and confirmed-seat uniqueness.
5.  Create `sql/schema.sql`.
6.  Create representative sample data in `sql/sample-data.sql`.
7.  Implement and validate the requested showtimes query in
    `sql/showtimes-query.sql`.
8.  Document the normalization rationale and test important integrity
    rules with representative scenarios.

------------------------------------------------------------------------

## 10. Summary of agreed decisions

-   `Movie` and `Show` are separate entities.
-   A theatre contains multiple auditoriums; an auditorium contains
    physical seats.
-   A show screens one movie in one auditorium at a scheduled time.
-   Seat availability is specific to a show-seat combination.
-   One booking can contain multiple seats.
-   `SeatHold` and `BookingSeat` are separate concepts.
-   Holds are tracked individually per seat and expire after five
    minutes.
-   Multi-seat hold acquisition is all-or-nothing.
-   Multiple active booking attempts per customer are allowed.
-   Expired holds release seats even if historical records remain
    stored.
-   Late payment success must never cause double booking.
-   Payment webhook processing must be idempotent.
-   Database constraints and transactional concurrency control are
    required; application-level availability checks alone are not
    enough.

This document is the current design baseline. Unresolved choices are
explicitly listed so they can be settled deliberately before
implementation.
