@isTest
private class ResourceDownloadTrackerTest {

    /** The deployer's own access is not enough in production; see HelpCenterTestDataFactory. */
    @TestSetup
    static void grantAccess() {
        HelpCenterTestDataFactory.grantAdminToRunningUser();
    }

    @isTest
    static void incrementsFromNull() {
        Resource_Category__c cat = new Resource_Category__c(Name = 'C', Slug__c = 'c', Is_Active__c = true);
        insert cat;
        Resource__c r = new Resource__c(
            Name = 'R', Slug__c = 'r', Category__c = cat.Id, Resource_Type__c = 'PDF', Is_Active__c = true);
        insert r;

        Test.startTest();
        System.enqueueJob(new ResourceDownloadTracker(r.Id));
        Test.stopTest();

        Assert.areEqual(1, [SELECT Download_Count__c FROM Resource__c WHERE Id = :r.Id].Download_Count__c,
            'Counter goes from 0/null to 1.');
    }

    @isTest
    static void nullResourceIsNoop() {
        Test.startTest();
        new ResourceDownloadTracker(null).execute(null); // must not throw
        Test.stopTest();
        Assert.isTrue(true, 'Null id handled.');
    }
}