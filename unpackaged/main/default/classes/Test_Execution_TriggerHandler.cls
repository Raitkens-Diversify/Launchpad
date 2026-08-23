/**
 * Test_Execution_TriggerHandler — maintains the unique Identity_Key__c
 * (case:cycle-or-STANDALONE:tester-or-UNCLAIMED) on every write, from any
 * path. The DB-level guard for the identity triple: races become caught
 * DUPLICATE_VALUE failures, never silently merged results. Idempotent, so
 * the rollup engine's own execution updates don't re-enter anything.
 */
public without sharing class Test_Execution_TriggerHandler {

    public void stampIdentity(List<Test_Execution__c> executions) {
        UatExecutionService.stampIdentityKeys(executions);
    }
}