/**
 * Auto Generated and Deployed by the Declarative Lookup Rollup Summaries Tool package (dlrs)
 **/
@IsTest
private class dlrs_FinServ_FinancialAccountTest
{
    @IsTest
    private static void testTrigger()
    {
        // Force the dlrs_FinServ_FinancialAccountTrigger to be invoked, fails the test if org config or other Apex code prevents this.
        dlrs.RollupService.testHandler(new FinServ__FinancialAccount__c());
    }
}