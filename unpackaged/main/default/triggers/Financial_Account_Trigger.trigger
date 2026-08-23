trigger Financial_Account_Trigger on Financial_Account__c (before insert, before update, before delete, after insert, after update, after delete) {
  system.debug('Hii');
    Financial_Account_TriggerHandler handler = new Financial_Account_TriggerHandler();
    if (Trigger.isBefore) {
        if(Trigger.isInsert){
            handler.isBeforeInsert(Trigger.new);
        }else if(Trigger.isUpdate){
            handler.isBeforeUpdate(Trigger.newMap, Trigger.oldMap);
        }else if(Trigger.isDelete){
            handler.isBeforeDelete(Trigger.oldMap);
        }      
    } else if (Trigger.isAfter) {
        if(Trigger.isInsert){
            handler.isAfterInsert(Trigger.newMap);
        }else if(Trigger.isUpdate){
            handler.isAfterUpdate(Trigger.newMap, Trigger.oldMap);
        }else if(Trigger.isDelete){
            handler.isAfterDelete(Trigger.oldMap);
        }else if(Trigger.isUndelete)  {
            handler.isAfterUnDelete(Trigger.newMap);
        }
    }
}