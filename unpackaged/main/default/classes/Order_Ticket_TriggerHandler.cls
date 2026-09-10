public class Order_Ticket_TriggerHandler {
	public void isBeforeInsert(List<Order_Ticket__c> newList){

	}

	public void isBeforeUpdate(Map<Id,Order_Ticket__c> newMap, Map<Id,Order_Ticket__c> oldMap){
		setCurrentAllocation(newMap, oldMap);
	}

	public void isBeforeDelete(Map<Id,Order_Ticket__c> oldMap){

	}

	public void isAfterInsert(Map<Id,Order_Ticket__c> newMap){
	}

	public void isAfterUpdate(Map<Id,Order_Ticket__c> newMap, Map<Id,Order_Ticket__c> oldMap){

	}

	public void isAfterDelete(Map<Id,Order_Ticket__c> oldMap){

	}

	public void isAfterUndelete(Map<Id,Order_Ticket__c> newMap){

	}
    
    
    
    public void setCurrentAllocation(Map<Id,Order_Ticket__c> newMap, Map<Id,Order_Ticket__c> oldMap){
        List<Allocation__c> allocationsToInsert = new List<Allocation__c>();
        Set<Id> finAcctIds = new Set<Id>();
        for(Order_Ticket__c newOT : newMap.values()){
            Order_Ticket__c oldOT = oldMap.get(newOT.Id);
            System.debug('newOT.of_Orders__c: ' + newOT.of_Orders__c);
            if(newOT.Status__c == 'Completed' && oldOT.Status__c != 'Completed' && newOT.of_Orders__c > 0){
                finAcctIds.add(newOT.Wizard_Financial_Account__c);
                System.debug('finAcctId added');
        	}
        }

        if(!finAcctIds.isEmpty()){
            Map<Id,Financial_Account__c> finAccts = new Map<Id,Financial_Account__c>([SELECT Id, Financial_Advisor_Team__c FROM Financial_Account__c WHERE Id in: finAcctIds]);
            for(Order_Ticket__c newOT : newMap.values()){
                Order_Ticket__c oldOT = oldMap.get(newOT.Id);
                if(newOT.Status__c == 'Completed' && oldOT.Status__c != 'Completed'){
                    Allocation__c a = new Allocation__c();
                    a.Current_Allocation__c = true;
                    a.Date_Implemented__c = Date.Today();
                    a.Request_Allocation_Originated_From__c = newOT.Id;
                    //a.Financial_Account__c = newOT.Financial_Account__c;
                    a.Wizard_Financial_Account__c = newOT.Wizard_Financial_Account__c;
                    a.Advisor_Notes__c = newOT.Advisor_Notes__c;
                    a.Financial_Advisor_Team__c = finAccts.get(newOT.Wizard_Financial_Account__c).Financial_Advisor_Team__c;
                    allocationsToInsert.add(a);
                }
            }
        }
        
        
        if(!allocationsToInsert.isEmpty()){
            insert allocationsToInsert;
        }
    }
}