@isTest
private class HelpGuidePublishCallbackTest {

    /** The deployer's own access is not enough in production; see HelpCenterTestDataFactory. */
    @TestSetup
    static void grantAccess() {
        HelpCenterTestDataFactory.grantAdminToRunningUser();
    }

    private class TestContext extends Metadata.DeployCallbackContext {
        public override Id getCallbackJobId() {
            return '0Af000000000001AAA';
        }
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
    static void successClearsPreviousError() {
        Id gId = draft();
        update new Help_Guide_Draft__c(Id = gId, Publish_Error__c = 'FAILED: earlier attempt');
        Metadata.DeployResult result = new Metadata.DeployResult();
        result.status = Metadata.DeployStatus.SUCCEEDED;

        new HelpGuidePublishCallback(gId).handleResult(result, new TestContext());

        Help_Guide_Draft__c g = [SELECT Published__c, Publish_Error__c FROM Help_Guide_Draft__c WHERE Id = :gId];
        Assert.isTrue(g.Published__c, 'Published.');
        Assert.isNull(g.Publish_Error__c, 'A later success wipes the stale error.');
    }

    @isTest
    static void failureRecordsError() {
        Id gId = draft();
        Metadata.DeployResult result = new Metadata.DeployResult();
        result.status = Metadata.DeployStatus.FAILED;
        Metadata.DeployDetails details = new Metadata.DeployDetails();
        Metadata.DeployMessage msg = new Metadata.DeployMessage();
        msg.problem = 'Something broke';
        Metadata.DeployMessage msg2 = new Metadata.DeployMessage();
        msg2.problem = 'Second problem';
        details.componentFailures = new List<Metadata.DeployMessage>{ msg, msg2 };
        result.details = details;
        result.errorMessage = 'Generic message loses to the component problem';

        Test.startTest();
        new HelpGuidePublishCallback(gId).handleResult(result, null);
        Test.stopTest();

        Help_Guide_Draft__c g = [SELECT Published__c, Publish_Error__c FROM Help_Guide_Draft__c WHERE Id = :gId];
        Assert.isFalse(g.Published__c, 'Not published on failure.');
        Assert.isTrue(g.Publish_Error__c.startsWith('Failed: '), 'Status prefix: ' + g.Publish_Error__c);
        Assert.isTrue(g.Publish_Error__c.contains('Something broke'), 'Error captured.');
        Assert.isFalse(g.Publish_Error__c.contains('Second problem'), 'Only the first problem is reported.');
        Assert.isFalse(g.Publish_Error__c.contains('Generic message'), 'Component problem outranks errorMessage.');
    }

    @isTest
    static void failureFallsBackToErrorMessage() {
        Id gId = draft();
        Metadata.DeployResult result = new Metadata.DeployResult();
        result.status = Metadata.DeployStatus.CANCELED;
        result.details = new Metadata.DeployDetails(); // no componentFailures
        result.errorMessage = 'Canceled by an administrator';

        new HelpGuidePublishCallback(gId).handleResult(result, new TestContext());

        Help_Guide_Draft__c g = [SELECT Published__c, Publish_Error__c FROM Help_Guide_Draft__c WHERE Id = :gId];
        Assert.isFalse(g.Published__c, 'Not published.');
        Assert.areEqual('Canceled: Canceled by an administrator', g.Publish_Error__c);
    }

    @isTest
    static void failureWithNoDetailsReportsStatusOnly() {
        Id gId = draft();
        Metadata.DeployResult result = new Metadata.DeployResult();
        result.status = Metadata.DeployStatus.FAILED;

        new HelpGuidePublishCallback(gId).handleResult(result, new TestContext());

        Help_Guide_Draft__c g = [SELECT Publish_Error__c FROM Help_Guide_Draft__c WHERE Id = :gId];
        Assert.areEqual('Failed', g.Publish_Error__c, 'Bare status when nothing else is known.');
    }

    @isTest
    static void failureMessageIsAbbreviated() {
        Id gId = draft();
        Metadata.DeployResult result = new Metadata.DeployResult();
        result.status = Metadata.DeployStatus.FAILED;
        result.errorMessage = 'x'.repeat(600);

        new HelpGuidePublishCallback(gId).handleResult(result, new TestContext());

        Help_Guide_Draft__c g = [SELECT Publish_Error__c FROM Help_Guide_Draft__c WHERE Id = :gId];
        Assert.areEqual(255, g.Publish_Error__c.length(), 'Abbreviated to the 255-char field.');
    }

    @isTest
    static void nullResultTreatedAsFailure() {
        Id gId = draft();

        new HelpGuidePublishCallback(gId).handleResult(null, new TestContext());

        Help_Guide_Draft__c g = [SELECT Published__c, Publish_Error__c FROM Help_Guide_Draft__c WHERE Id = :gId];
        Assert.isFalse(g.Published__c, 'Not published.');
        Assert.areEqual('Deployment failed (no result returned).', g.Publish_Error__c);
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
        Assert.areEqual(0, [SELECT COUNT() FROM Help_Guide_Draft__c WHERE Id = :gId], 'Handled missing draft.');
    }
}