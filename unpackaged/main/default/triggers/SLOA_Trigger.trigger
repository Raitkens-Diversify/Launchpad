trigger SLOA_Trigger on Standing_Letter_of_Authorization__c (before insert, before update, before delete, after insert, after update, after delete, after undelete) {
	SLOA_TriggerHandler handler = new SLOA_TriggerHandler();
	if (Trigger.isBefore) {
		 if (Trigger.isInsert) {
			handler.isBeforeInsert(Trigger.new);
		}
		 else if (Trigger.isUpdate) {
			handler.isBeforeUpdate(Trigger.newMap,Trigger.oldMap);
		}
		 else if (Trigger.isDelete) {
			handler.isBeforeDelete(Trigger.oldMap);
		}
	}
	else if (Trigger.isAfter) {
		 if (Trigger.isInsert) {
			handler.isAfterInsert(Trigger.newMap);
		}
		 else if (Trigger.isUpdate) {
			handler.isAfterUpdate(Trigger.newMap,Trigger.oldMap);
		}
		 else if (Trigger.isDelete) {
			handler.isAfterDelete(Trigger.oldMap);
		}
		 else if (Trigger.isUndelete) {
			handler.isAfterUndelete(Trigger.newMap);
		}
	}
}