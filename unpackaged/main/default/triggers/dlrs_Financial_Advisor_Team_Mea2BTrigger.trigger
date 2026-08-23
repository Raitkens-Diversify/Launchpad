/**
 * Auto Generated and Deployed by the Declarative Lookup Rollup Summaries Tool package (dlrs)
 **/
trigger dlrs_Financial_Advisor_Team_Mea2BTrigger on Financial_Advisor_Team_Member__c
    (before delete, before insert, before update, after delete, after insert, after undelete, after update)
{
    dlrs.RollupService.triggerHandler(Financial_Advisor_Team_Member__c.SObjectType);
}