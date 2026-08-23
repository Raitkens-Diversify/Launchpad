/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-19
 */
trigger AccountAccountRelationshipTrigger on Account_Account_Relationship__c (
  after insert,
  after update
) {
  AccountAccountRelationshipTriggerHandler handler = new AccountAccountRelationshipTriggerHandler();

  if (Trigger.isAfter) {
    if (Trigger.isInsert) {
      handler.isAfterInsert(Trigger.new);
    } else if (Trigger.isUpdate) {
      handler.isAfterUpdate(Trigger.new, Trigger.oldMap);
    }
  }
}