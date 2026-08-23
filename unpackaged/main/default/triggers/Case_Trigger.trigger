trigger Case_Trigger on Case (before insert,before update,before delete,after insert,after update,after delete,after undelete) {
    Case_TriggerHandler handler = new Case_TriggerHandler();
    CaseSlaTriggerHandler slaHandler = new CaseSlaTriggerHandler();
    if(Trigger.isBefore){
        if(Trigger.isInsert){
            handler.isBeforeInsert(Trigger.new);
        }else if(Trigger.isUpdate){
            handler.isBeforeUpdate(Trigger.newMap, Trigger.oldMap);
            slaHandler.isBeforeUpdate(Trigger.newMap, Trigger.oldMap);
        }else if(Trigger.isDelete){
            slaHandler.isBeforeDelete(Trigger.oldMap);
            handler.isBeforeDelete(Trigger.oldMap);
        }
    }else if(Trigger.isAfter){
        if(Trigger.isInsert){
            handler.isAfterInsert(Trigger.newMap);
            NotificationPublisher.publishFromRecords(Trigger.newMap.values(), NotificationConstants.OBJECT_TYPE_CASE);
        }else if(Trigger.isUpdate){
            handler.isAfterUpdate(Trigger.newMap, Trigger.oldMap);
            NotificationChangePublisher.publishUpdates(
                NotificationConstants.OBJECT_TYPE_CASE,
                Trigger.newMap,
                Trigger.oldMap
            );
        }else if(Trigger.isDelete){
            handler.isAfterDelete(Trigger.oldMap);
        }else if(Trigger.isUndelete){
            handler.isAfterUnDelete(Trigger.newMap);
        }
    }
}