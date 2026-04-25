public with sharing class BuyerProfileController {

    @AuraEnabled(cacheable=true)
    public static BuyerData getBuyerData(Id accountId) {
        if (accountId == null) return null;

        List<Account> accounts = [
            SELECT Id, Name, PAN__c, KYC_Status__c, KYC_Verified_Date__c,
                   Buyer_Type__c, NRI_Status__c, DOB__c, Phone
            FROM Account
            WHERE Id = :accountId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        if (accounts.isEmpty()) return null;
        Account a = accounts[0];

        BuyerData d = new BuyerData();
        d.accountId = a.Id;
        d.name = a.Name;
        d.pan = a.PAN__c;
        d.kycStatus = a.KYC_Status__c;
        d.kycVerifiedDate = a.KYC_Verified_Date__c;
        d.buyerType = a.Buyer_Type__c;
        d.nriStatus = a.NRI_Status__c == true;
        d.dob = a.DOB__c;
        d.phone = a.Phone;

        d.bookingCount = 0;
        d.totalInvestment = 0;
        for (Booking__c b : [
            SELECT Id, Total_Consideration__c FROM Booking__c
            WHERE Primary_Buyer__c = :accountId
            WITH SECURITY_ENFORCED
        ]) {
            d.bookingCount++;
            if (b.Total_Consideration__c != null) {
                d.totalInvestment += b.Total_Consideration__c;
            }
        }

        return d;
    }

    public class BuyerData {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String name;
        @AuraEnabled public String pan;
        @AuraEnabled public String kycStatus;
        @AuraEnabled public Date kycVerifiedDate;
        @AuraEnabled public String buyerType;
        @AuraEnabled public Boolean nriStatus;
        @AuraEnabled public Date dob;
        @AuraEnabled public String phone;
        @AuraEnabled public Integer bookingCount;
        @AuraEnabled public Decimal totalInvestment;
    }
}
