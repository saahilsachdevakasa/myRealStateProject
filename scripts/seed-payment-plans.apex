// E09 — Seed 3 Payment Plans (CLP, DLP, PLP) with their milestones.
//
// Plans seeded as INACTIVE. Activate via Setup UI:
//   Object Manager → Payment Plan → [record] → Edit → Active = true.
// See CLAUDE.md gotcha #40 for why a single-transaction Active=true seed isn't
// possible (MD rollup recalc on the parent Plan during each child milestone
// insert fires the Active_Plan_Total_Pct_Must_Be_100 VR with partial rollup
// state, regardless of insert order or transaction boundaries).
//
// Idempotent: deletes existing plans by Plan_Code__c first (MD cascade removes milestones).
//
// Run: sf apex run --file scripts/seed-payment-plans.apex --target-org re-crm-sdo

delete [SELECT Id FROM Payment_Plan__c WHERE Plan_Code__c IN ('CLP', 'DLP', 'PLP')];

List<Payment_Plan__c> plans = new List<Payment_Plan__c>{
    new Payment_Plan__c(
        Name = 'Construction Linked Plan',
        Plan_Code__c = 'CLP',
        Active__c = false,
        Applicable_Project_Types__c = 'Residential',
        Description__c = 'Standard construction-linked 10-milestone plan for residential projects.'
    ),
    new Payment_Plan__c(
        Name = 'Down Payment Plan',
        Plan_Code__c = 'DLP',
        Active__c = false,
        Applicable_Project_Types__c = 'Residential',
        Description__c = 'Aggressive 3-milestone front-loaded plan (80% within 90 days of booking).'
    ),
    new Payment_Plan__c(
        Name = 'Possession Linked Plan',
        Plan_Code__c = 'PLP',
        Active__c = false,
        Applicable_Project_Types__c = 'Residential',
        Description__c = 'Possession-weighted 4-milestone plan (70% at possession).'
    )
};
insert plans;

Id clpId = plans[0].Id;
Id dlpId = plans[1].Id;
Id plpId = plans[2].Id;

List<Payment_Plan_Milestone__c> milestones = new List<Payment_Plan_Milestone__c>{
    // CLP — 10 milestones (10+10+10+10+10+10+7.5+7.5+7.5+17.5 = 100)
    new Payment_Plan_Milestone__c(Payment_Plan__c=clpId, Sequence__c=1,  Trigger__c='On Booking',                    Trigger_Type__c='Booking',      Days_From_Trigger__c=0,  Percentage__c=10,   Active__c=true, Description__c='Booking amount'),
    new Payment_Plan_Milestone__c(Payment_Plan__c=clpId, Sequence__c=2,  Trigger__c='Within 30 days of booking',     Trigger_Type__c='Time-Based',   Days_From_Trigger__c=30, Percentage__c=10,   Active__c=true, Description__c='30-day balance'),
    new Payment_Plan_Milestone__c(Payment_Plan__c=clpId, Sequence__c=3,  Trigger__c='On casting of 1st floor slab',  Trigger_Type__c='Construction', Percentage__c=10,   Active__c=true),
    new Payment_Plan_Milestone__c(Payment_Plan__c=clpId, Sequence__c=4,  Trigger__c='On casting of 4th floor slab',  Trigger_Type__c='Construction', Percentage__c=10,   Active__c=true),
    new Payment_Plan_Milestone__c(Payment_Plan__c=clpId, Sequence__c=5,  Trigger__c='On casting of 8th floor slab',  Trigger_Type__c='Construction', Percentage__c=10,   Active__c=true),
    new Payment_Plan_Milestone__c(Payment_Plan__c=clpId, Sequence__c=6,  Trigger__c='On casting of 12th floor slab', Trigger_Type__c='Construction', Percentage__c=10,   Active__c=true),
    new Payment_Plan_Milestone__c(Payment_Plan__c=clpId, Sequence__c=7,  Trigger__c='On casting of last floor slab', Trigger_Type__c='Construction', Percentage__c=7.5,  Active__c=true),
    new Payment_Plan_Milestone__c(Payment_Plan__c=clpId, Sequence__c=8,  Trigger__c='On completion of brickwork',    Trigger_Type__c='Construction', Percentage__c=7.5,  Active__c=true),
    new Payment_Plan_Milestone__c(Payment_Plan__c=clpId, Sequence__c=9,  Trigger__c='On completion of plaster',      Trigger_Type__c='Construction', Percentage__c=7.5,  Active__c=true),
    new Payment_Plan_Milestone__c(Payment_Plan__c=clpId, Sequence__c=10, Trigger__c='On Possession',                 Trigger_Type__c='Possession',   Percentage__c=17.5, Active__c=true),

    // DLP — 3 milestones (10+80+10 = 100)
    new Payment_Plan_Milestone__c(Payment_Plan__c=dlpId, Sequence__c=1, Trigger__c='On Booking',                Trigger_Type__c='Booking',    Days_From_Trigger__c=0,  Percentage__c=10, Active__c=true),
    new Payment_Plan_Milestone__c(Payment_Plan__c=dlpId, Sequence__c=2, Trigger__c='Within 90 days of booking', Trigger_Type__c='Time-Based', Days_From_Trigger__c=90, Percentage__c=80, Active__c=true),
    new Payment_Plan_Milestone__c(Payment_Plan__c=dlpId, Sequence__c=3, Trigger__c='On Possession',             Trigger_Type__c='Possession', Percentage__c=10, Active__c=true),

    // PLP — 4 milestones (10+10+10+70 = 100)
    new Payment_Plan_Milestone__c(Payment_Plan__c=plpId, Sequence__c=1, Trigger__c='On Booking',     Trigger_Type__c='Booking',    Days_From_Trigger__c=0,   Percentage__c=10, Active__c=true),
    new Payment_Plan_Milestone__c(Payment_Plan__c=plpId, Sequence__c=2, Trigger__c='Within 60 days', Trigger_Type__c='Time-Based', Days_From_Trigger__c=60,  Percentage__c=10, Active__c=true),
    new Payment_Plan_Milestone__c(Payment_Plan__c=plpId, Sequence__c=3, Trigger__c='Within 120 days',Trigger_Type__c='Time-Based', Days_From_Trigger__c=120, Percentage__c=10, Active__c=true),
    new Payment_Plan_Milestone__c(Payment_Plan__c=plpId, Sequence__c=4, Trigger__c='On Possession',  Trigger_Type__c='Possession', Percentage__c=70, Active__c=true)
};
insert milestones;

System.debug('Seeded 3 Payment Plans (Active=false) and ' + milestones.size() + ' milestones (CLP: 10, DLP: 3, PLP: 4). Activate via Setup UI when needed.');
