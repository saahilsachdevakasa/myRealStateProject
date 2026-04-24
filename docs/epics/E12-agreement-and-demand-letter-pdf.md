# E12 — Agreement Workflow and Demand Letter PDF

## Objective

Two related document workflows:

**Piece A** — Create `Agreement__c` records from `Booking__c` with auto-naming (`AGR-{BookingName}`), and sync Booking status when Agreement status transitions (`Signed` → `Agreement Signed`, `Executed` → `Registered`).

**Piece B** (folded into Piece A) — Agreement status → Booking status state machine as an after-update handler on Agreement.

**Piece C** — Generate a Demand Letter PDF (VF `renderAs="pdf"`) from a Demand record, attach it via ContentVersion/ContentDocumentLink, flag the Demand as PDF-generated.

## Dependencies

- E10 — `Demand__c` records exist with computed amounts (Principal / GST / TDS / Net Payable).
- E08 — `Booking__c` records exist; Booking has `Agreement__c` lookup (not `Related_Agreement__c` — spec was wrong; actual field is `Agreement__c`, label "Related Agreement").
- E02b / E03 — `Agreement__c` object with 17 custom fields; OWD = ControlledByParent.

## In-scope artefacts

**Piece A — Agreement (8 files):**
1. `triggers/AgreementTrigger.trigger` — fires on `before insert, after update`.
2. `classes/AgreementTriggerHandler.cls` — routes BEFORE_INSERT → `AgreementNamingService`; AFTER_UPDATE → `AgreementService.onAfterUpdate`. RecursionGuard on after-update.
3. `classes/AgreementNamingService.cls` — bulk-queries parent Booking names, sets `Name = 'AGR-' + Booking.Name`. Mirrors `DemandNamingService`.
4. `classes/AgreementService.cls` — invocable `createAgreements(List<AgreementRequest>)` + `onAfterUpdate` handler. Validates Booking_Status ∈ {Confirmed, Agreement Pending}, rejects duplicates (1:1 Booking↔Agreement), creates Agreement, updates Booking.Booking_Status→'Agreement Pending' + sets Booking.Agreement__c. After-update maps Status='Signed'→Booking='Agreement Signed', Status='Executed'→Booking='Registered'.
5. `classes/AgreementServiceTest.cls` — 7 tests.
6. `classes/TestDataFactory.cls` — +`createAgreement(bookingId, overrides)` (defaults Status='Not Started', does not pre-set Name).
7-8. Corresponding `-meta.xml` files.

**Piece C — Demand Letter PDF (6 files):**
9. `pages/DemandLetter.page` — VF renderAs="pdf", A4, inline CSS, professional layout (header with project + RERA, buyer block, booking details, demand particulars, amount table, bank details placeholder, signature block, footer).
10. `classes/DemandLetterController.cls` — reads `?id=<demandId>`, SOQL-traverses Demand→Booking→Unit→Tower→Project + Primary_Buyer + Payment_Schedule. Empty `ApexPages.currentPage()` branch tolerated for test-no-page-context.
11. `classes/DemandLetterService.cls` — invocable `generateDemandLetters`. Uses `Test.isRunningTest()` guard for `getContentAsPDF()`. Creates ContentVersion (Origin='H') → queries ContentDocumentId → creates ContentDocumentLink (ShareType='V', Visibility='AllUsers') → updates Demand.PDF_Generated__c=true + PDF_Attachment_Id__c.
12. `classes/DemandLetterServiceTest.cls` — 5 tests.
13-14. `-meta.xml` files (including page-meta.xml with `availableInTouch`, `confirmationTokenRequired`, `label`).

**NOT in E12:** Agreement for Sale PDF (template work too heavy for demo value — defer to Phase 2 or E23 polish), Commission Payout Statement PDF (E17), live e-sign integration (stub-only per Phase 1 spec — Agreement's e-sign fields remain display-only).

## Locked design decisions

**D1. Agreement field-name correction.** The spec referenced `Booking.Related_Agreement__c`; the actual field API name is `Booking.Agreement__c` (label "Related Agreement"). Service uses the API name. The spec has been corrected here for future reference.

**D2. `Agreement.Agreement_Value__c` is a Formula**, not a currency. Service does NOT set this on insert — it derives at query time via `Booking__r.Agreement_Value__c` which itself is a formula = `Quoted_Gross_Value__c`.

**D3. Agreement naming pattern:** `Name = 'AGR-' + Booking.Name`. Example: Booking `BKG-HPY-26-0001` → Agreement `AGR-BKG-HPY-26-0001`. Naming trigger runs in before-insert; parent Booking names bulk-queried (Booking__r.Name not accessible in before-insert).

**D4. Agreement Status → Booking Status mapping** (after-update only):
- `Signed` → Booking.Booking_Status = `Agreement Signed`
- `Executed` → Booking.Booking_Status = `Registered`
- All other status changes (`Draft Generated`, `Sent to Buyer`, `e-Sign Initiated`, `Cancelled`) → Booking untouched.
- Agreement Status transitions themselves are NOT state-machine-enforced (unlike Unit__c in E07) — status moves freely, business process is manual. Enforcement is a Phase-2 enhancement if demo feedback requires it.

**D5. 1:1 Booking↔Agreement.** Enforced by `createAgreements`: rejects if any Agreement already exists for the target Booking. `Agreement.Booking__c` is Master-Detail; `Booking.Agreement__c` is Lookup (one slot).

**D6. RecursionGuard key**: `'Agreement_afterUpdate'`. The existing `BookingTriggerHandler` only acts on `Payment_Plan__c` changes (E09), so updating Booking_Status + Agreement__c won't cascade. Still guarded belt-and-suspenders.

**D7. Demand Letter PDF architecture**: VF `renderAs="pdf"` (classic approach per Phase 1 Section 9). The controller loads all data in one SOQL with relationship traversal to avoid N+1 queries per PDF. The service is the invocable entry point for Flow integration.

**D8. `Test.isRunningTest()` guard** for `getContentAsPDF()` — this API returns null / throws in test context. Fallback `Blob.valueOf('TEST PDF CONTENT FOR '+d.Name)` lets us exercise the ContentVersion + ContentDocumentLink chain without a real PDF.

**D9. ContentVersion Origin='H'** (Content/Chatter Files). ContentDocumentLink ShareType='V' (Viewer), Visibility='AllUsers'. Standard values — no special permissions needed.

**D10. E-sign fields deferred.** Agreement has `ESign_Provider__c`, `ESign_Envelope_Id__c`, `ESign_Status__c` (from E02b). Display-only for now. Future epic will wire `IESignService` interface with a Stub and a Leegality adapter.

## Acceptance criteria

**Piece A:**

| # | Scenario | Expected |
|---|---|---|
| 1 | Create Agreement from Confirmed Booking | Agreement.Name='AGR-BKG-...', Status='Not Started', Booking.Status='Agreement Pending', Booking.Agreement__c set |
| 2 | Try to create a second Agreement for same Booking | AuraHandledException "Agreement already exists" |
| 3 | Try to create Agreement when Booking is Cancelled | AuraHandledException "Cannot create Agreement when Booking_Status is Cancelled" |
| 4 | Update Agreement.Status='Signed' + Signed_Date | Booking.Status = 'Agreement Signed' |
| 5 | Update Agreement.Status='Executed' + Registration_Date | Booking.Status = 'Registered' |
| 6 | Update Agreement.Status='Draft Generated' | Booking.Status unchanged (routing logic filter) |
| 7 | Bulk create 3 Agreements in one call | All 3 Agreements named correctly, all 3 Bookings updated |

**Piece C:**

| # | Scenario | Expected |
|---|---|---|
| 1 | Generate Demand Letter for 1 Demand | ContentVersion created (Title contains Demand.Name), ContentDocumentLink (ShareType='V') links CV to Demand, Demand.PDF_Generated=true, Demand.PDF_Attachment_Id__c set |
| 2 | Bulk-generate 3 PDFs in one call | 3 ContentVersions, 3 CDLs, all 3 Demands flagged PDF_Generated |
| 3 | Generate for a non-existent Demand (deleted) | AuraHandledException |
| 4 | Controller invoked with Demand id URL param | `ctrl.demand` loaded, all relationship fields populated |
| 5 | Controller invoked with no id param | `ctrl.demand` is null (no crash) |

## Iteration story

- Discovery surfaced a spec bug: `Booking.Related_Agreement__c` doesn't exist; actual field is `Booking.Agreement__c`. Corrected before generation.
- Discovery also confirmed `Agreement.Agreement_Value__c` is a formula → service must NOT set it. Adjusted design.
- Generation produced 10 new files + 1 modified.
- Dry-run deploy clean (32 components total including already-deployed prior-epic classes).
- Real deploy hit gotcha #31 (CLI cosmetic "Missing message metadata.transfer:Finalizing"); verified 32/32 components Succeeded via `sf project deploy report`.
- First test run: **51/52 pass**, 1 fail in `testCreateAgreement_BulkOperation` — `System.QueryException: List has no rows` when querying Booking after the 2nd close-won in a loop. Root cause: within a single test method, calling `seedAndCloseWon` three times left the `Opportunity_afterUpdate` RecursionGuard key set from the first call, so subsequent close-wons silently no-op'd the BookingService trigger. Fix: `RecursionGuard.resetAll()` at the top of the helper and again before `update opp`. Redeploy + re-run: 52/52 pass.
- Coverage: all E12 classes ≥90% (AgreementService 97%, DemandLetterController 91%, DemandLetterService 96%, AgreementNamingService + TriggerHandler + Trigger 100%).

## Files produced

```
force-app/main/default/
├── triggers/
│   ├── AgreementTrigger.trigger               NEW
│   └── AgreementTrigger.trigger-meta.xml      NEW
├── classes/
│   ├── AgreementTriggerHandler.cls            NEW
│   ├── AgreementNamingService.cls             NEW
│   ├── AgreementService.cls                   NEW   (96.7% covered)
│   ├── AgreementServiceTest.cls               NEW   (7 tests)
│   ├── DemandLetterController.cls             NEW   (90.6% covered)
│   ├── DemandLetterService.cls                NEW   (96.4% covered)
│   ├── DemandLetterServiceTest.cls            NEW   (5 tests)
│   └── TestDataFactory.cls                    MODIFIED (+createAgreement)
└── pages/
    ├── DemandLetter.page                      NEW
    └── DemandLetter.page-meta.xml             NEW
```

## Test results

```
Tests Ran           52
Outcome             Passed
Pass Rate           100%
Test Run Id         707Hp0000LleeN4
Test Execution Time 49.8s
```

Coverage of touched classes:
- AgreementService               97%  (58/60)
- AgreementNamingService        100%  (11/11)
- AgreementTrigger              100%
- AgreementTriggerHandler       100%  (6/6)
- DemandLetterService            96%  (53/55)
- DemandLetterController         91%  (29/32)
- ReceiptAllocationService       90%  (carried)
- DemandService                  96%  (carried)
- All other prior-epic services 96-100%

## Gotchas surfaced

No new CLAUDE.md entries needed. Honoured:

- **#30** — TestDataFactory respects Tower/Unit naming VRs (existing factory pattern).
- **#31** — CLI v2.84.6 cosmetic "Missing message metadata.transfer:Finalizing" on real deploy. Verified via `sf project deploy report`.
- **RecursionGuard multi-call helper pattern** — not a new gotcha, but a reminder: when a helper method triggers a guarded operation (here, close-won), and the helper is called multiple times within one test method, call `RecursionGuard.resetAll()` at the top of the helper AND between its DMLs. The fix is discoverable from the existing RecursionGuard design — no new documentation warranted.

## Implemented

- [x] AgreementTrigger (before insert, after update)
- [x] AgreementTriggerHandler routing with RecursionGuard('Agreement_afterUpdate')
- [x] AgreementNamingService — Name='AGR-'+Booking.Name
- [x] AgreementService.createAgreements — invocable with validation + Booking sync
- [x] AgreementService.onAfterUpdate — Signed→Agreement Signed, Executed→Registered
- [x] TestDataFactory.createAgreement
- [x] 7 AgreementServiceTest tests
- [x] DemandLetterController — full SOQL traversal for all letter data
- [x] DemandLetter.page — A4 VF PDF with professional styling
- [x] DemandLetterService — ContentVersion + ContentDocumentLink + Demand flagging
- [x] 5 DemandLetterServiceTest tests
- [x] Deployed to re-crm-sdo
- [x] All 52 tests pass
- [x] Coverage ≥ 90% on every new class

## Known follow-ups (next epics)

- **E17** — Commission Payout Statement PDF (same VF + ContentVersion pattern for Partner payouts).
- **E?** — Agreement for Sale PDF (deferred — 10+ pages of legal template is heavy for demo value).
- **E?** — E-sign live integration: wire `IESignService` with Stub + Leegality adapter. Agreement fields (ESign_Provider, ESign_Envelope_Id, ESign_Status) exist and are display-only.
- **E?** — Agreement status state machine enforcement (analogous to Unit__c E07).
- **E?** — Agreement Quick Action "Send for e-Sign" on record page.
- **E?** — Demand Letter email delivery (Messaging.SingleEmailMessage with PDF attachment) + buyer-portal self-serve download.
- **E?** — Demand Letter "Send to Buyer" Quick Action that wraps generate + email + flip `Sent_To_Buyer__c=true`, `Sent_DateTime__c=NOW()`.
- **E23 polish** — Quick Actions on Demand and Agreement record pages to invoke the services via Flow.
