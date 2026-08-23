/**
 * Auto Generated and Deployed by the Declarative Lookup Rollup Summaries Tool package (dlrs)
 **/
trigger dlrs_FinServ_FinancialAccountTrigger on FinServ__FinancialAccount__c
    (before delete, before insert, before update, after delete, after insert, after undelete, after update)
{
    dlrs.RollupService.triggerHandler(FinServ__FinancialAccount__c.SObjectType);
}