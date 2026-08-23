trigger efs_Advertising_ItemTrigger on Advertising_Item__c (after update, after insert) 
{
    if(trigger.isAfter && trigger.isInsert)
        efs__.EgnyteSyncQueueTrigger.onAfterInsert();
    else if(trigger.isAfter && trigger.isUpdate)
        efs__.EgnyteSyncQueueTrigger.onAfterUpdate();
}