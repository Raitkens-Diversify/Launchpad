@isTest
private class ResourceDownloadTrackerTest {

    /** The deployer's own access is not enough in production; see HelpCenterTestDataFactory. */
    @TestSetup
    static void grantAccess() {
        HelpCenterTestDataFactory.grantAdminToRunningUser();
    }

    private static Resource__c makeResource(Decimal startCount) {
        Resource_Category__c cat = new Resource_Category__c(Name = 'C', Slug__c = 'c', Is_Active__c = true);
        insert cat;
        Resource__c r = new Resource__c(
            Name = 'R', Slug__c = 'r', Category__c = cat.Id, Resource_Type__c = 'PDF', Is_Active__c = true,
            Download_Count__c = startCount);
        insert r;
        return r;
    }

    @isTest
    static void incrementsFromNull() {
        Resource__c r = makeResource(null);

        Test.startTest();
        System.enqueueJob(new ResourceDownloadTracker(r.Id));
        Test.stopTest();

        Assert.areEqual(1, [SELECT Download_Count__c FROM Resource__c WHERE Id = :r.Id].Download_Count__c,
            'Counter goes from 0/null to 1.');
    }

    @isTest
    static void incrementsExistingCount() {
        Resource__c r = makeResource(41);

        Test.startTest();
        System.enqueueJob(new ResourceDownloadTracker(r.Id));
        Test.stopTest();

        Assert.areEqual(42, [SELECT Download_Count__c FROM Resource__c WHERE Id = :r.Id].Download_Count__c,
            'Counter increments the existing value by exactly one.');
    }

    @isTest
    static void nullResourceIsNoop() {
        Test.startTest();
        Integer before = Limits.getDmlStatements();
        new ResourceDownloadTracker(null).execute(null); // must not throw
        Assert.areEqual(before, Limits.getDmlStatements(), 'Null id performs no DML.');
        Test.stopTest();
    }

    @isTest
    static void deletedResourceIsNoop() {
        Resource__c r = makeResource(3);
        Id gone = r.Id;
        delete r;

        Test.startTest();
        System.enqueueJob(new ResourceDownloadTracker(gone)); // must not throw
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Resource__c WHERE Id = :gone], 'Nothing to count against.');
    }

    @isTest
    static void runsInSystemContextForRestrictedUser() {
        // A restricted user cannot read Resource__c under sharing, but the
        // class is `without sharing`, so the row is found and the system-context
        // update succeeds — the point of the sharing declaration. Assert that.
        Resource__c r = makeResource(0);
        User bare;
        System.runAs(HelpCenterTestDataFactory.currentUser()) {
            bare = HelpCenterTestDataFactory.createUser('rdtbare', null);
        }

        Test.startTest();
        System.runAs(bare) {
            System.enqueueJob(new ResourceDownloadTracker(r.Id));
        }
        Test.stopTest();

        Assert.areEqual(1, [SELECT Download_Count__c FROM Resource__c WHERE Id = :r.Id].Download_Count__c,
            'without sharing lets a read-only site member increment the counter.');
    }
}