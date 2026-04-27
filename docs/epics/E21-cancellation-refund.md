# E21 — Booking Cancellation & Refund

## Goal

Single user-triggered Screen Flow that orchestrates the full booking
cancellation cascade: open demands → agreement → possession → booking
→ unit, with refund calculation and automatic commission clawback via
the existing E17 trigger wiring.

## Architecture

```
                      ┌──────────────────────────────┐
                      │  Booking page → "Cancel       │
                      │  Booking" Quick Action        │
                      │  (Flow type, sortOrder 3)     │
                      └─────────────┬────────────────┘
                                    │
                                    ▼
                      ┌──────────────────────────────┐
                      │   Cancel_Booking Screen Flow │
                      │   1. Get_Booking lookup      │
                      │   2. Confirm_Screen          │
                      │      - Cancellation Reason   │
                      │        (RadioButtons, 5      │
                      │         picklist values)     │
                      │      - Forfeiture %          │
                      │        (default 10)          │
                      │   3. Cancel_Booking_Action   │
                      │      → CancellationService   │
                      │   4. Success_Screen          │
                      └─────────────┬────────────────┘
                                    │ @InvocableMethod
                                    ▼
              ┌──────────────────────────────────────────────┐
              │           CancellationService                │
              │                                              │
              │  STEP 1  Validate (status, reason, pct)      │
              │  STEP 2  Cancel open Demands                 │
              │            (Raised/Partial/Overdue)          │
              │  STEP 3  Cancel Agreement(s)                 │
              │  STEP 4  Mark Possession Delayed             │
              │            (no 'Cancelled' picklist value)   │
              │  STEP 5  refund = paid × (1 − pct/100)       │
              │  STEP 6  Update Booking ───────────────────┐ │
              │            Status = Cancelled              │ │
              │            Cancellation_Date = today       │ │
              │            Cancellation_Reason = input     │ │
              │            Refund_Amount = computed        │ │
              │  STEP 7  Update Unit                       │ │
              │            Unit_Status = Cancelled         │ │
              │            (Booked → Cancelled, E07)       │ │
              └────────────────────────────────────────────┼─┘
                                                           │
                          ┌────────────────────────────────┘
                          ▼
              ┌──────────────────────────────────┐
              │  BookingTrigger AFTER_UPDATE     │
              │  → CommissionService             │
              │      .clawbackOnCancellation     │
              │  (E17 — automatic, no coupling)  │
              └──────────────────────────────────┘
```

## Implemented

### Apex

- **`CancellationService.cls`** — `with sharing`, `WITH SECURITY_ENFORCED`
  on every SOQL. Single InvocableMethod `cancelBookings(List<CancellationRequest>) → List<CancellationResult>`.
  Bulkified one-Booking-at-a-time inside the loop for now (per-Booking
  workflow is naturally sequential — agreement / possession / unit
  state transitions don't bulk meaningfully). All seven steps execute
  atomically per Booking; if any step fails, the transaction rolls
  back.

- **Validation surface**:
  - Booking must exist (else AuraHandledException)
  - Booking_Status must NOT be `Cancelled` or `Possessed`
  - Cancellation Reason must match one of the 5 existing picklist
    values: `Buyer Withdrew`, `Financing Failed`, `Dispute`,
    `Admin Cancelled`, `Other`
  - Forfeiture Percentage in [0, 100]; defaults to 10 if null

- **`CancellationServiceTest.cls`** — 8 tests, 100% pass:
  - Happy path (with CP + Agreement + Receipt → asserts refund,
    agreement status, unit status, **commission clawback fires
    automatically via E17 trigger**)
  - Already cancelled rejected
  - Already possessed rejected
  - No agreement / no possession (clean cancel)
  - Zero forfeiture (full refund)
  - Possession in 'Snag Phase' → 'Delayed'
  - Bulk operation (3 bookings in one InvocableMethod call)
  - Invalid reason rejected

  Tests use `RecursionGuard.resetAll()` after `seedBooking` and
  between setup DMLs so the cancellation update fires the
  Booking_afterUpdate-guarded clawback path cleanly.

### Screen Flow

- **`flows/Cancel_Booking.flow-meta.xml`** — Screen Flow,
  apiVersion 62.0, status Active.
  - 5 static `<choices>` resources (one per Cancellation_Reason
    picklist value) bound to a RadioButtons screen field
  - Number InputField for Forfeiture Percentage (default 10, scale 2)
  - DisplayText warning about irreversibility
  - Apex actionCall to `CancellationService` with three input parameters
    (`bookingId`, `reason`, `forfeiturePercent`), `storeOutputAutomatically`
  - Success screen with high-level summary (refund and clawback are
    not displayed inline because Flow doesn't natively render
    InvocableMethod return values without additional plumbing — this
    is a follow-up polish item)

### Quick Action + Layout

- **`objects/Booking__c/quickActions/Cancel_Booking.quickAction-meta.xml`**
  — Flow QA, label "Cancel Booking", `flowDefinition=Cancel_Booking`.
- **`layouts/Booking__c-Booking Layout`** — appended `Cancel_Booking`
  to existing `<platformActionList>` at sortOrder 3 (after
  Raise_Demand=0, Create_Agreement=1, Create_Possession=2).
  Per gotcha #41, Flow QAs go in `<platformActionList>`,
  not `<quickActionList>`.

### Schema (FLS fix surfaced during deploy)

- **`profiles/Admin.profile-meta.xml`** — added `<fieldPermissions>`
  for `Booking__c.Total_Paid__c` (Roll-up Summary). Sibling roll-ups
  (`Total_Outstanding__c`, `Total_Consideration__c`) already had FLS
  on Admin; `Total_Paid__c` was missed at original deploy time.
  Per gotcha #27, all custom fields need explicit FLS even on Admin
  for SOQL selectability (especially when callers use
  `WITH SECURITY_ENFORCED`).

  This was a real failure caught by the test suite — without it,
  every CancellationService test that triggered Step 1's SOQL
  `SELECT ... Total_Paid__c FROM Booking__c WITH SECURITY_ENFORCED`
  failed with a masked AuraHandledException.

## Test coverage

- `CancellationServiceTest`: **8 / 8 pass**
- Full regression: **81 / 81 pass** across all 12 service test
  suites (CancellationService, CommissionService,
  CommissionPayoutBatch, RateCardService, BookingService,
  AgreementService, PossessionService, PaymentScheduleService,
  DemandService, ReceiptAllocationService, UnitBlockingService,
  UnitLifecycleService).

## Non-obvious design decisions

- **Possession 'Delayed' as cancellation marker.** The Possession
  Status picklist has no `Cancelled` value (Ready to Offer / Offered
  / Snag Phase / Cleared / Handed Over / Delayed). Rather than
  expand the picklist (out of scope), the closest semantic match
  `Delayed` is used. PossessionService.onAfterUpdate only acts on
  `Status == 'Handed Over'` (transitions Booking to Possessed), so
  setting it to `Delayed` is a safe no-op for the booking sync.
- **Unit goes to 'Cancelled', NOT directly back to 'Available'.**
  Per the E07 state machine, `Cancelled → Available` is allowed but
  is a separate (admin-controlled) step. Conservative — prevents
  accidental re-sale of a cancelled unit before refund/legal
  processes complete.
- **Clawback is fully implicit.** CancellationService doesn't
  reference CommissionService at all. The Booking status change to
  `Cancelled` in Step 6 fires `BookingTrigger AFTER_UPDATE →
  CommissionService.clawbackOnCancellation` (wired in E17), which
  detects the status transition and processes the clawback. Zero
  coupling between epics.
- **Cancellation_Reason is a picklist, not Text.** The existing
  field is restricted to 5 values. The InvocableMethod input is
  declared `String reason` and the service validates against the
  set; the Screen Flow uses RadioButtons over the same 5 values.
  No free-form notes field added to scope — if needed later, add a
  separate `Cancellation_Notes__c Text(255)`.
- **Per-Booking sequential processing inside a bulk call.** The
  InvocableMethod accepts a list of CancellationRequest, but the
  inner loop processes one Booking at a time. Cancellation is a
  workflow per Booking — there's no meaningful gain from
  cross-Booking bulkification because each Booking has its own
  Demands/Agreement/Possession/Unit cascade. Bulk-test confirms 3
  Bookings process correctly in one call.

## Out of scope

- **Refund processing automation** — `Refund_Amount__c` is computed
  and stored on the Booking, but the actual disbursement (UTR,
  finance team workflow) is manual. No payment integration.
- **Stamp duty recovery, GST reversal, interest on delayed refund**
  — real-world cancellation involves more financial reconciliation
  than the simple `paid × (1 - pct/100)` formula. Captured in spec
  as MVP simplification.
- **Cancellation approval flow** — CancellationService runs
  immediately on Flow submission. No approval step. Add a
  Salesforce Approval Process on Booking pre-cancellation if
  business requires it.
- **Audit trail beyond Booking fields** — Cancellation_Date and
  Cancellation_Reason are written to the Booking. No separate
  audit object. The status change is captured in
  `Booking_Status__c` history if Field Tracking is enabled in
  Setup (currently a manual SDO-setup step).
- **Returning Unit to 'Available' automatically** — out of scope by
  design (see decisions above). Manual admin step.

## Manual setup deferred

1. **Enable Field History Tracking** on `Booking__c.Booking_Status__c`
   and `Booking__c.Cancellation_Date__c` for audit purposes (Setup →
   Object Manager → Booking → Fields & Relationships → Set History
   Tracking). One-time SDO-setup step; not a metadata-deployable
   configuration.
