/**
 * Tests for UatStaleClaimScheduler — the nightly sweep wrapper. The release
 * state machine itself is covered by UatExecutionServiceTest
 * (staleClaimsAutoReleaseAfterCycleWindow); these verify the Schedulable
 * plumbing: execute() delegates to the service, and the job schedules.
 */
@IsTest
private class UatStaleClaimSchedulerTest {

    @TestSetup
    static void setup() {
        UatTestDataFactory.createTesterUser('uattst1');
    }

    private static User tester1() {
        return [SELECT Id FROM User WHERE LastName = 'UAT uattst1' LIMIT 1];
    }

    @IsTest
    static void executeReleasesStaleClaims() {
        UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
        Test_Case__c c1 = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1001);
        Test_Cycle__c cycle = UatTestDataFactory.makeCycle('Sprint 1', null, null, new List<Id>{ c1.Id });
        cycle.Stale_Claim_Days__c = 7;
        update cycle;
        Test_Execution__c claimed = UatExecutionService.claimSeat(cycle.Id, c1.Id, tester1().Id);

        Test.startTest();
        // execute() called directly: statics (the clock override) don't
        // survive into stopTest's async replay, and the cron plumbing is
        // covered separately below.
        UatExecutionService.nowOverride = System.now().addDays(8);
        new UatStaleClaimScheduler().execute(null);
        UatExecutionService.nowOverride = null;
        Test.stopTest();

        Assert.isNull([
            SELECT Assigned_Tester__c FROM Test_Execution__c WHERE Id = :claimed.Id
        ].Assigned_Tester__c, 'The stale claim went back to the pool.');
        Assert.areEqual(1, [
            SELECT COUNT() FROM Test_Assignment_Event__c WHERE Action__c = 'Auto Released'
        ]);
    }

    @IsTest
    static void jobSchedules() {
        Test.startTest();
        Id jobId = System.schedule('UAT Stale Claim Release (test)', '0 0 6 * * ?',
            new UatStaleClaimScheduler());
        Test.stopTest();

        CronTrigger cron = [
            SELECT CronExpression, TimesTriggered FROM CronTrigger WHERE Id = :jobId
        ];
        Assert.areEqual('0 0 6 * * ?', cron.CronExpression);
    }
}