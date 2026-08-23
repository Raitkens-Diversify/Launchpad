public class FARP_TriggerHandler {
	public void isBeforeInsert(List<Financial_Account_Related_Product__c> newList){

	}

	public void isBeforeUpdate(Map<Id,Financial_Account_Related_Product__c> newMap, Map<Id,Financial_Account_Related_Product__c> oldMap){

	}

	public void isBeforeDelete(Map<Id,Financial_Account_Related_Product__c> oldMap){

	}

	public void isAfterInsert(Map<Id,Financial_Account_Related_Product__c> newMap){
		findFinAcct(newMap);
	}

	public void isAfterUpdate(Map<Id,Financial_Account_Related_Product__c> newMap, Map<Id,Financial_Account_Related_Product__c> oldMap){
		findFinAcct(newMap);
	}

	public void isAfterDelete(Map<Id,Financial_Account_Related_Product__c> oldMap){

	}

	public void isAfterUndelete(Map<Id,Financial_Account_Related_Product__c> newMap){

	}
    
    private void findFinAcct(Map<Id,Financial_Account_Related_Product__c> newMap){
        List<Find_Related_Record__e> wizEvents = new List<Find_Related_Record__e>();
        List<Financial_Account_Related_Product__c> farpsToUpdate = new List<Financial_Account_Related_Product__c>();
        Set<Id> wizIds = new Set<Id>();
        Map<Id,Id> wizFinToFin = new Map<Id,Id>();
        
        for(Financial_Account_Related_Product__c f : newMap.values()){
            if(f.Wizard_Financial_Account__c != null){
                wizIds.add(f.Wizard_Financial_Account__c);
                farpsToUpdate.add(f);
            }
        }
        if(!wizIds.isEmpty()){
            List<FinServ__FinancialAccount__c> finAccts = [SELECT Id, Wizard_Financial_Account__c FROM FinServ__FinancialAccount__c WHERE Wizard_Financial_Account__c in: wizIds];
            for(FinServ__FinancialAccount__c f : finAccts){
                wizFinToFin.put(f.Wizard_Financial_Account__c, f.Id);
            }
            for(Financial_Account_Related_Product__c f : farpsToUpdate){
                wizEvents.add(new Find_Related_Record__e(Wiz_Fin_Acct_Id__c = f.Wizard_Financial_Account__c,
                                                        Fin_Acct_Id__c = wizFinToFin.get(f.Wizard_Financial_Account__c),
                                                        Object__c = 'Financial_Account_Related_Product__c',
                                                        Object_Id__c = f.Id));
            }
            System.debug('wizEvent:'+ wizEvents);
        }
        if(!wizEvents.isEmpty()){
            List<Database.SaveResult> results = EventBus.publish(wizEvents);
            for (Database.SaveResult sr : results) {
                if (sr.isSuccess()) {
                    System.debug('Successfully published event.');
                    wizEvents.clear();
                } else {
                    for(Database.Error err : sr.getErrors()) {
                        System.debug('Error returned: ' + err.getStatusCode()+' - '+err.getMessage());
                        wizEvents.clear();
                    }
                }       
            }
        }
        
    }
}