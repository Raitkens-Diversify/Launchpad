trigger User_Trigger on User (before insert, before update, before delete, after insert, after update, after delete, after undelete) {
    User_TriggerHandler handler = new User_TriggerHandler();
    
    if (Trigger.isBefore) {
        if(Trigger.isInsert){
            handler.isBeforeInsert(Trigger.new);
        }else if(Trigger.isUpdate){
            handler.isBeforeUpdate(Trigger.newMap, Trigger.oldMap);
        }      
    } else if (Trigger.isAfter) {
        if(Trigger.isInsert){
            handler.isAfterInsert(Trigger.newMap);
        }else if(Trigger.isUpdate){
            handler.isAfterUpdate(Trigger.newMap, Trigger.oldMap);
        }
    }
}