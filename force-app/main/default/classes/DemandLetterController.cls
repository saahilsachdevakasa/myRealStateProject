public with sharing class DemandLetterController {

    public Demand__c demand { get; private set; }
    public Booking__c booking { get; private set; }
    public Unit__c unit { get; private set; }
    public Project__c project { get; private set; }
    public Account buyer { get; private set; }
    public Booking_Payment_Schedule__c schedule { get; private set; }
    public String buyerName { get; private set; }
    public String unitDisplay { get; private set; }
    public String milestoneLabel { get; private set; }

    public DemandLetterController() {
        Id demandId = ApexPages.currentPage() == null
            ? null
            : ApexPages.currentPage().getParameters().get('id');
        if (demandId != null) {
            loadData(demandId);
        }
    }

    private void loadData(Id demandId) {
        List<Demand__c> demands = [
            SELECT Id, Name, Demand_Seq__c, Raised_Date__c, Due_Date__c,
                   Principal_Amount__c, GST_Amount__c, TDS_Amount__c, Net_Payable__c,
                   Total_Gross__c, Status__c, Amount_Received__c, Outstanding__c,
                   Booking__c, Payment_Schedule__c,
                   Booking__r.Name, Booking__r.Booking_Date__c,
                   Booking__r.Primary_Buyer__c,
                   Booking__r.Primary_Buyer__r.Name,
                   Booking__r.Primary_Buyer__r.BillingStreet,
                   Booking__r.Primary_Buyer__r.BillingCity,
                   Booking__r.Primary_Buyer__r.BillingState,
                   Booking__r.Primary_Buyer__r.BillingPostalCode,
                   Booking__r.Unit__c,
                   Booking__r.Unit__r.Name,
                   Booking__r.Unit__r.Configuration__c,
                   Booking__r.Unit__r.Super_BuiltUp_Area_sqft__c,
                   Booking__r.Unit__r.Carpet_Area_sqft__c,
                   Booking__r.Unit__r.Tower__c,
                   Booking__r.Unit__r.Tower__r.Project__c,
                   Booking__r.Unit__r.Tower__r.Project__r.Name,
                   Booking__r.Unit__r.Tower__r.Project__r.RERA_Number__c,
                   Booking__r.Unit__r.Tower__r.Project__r.RERA_State__c,
                   Payment_Schedule__r.Sequence__c,
                   Payment_Schedule__r.Milestone_Trigger__c,
                   Payment_Schedule__r.Percentage__c
            FROM Demand__c
            WHERE Id = :demandId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (demands.isEmpty()) return;

        this.demand = demands[0];
        this.booking = demand.Booking__r;
        this.unit = booking.Unit__r;
        this.project = unit.Tower__r.Project__r;
        this.buyer = booking.Primary_Buyer__r;
        this.schedule = demand.Payment_Schedule__r;

        this.buyerName = (buyer != null) ? buyer.Name : 'Buyer';
        this.unitDisplay = (unit != null)
            ? unit.Name + ' (' + (unit.Configuration__c == null ? '-' : unit.Configuration__c) + ')'
            : '-';
        this.milestoneLabel = (schedule != null && schedule.Milestone_Trigger__c != null)
            ? 'Milestone ' + String.valueOf(schedule.Sequence__c.intValue()) + ' — ' + schedule.Milestone_Trigger__c
            : '-';
    }
}
