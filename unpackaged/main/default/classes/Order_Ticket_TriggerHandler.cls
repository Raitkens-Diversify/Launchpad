public class Order_Ticket_TriggerHandler {
	public void isBeforeInsert(List<Order_Ticket__c> newList){

	}

	public void isBeforeUpdate(Map<Id,Order_Ticket__c> newMap, Map<Id,Order_Ticket__c> oldMap){
		setCurrentAllocation(newMap, oldMap);
	}

	public void isBeforeDelete(Map<Id,Order_Ticket__c> oldMap){

	}

	public void isAfterInsert(Map<Id,Order_Ticket__c> newMap){
		findFinAcct(newMap);
	}

	public void isAfterUpdate(Map<Id,Order_Ticket__c> newMap, Map<Id,Order_Ticket__c> oldMap){

	}

	public void isAfterDelete(Map<Id,Order_Ticket__c> oldMap){

	}

	public void isAfterUndelete(Map<Id,Order_Ticket__c> newMap){

	}
    
    private void findFinAcct(Map<Id,Order_Ticket__c> newMap){
        System.debug('Order_Ticket_TriggerHandler.findFinAcct');
        List<Find_Related_Record__e> wizEvents = new List<Find_Related_Record__e>();
        List<Order_Ticket__c> orderTicketsToUpdate = new List<Order_Ticket__c>();
        Set<Id> wizIds = new Set<Id>();
        Map<Id,Id> wizFinToFin = new Map<Id,Id>();
        
        for(Order_Ticket__c o : newMap.values()){
            if(o.Wizard_Financial_Account__c != null){
                wizIds.add(o.Wizard_Financial_Account__c);
                orderTicketsToUpdate.add(o);
            }
        }
        if(!wizIds.isEmpty()){
            List<FinServ__FinancialAccount__c> finAccts = [SELECT Id, Wizard_Financial_Account__c FROM FinServ__FinancialAccount__c WHERE Wizard_Financial_Account__c in: wizIds];
            for(FinServ__FinancialAccount__c f : finAccts){
                wizFinToFin.put(f.Wizard_Financial_Account__c, f.Id);
            }
            for(Order_Ticket__c o : orderTicketsToUpdate){
                wizEvents.add(new Find_Related_Record__e(Wiz_Fin_Acct_Id__c = o.Wizard_Financial_Account__c,
                                                        Fin_Acct_Id__c = wizFinToFin.get(o.Wizard_Financial_Account__c),
                                                        Object__c = 'Order_Ticket__c',
                                                        Object_Id__c = o.Id));
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
    
    public void setCurrentAllocation(Map<Id,Order_Ticket__c> newMap, Map<Id,Order_Ticket__c> oldMap){
        List<Allocation__c> allocationsToInsert = new List<Allocation__c>();
        Set<Id> finAcctIds = new Set<Id>();
        for(Order_Ticket__c newOT : newMap.values()){
            Order_Ticket__c oldOT = oldMap.get(newOT.Id);
            System.debug('newOT.of_Orders__c: ' + newOT.of_Orders__c);
            if(newOT.Status__c == 'Completed' && oldOT.Status__c != 'Completed' && newOT.of_Orders__c > 0){
                finAcctIds.add(newOT.Financial_Account__c);
                System.debug('finAcctId added');
        	}
        }
        
        if(!finAcctIds.isEmpty()){
            Map<Id,FinServ__FinancialAccount__c> finAccts = new Map<Id,FinServ__FinancialAccount__c>([SELECT Id, Financial_Advisor_Team__c FROM FinServ__FinancialAccount__c WHERE Id in: finAcctIds]);
            for(Order_Ticket__c newOT : newMap.values()){
                Order_Ticket__c oldOT = oldMap.get(newOT.Id);
                if(newOT.Status__c == 'Completed' && oldOT.Status__c != 'Completed'){
                    Allocation__c a = new Allocation__c();
                    a.Current_Allocation__c = true;
                    a.Date_Implemented__c = Date.Today();
                    a.Request_Allocation_Originated_From__c = newOT.Id;
                    a.Financial_Account__c = newOT.Financial_Account__c;
                    a.Wizard_Financial_Account__c = newOT.Wizard_Financial_Account__c;
                    a.Advisor_Notes__c = newOT.Advisor_Notes__c;
                    a.Financial_Advisor_Team__c = finAccts.get(newOT.Financial_Account__c).Financial_Advisor_Team__c;
                    allocationsToInsert.add(a);
                }
            }
        }
        
        
        if(!allocationsToInsert.isEmpty()){
            insert allocationsToInsert;
        }
    }
}