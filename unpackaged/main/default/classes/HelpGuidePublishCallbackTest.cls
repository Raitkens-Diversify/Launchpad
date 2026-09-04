@isTest
private class HelpGuidePublishCallbackTest {

    /** The deployer's own access is not enough in production; see HelpCenterTestDataFactory. */
    @TestSetup
    static void grantAccess() {
        HelpCenterTestDataFactory.grantAdminToRunningUser();
    }

    private static Id draft() {
        Help_Guide_Draft__c g = new Help_Guide_Draft__c(
            Name = 'Get Help', Guide_Key__c = 'get_help', Label__c = 'Get Help',
            Active__c = true, Version__c = 1, Published__c = false);
        insert g;
        return g.Id;
    }

    @isTest
    static void successMarksPublished() {
        Id gId = draft();
        Metadata.DeployResult result = new Metadata.DeployResult();
        result.status = Metadata.DeployStatus.SUCCEEDED;

        Test.startTest();
        new HelpGuidePublishCallback(gId).handleResult(result, null);
        Test.stopTest();

        Help_Guide_Draft__c g = [
            SELECT Published__c, Last_Published__c, Publish_Error__c FROM Help_Guide_Draft__c WHERE Id = :gId
        ];
        Assert.isTrue(g.Published__c, 'Marked published on success.');
        Assert.isNotNull(g.Last_Published__c, 'Stamped publish time.');
        Assert.isNull(g.Publish_Error__c, 'No error on success.');
    }

    @isTest
    static void failureRecordsError() {
        Id gId = draft();
        Metadata.DeployResult result = new Metadata.DeployResult();
        result.status = Metadata.DeployStatus.FAILED;
        Metadata.DeployDetails details = new Metadata.DeployDetails();
        Metadata.DeployMessage msg = new Metadata.DeployMessage();
        msg.problem = 'Something broke';
        details.componentFailures = new List<Metadata.DeployMessage>{ msg };
        result.details = details;

        Test.startTest();
        new HelpGuidePublishCallback(gId).handleResult(result, null);
        Test.stopTest();

        Help_Guide_Draft__c g = [SELECT Published__c, Publish_Error__c FROM Help_Guide_Draft__c WHERE Id = :gId];
        Assert.isFalse(g.Published__c, 'Not published on failure.');
        Assert.isTrue(g.Publish_Error__c.contains('Something broke'), 'Error captured.');
    }

    @isTest
    static void missingDraftIsNoop() {
        // Use a valid-type but now-deleted draft Id so the SObject type is correct.
        Id gId = draft();
        delete new Help_Guide_Draft__c(Id = gId);

        Metadata.DeployResult result = new Metadata.DeployResult();
        result.status = Metadata.DeployStatus.SUCCEEDED;

        Test.startTest();
        new HelpGuidePublishCallback(gId).handleResult(result, null); // must not throw
        Test.stopTest();
        Assert.isTrue(true, 'Handled missing draft.');
    }
}