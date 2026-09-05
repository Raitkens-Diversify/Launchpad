@IsTest
private class DocumentServiceTest {

    private static Id householdRecordTypeId() {
        return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Household')
            .getRecordTypeId();
    }

    private static Account makeHousehold(String name) {
        Account household = new Account(
            Name = name,
            RecordTypeId = householdRecordTypeId(),
            Type = 'Prospect'
        );
        insert household;
        return household;
    }

    private static ContentVersion makeContentVersion(String title) {
        ContentVersion cv = new ContentVersion(
            Title = title,
            PathOnClient = title + '.txt',
            VersionData = Blob.valueOf('test data for ' + title),
            IsMajorVersion = true
        );
        insert cv;
        return [SELECT Id, ContentDocumentId, Title FROM ContentVersion WHERE Id = :cv.Id];
    }

    // A syntactically valid Id of the right type that no longer exists, for the "no matching rows"
    // branches -- insert then delete to guarantee it once existed and now points at nothing.
    private static Id deletedRequiredDocumentId() {
        Required_Documents__c doc = new Required_Documents__c(Name = 'Temp - to delete');
        insert doc;
        Id docId = doc.Id;
        delete doc;
        return docId;
    }

    // ---------------------------------------------------------------------
    // getUploadedFiles
    // ---------------------------------------------------------------------

    @IsTest
    static void getUploadedFilesReturnsEmptyForNullEnvelope() {
        Test.startTest();
        List<ContentVersion> result = DocumentService.getUploadedFiles(null);
        Test.stopTest();
        System.assertEquals(0, result.size());
    }

    @IsTest
    static void getUploadedFilesReturnsEmptyWhenNoDocumentsLinked() {
        Envelope__c envelope = new Envelope__c(Status__c = 'New');
        insert envelope;

        Test.startTest();
        List<ContentVersion> result = DocumentService.getUploadedFiles(envelope.Id);
        Test.stopTest();
        System.assertEquals(0, result.size());
    }

    @IsTest
    static void getUploadedFilesReturnsLatestVersionForLinkedDocument() {
        Envelope__c envelope = new Envelope__c(Status__c = 'New');
        insert envelope;

        ContentVersion cv = makeContentVersion('Envelope Upload');
        insert new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId = envelope.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );

        Test.startTest();
        List<ContentVersion> result = DocumentService.getUploadedFiles(envelope.Id);
        Test.stopTest();

        System.assertEquals(1, result.size());
        System.assertEquals('Envelope Upload', result[0].Title);
        System.assertEquals(cv.ContentDocumentId, result[0].ContentDocumentId);
    }

    // ---------------------------------------------------------------------
    // getRequiredDocuments
    // ---------------------------------------------------------------------

    @IsTest
    static void getRequiredDocumentsReturnsEmptyForNullEnvelope() {
        Test.startTest();
        List<Required_Documents__c> result = DocumentService.getRequiredDocuments(null);
        Test.stopTest();
        System.assertEquals(0, result.size());
    }

    @IsTest
    static void getRequiredDocumentsReturnsDocsLinkedToEnvelope() {
        Envelope__c envelope = new Envelope__c(Status__c = 'New');
        insert envelope;
        Required_Documents__c reqDoc = new Required_Documents__c(Name = 'Signature Page');
        insert reqDoc;
        insert new Envelope_Content__c(Envelope__c = envelope.Id, Required_Document__c = reqDoc.Id);

        Account owner = makeHousehold('Signee Household');
        insert new Signee__c(Required_Document__c = reqDoc.Id, Account__c = owner.Id);

        Test.startTest();
        List<Required_Documents__c> result = DocumentService.getRequiredDocuments(envelope.Id);
        Test.stopTest();

        System.assertEquals(1, result.size());
        System.assertEquals(reqDoc.Id, result[0].Id);
        System.assertEquals(1, result[0].Signee__r.size(),
            'The signee subquery should return the linked owner.');
    }

    // ---------------------------------------------------------------------
    // updateContentDocumentLinks / processContentDocumentLinks
    // ---------------------------------------------------------------------

    @IsTest
    static void updateContentDocumentLinksNoOpsForNullContentDocumentId() {
        Test.startTest();
        DocumentService.updateContentDocumentLinks(null, new List<Id>{ deletedRequiredDocumentId() }, null);
        Test.stopTest();
        // No exception means the early return was exercised; nothing to assert on data.
        System.assert(true);
    }

    @IsTest
    static void updateContentDocumentLinksNoOpsForNullOrEmptyIdLists() {
        ContentVersion cv = makeContentVersion('No Links Doc');
        Test.startTest();
        DocumentService.updateContentDocumentLinks(cv.ContentDocumentId, null, null);
        DocumentService.updateContentDocumentLinks(cv.ContentDocumentId, new List<Id>(), new List<Id>());
        Test.stopTest();
        System.assertEquals(0,
            [SELECT count() FROM ContentDocumentLink WHERE ContentDocumentId = :cv.ContentDocumentId
             AND LinkedEntityId != :UserInfo.getUserId()]);
    }

    @IsTest
    static void updateContentDocumentLinksSkipsWhenRequiredDocumentsDoNotExist() {
        ContentVersion cv = makeContentVersion('Missing Doc Link');
        Test.startTest();
        // A valid-format Id that matches no Required_Documents__c row: requiredDocs comes back
        // empty, so linkedIds stays empty and the method returns before querying/inserting links.
        DocumentService.updateContentDocumentLinks(
            cv.ContentDocumentId, new List<Id>{ deletedRequiredDocumentId() }, null);
        Test.stopTest();

        // Inserting a ContentVersion auto-links its ContentDocument to the running user, so that
        // link is excluded here -- this assertion is about links our own code would have created.
        System.assertEquals(0,
            [SELECT count() FROM ContentDocumentLink
             WHERE ContentDocumentId = :cv.ContentDocumentId AND LinkedEntityId != :UserInfo.getUserId()]);
    }

    @IsTest
    static void updateContentDocumentLinksInsertsLinksForRequiredDocumentAndItsRelatedRecords() {
        Account household = makeHousehold('Link Household');
        Account trust = makeHousehold('Link Trust Stand-in');
        Account business = makeHousehold('Link Business Stand-in');
        Financial_Account__c finAccount = new Financial_Account__c(Name = 'Link Financial Account');
        insert finAccount;

        Required_Documents__c reqDoc = new Required_Documents__c(
            Name = 'Multi Link Doc',
            Household__c = household.Id,
            Trust__c = trust.Id,
            Business__c = business.Id,
            Financial_Account__c = finAccount.Id
        );
        insert reqDoc;

        ContentVersion cv = makeContentVersion('Multi Link File');

        Test.startTest();
        DocumentService.updateContentDocumentLinks(
            cv.ContentDocumentId, new List<Id>{ reqDoc.Id }, null);
        Test.stopTest();

        Set<Id> linkedEntityIds = new Set<Id>();
        for (ContentDocumentLink cdl : [
            SELECT LinkedEntityId FROM ContentDocumentLink WHERE ContentDocumentId = :cv.ContentDocumentId
        ]) {
            linkedEntityIds.add(cdl.LinkedEntityId);
        }
        System.assert(linkedEntityIds.contains(reqDoc.Id), 'The required document itself should be linked.');
        System.assert(linkedEntityIds.contains(household.Id), 'The household should be linked.');
        System.assert(linkedEntityIds.contains(trust.Id), 'The trust should be linked.');
        System.assert(linkedEntityIds.contains(business.Id), 'The business should be linked.');
        System.assert(linkedEntityIds.contains(finAccount.Id), 'The financial account should be linked.');
    }

    @IsTest
    static void updateContentDocumentLinksDoesNotDuplicateExistingLinksThenUnlinksThem() {
        Account household = makeHousehold('Relink Household');
        Required_Documents__c reqDoc = new Required_Documents__c(
            Name = 'Relink Doc', Household__c = household.Id
        );
        insert reqDoc;
        ContentVersion cv = makeContentVersion('Relink File');

        Test.startTest();
        // First pass creates the links. (Inserting the ContentVersion auto-links its
        // ContentDocument to the running user; every count below excludes that link so it reflects
        // only what our own code created.)
        DocumentService.updateContentDocumentLinks(cv.ContentDocumentId, new List<Id>{ reqDoc.Id }, null);
        Integer afterFirstLink = [
            SELECT count() FROM ContentDocumentLink
            WHERE ContentDocumentId = :cv.ContentDocumentId AND LinkedEntityId != :UserInfo.getUserId()
        ];
        // Second pass with the same target must not create duplicates.
        DocumentService.updateContentDocumentLinks(cv.ContentDocumentId, new List<Id>{ reqDoc.Id }, null);
        Integer afterSecondLink = [
            SELECT count() FROM ContentDocumentLink
            WHERE ContentDocumentId = :cv.ContentDocumentId AND LinkedEntityId != :UserInfo.getUserId()
        ];
        // Now unlink.
        DocumentService.updateContentDocumentLinks(cv.ContentDocumentId, null, new List<Id>{ reqDoc.Id });
        Integer afterUnlink = [
            SELECT count() FROM ContentDocumentLink
            WHERE ContentDocumentId = :cv.ContentDocumentId AND LinkedEntityId != :UserInfo.getUserId()
        ];
        Test.stopTest();

        System.assertEquals(2, afterFirstLink, 'The doc and its household should both be linked.');
        System.assertEquals(afterFirstLink, afterSecondLink,
            'Re-running the same link request should not create duplicate links.');
        System.assertEquals(0, afterUnlink, 'Unlinking should remove every link this file has.');
    }

    // ---------------------------------------------------------------------
    // removeFile
    // ---------------------------------------------------------------------

    @IsTest
    static void removeFileDeletesTheContentDocument() {
        ContentVersion cv = makeContentVersion('Remove Me');

        Test.startTest();
        DocumentService.removeFile(cv.ContentDocumentId);
        Test.stopTest();

        System.assertEquals(0,
            [SELECT count() FROM ContentDocument WHERE Id = :cv.ContentDocumentId]);
    }

    @IsTest
    static void removeFileIsANoOpForAMissingDocument() {
        Test.startTest();
        DocumentService.removeFile(deletedRequiredDocumentId());
        Test.stopTest();
        // No matching ContentDocument row means the query returns nothing to delete; no exception
        // should propagate.
        System.assert(true);
    }
}