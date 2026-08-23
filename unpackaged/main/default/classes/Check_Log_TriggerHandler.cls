public class Check_Log_TriggerHandler {
    // Check Log field population, owner assignment, and team sharing moved to
    // Check_Log_Before_Save and Check_Log_After_Save record-triggered flows.
    public void isBeforeInsert(List<Check_Log__c> newList){
    }

    public void isBeforeUpdate(Map<Id, Check_Log__c> newMap, Map<Id, Check_Log__c> oldMap){
    }

    public void isBeforeDelete(Map<Id, Check_Log__c> oldMap){
    }

    public void isAfterInsert(Map<Id, Check_Log__c> newMap){
    }

    public void isAfterUpdate(Map<Id, Check_Log__c> newMap, Map<Id, Check_Log__c> oldMap){
    }

    public void isAfterDelete(Map<Id, Check_Log__c> oldMap){
    }

    public void isAfterUndelete(Map<Id, Check_Log__c> newMap){
    }
}