trigger Required_Documents_Trigger on Required_Documents__c (after update) {
	Required_Documents_TriggerHandler handler = new Required_Documents_TriggerHandler();
	if (Trigger.isAfter) {
		 if (Trigger.isUpdate) {
			handler.isAfterUpdate(Trigger.newMap,Trigger.oldMap);
		}
	}
}