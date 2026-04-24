public with sharing class DemandLetterService {

    public class GenerateDemandLetterRequest {
        @InvocableVariable(required=true label='Demand Id')
        public Id demandId;
    }

    @InvocableMethod(label='Generate Demand Letter PDF' description='Renders the DemandLetter VF page as PDF and attaches it to the Demand record via ContentVersion.')
    public static void generateDemandLetters(List<GenerateDemandLetterRequest> requests) {
        if (requests == null || requests.isEmpty()) return;

        Set<Id> demandIds = new Set<Id>();
        for (GenerateDemandLetterRequest r : requests) {
            if (r.demandId == null) {
                throw new AuraHandledException('Demand Id is required.');
            }
            demandIds.add(r.demandId);
        }

        Map<Id, Demand__c> demandsById = new Map<Id, Demand__c>([
            SELECT Id, Name, PDF_Generated__c
            FROM Demand__c
            WHERE Id IN :demandIds
            WITH SECURITY_ENFORCED
        ]);

        List<ContentVersion> versionsToInsert = new List<ContentVersion>();
        Map<Integer, Id> indexToDemandId = new Map<Integer, Id>();
        Integer idx = 0;

        for (GenerateDemandLetterRequest r : requests) {
            Demand__c d = demandsById.get(r.demandId);
            if (d == null) {
                throw new AuraHandledException('Demand not found: ' + r.demandId);
            }

            PageReference pageRef = Page.DemandLetter;
            pageRef.getParameters().put('id', d.Id);
            Blob pdf;
            if (Test.isRunningTest()) {
                pdf = Blob.valueOf('TEST PDF CONTENT FOR ' + d.Name);
            } else {
                pdf = pageRef.getContentAsPDF();
            }

            ContentVersion cv = new ContentVersion(
                Title = 'Demand Letter - ' + d.Name,
                PathOnClient = d.Name + '.pdf',
                VersionData = pdf,
                Origin = 'H'
            );
            versionsToInsert.add(cv);
            indexToDemandId.put(idx, d.Id);
            idx++;
        }

        insert versionsToInsert;

        Set<Id> contentVersionIds = new Set<Id>();
        for (ContentVersion cv : versionsToInsert) contentVersionIds.add(cv.Id);

        Map<Id, Id> contentDocIdByVersion = new Map<Id, Id>();
        for (ContentVersion cv : [
            SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id IN :contentVersionIds
        ]) {
            contentDocIdByVersion.put(cv.Id, cv.ContentDocumentId);
        }

        List<ContentDocumentLink> linksToInsert = new List<ContentDocumentLink>();
        List<Demand__c> demandsToUpdate = new List<Demand__c>();
        for (Integer i = 0; i < versionsToInsert.size(); i++) {
            ContentVersion cv = versionsToInsert[i];
            Id demandId = indexToDemandId.get(i);
            Id docId = contentDocIdByVersion.get(cv.Id);

            linksToInsert.add(new ContentDocumentLink(
                ContentDocumentId = docId,
                LinkedEntityId = demandId,
                ShareType = 'V',
                Visibility = 'AllUsers'
            ));

            demandsToUpdate.add(new Demand__c(
                Id = demandId,
                PDF_Generated__c = true,
                PDF_Attachment_Id__c = docId
            ));
        }

        insert linksToInsert;
        update demandsToUpdate;
    }
}
