# Booking Transaction and Concurrency Design

## Database-enforced protection
- `SHOW_SEAT_CLAIM` primary key `(show_id, seat_id)` permits at most one current claim for a show-seat pair.
- Composite foreign keys enforce booking/show and show/seat/auditorium consistency.
- Unique provider/event and provider/idempotency keys support deduplication.
- Foreign keys prevent orphaned booking, payment, refund and ticket records.

## All-or-nothing multi-seat hold
1. Start a transaction.
2. Lock the target `BOOKING` row (`SELECT ... FOR UPDATE`) and verify it is `PENDING`.
3. Validate the requested seats belong to the show's auditorium.
4. Process seat IDs in deterministic ascending order.
5. Insert per-seat `SEAT_HOLD` rows using one booking-level expiry (`UTC_TIMESTAMP(6) + INTERVAL 5 MINUTE`).
6. Insert matching `SHOW_SEAT_CLAIM` rows with `claim_type='HOLD'`.
7. If any claim insert conflicts, roll back the entire transaction.
8. Commit only if every requested seat was acquired.

A unique-key conflict is the final arbiter of competing claims; an application-side availability read alone is not sufficient.

## Expiry
- A request-time check and a background worker should call the same expiry operation.
- Lock the booking and its active holds/claims.
- Compare expiry using database UTC time.
- Expire the booking and its active holds atomically; remove only matching `HOLD` claims.
- Never remove `CONFIRMED` claims.
- Preserve expired hold rows as history.

## Payment confirmation
1. Verify webhook signature outside the database transaction.
2. Persist/deduplicate the webhook event.
3. Start a transaction and lock the payment, booking, and relevant claims in a consistent order.
4. If the booking remains pending and every claim is valid, mark payment successful, convert holds, confirm booking, create `BOOKING_SEAT` rows and tickets, and convert claims.
5. If the hold expired or claims no longer belong to the booking, do not reclaim seats; record/reconcile the successful payment and initiate refund handling.
6. Commit the database state transition; make external provider calls outside the locked transaction.

## Cancellation/refund
- Lock booking and associated claims/allocations before changing state.
- Check show start and the stored `refund_cutoff_at`.
- Cancel booking and booking-seat/ticket rows as applicable; release confirmed claims in the same transaction.
- Create a durable refund row only when eligible and a successful captured payment exists.
- Enforce refund amount not exceeding captured payment amount in transactional application logic.

## Deadlocks and retries
- Lock rows in a consistent order, including seats sorted by ID.
- Keep transactions short; do not call payment-provider APIs while holding DB locks.
- Retry the entire transaction a bounded number of times after deadlock/lock-timeout errors.
- Log idempotency keys and correlation identifiers.

## Show scheduling overlap
MySQL has no general exclusion constraint for overlapping time ranges. Serialize schedule changes by locking the auditorium row, then check:
`existing.start_time < requested.end_time AND existing.end_time > requested.start_time`.
Perform the overlap check and insert/update in the same transaction.
