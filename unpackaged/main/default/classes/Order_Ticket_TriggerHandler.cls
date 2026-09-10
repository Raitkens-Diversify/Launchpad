public class Order_Ticket_TriggerHandler {
	public void isBeforeInsert(List<Order_Ticket__c> newList){

	}

	public void isBeforeUpdate(Map<Id,Order_Ticket__c> newMap, Map<Id,Order_Ticket__c> oldMap){
		setCurrentAllocation(newMap, oldMap);
	}

	public void isBeforeDelete(Map<Id,Order_Ticket__c> oldMap){

	}

	public void isAfterInsert(Map<Id,Order_Ticket__c> newMap){
		// findFinAcct (the Find_Related_Record__e publish that resolved the FinServ
		// Financial Account) was retired 2026-09-10: the wizard writes
		// Wizard_Financial_Account__c directly and every allocation keys off it.
	}

	public void isAfterUpdate(Map<Id,Order_Ticket__c> newMap, Map<Id,Order_Ticket__c> oldMap){

	}

	public void isAfterDelete(Map<Id,Order_Ticket__c> oldMap){

	}

	public void isAfterUndelete(Map<Id,Order_Ticket__c> newMap){

	}

    /**
     * When an order ticket first reaches Completed with at least one order, snapshot it as the
     * account's new current allocation. The allocation is keyed on the wizard Financial_Account__c
     * (Allocation_TriggerHandler then copies the orders into strategies, shares the row with the
     * team's public group, and retires the previous current allocation for that account).
     *
     * A ticket with no Wizard_Financial_Account__c is skipped rather than allowed to throw: there is
     * no account to hang the allocation on, and the earlier code's null dereference blocked Ops from
     * completing the ticket at all.
     */
    public void setCurrentAllocation(Map<Id,Order_Ticket__c> newMap, Map<Id,Order_Ticket__c> oldMap){
        List<Order_Ticket__c> completedTickets = new List<Order_Ticket__c>();
        Set<Id> wizFinAcctIds = new Set<Id>();
        for(Order_Ticket__c newOT : newMap.values()){
            Order_Ticket__c oldOT = oldMap.get(newOT.Id);
            Boolean justCompleted = newOT.Status__c == 'Completed' && oldOT.Status__c != 'Completed';
            Boolean hasOrders = newOT.of_Orders__c != null && newOT.of_Orders__c > 0;
            if(justCompleted && hasOrders && newOT.Wizard_Financial_Account__c != null){
                completedTickets.add(newOT);
                wizFinAcctIds.add(newOT.Wizard_Financial_Account__c);
            }
        }
        if(completedTickets.isEmpty()){
            return;
        }

        Map<Id,Financial_Account__c> finAccts = new Map<Id,Financial_Account__c>(
            [SELECT Id, Financial_Advisor_Team__c FROM Financial_Account__c WHERE Id IN :wizFinAcctIds]
        );

        List<Allocation__c> allocationsToInsert = new List<Allocation__c>();
        for(Order_Ticket__c newOT : completedTickets){
            Financial_Account__c wizFinAcct = finAccts.get(newOT.Wizard_Financial_Account__c);
            Allocation__c a = new Allocation__c();
            a.Current_Allocation__c = true;
            a.Date_Implemented__c = Date.today();
            a.Request_Allocation_Originated_From__c = newOT.Id;
            a.Wizard_Financial_Account__c = newOT.Wizard_Financial_Account__c;
            a.Advisor_Notes__c = newOT.Advisor_Notes__c;
            a.Financial_Advisor_Team__c = wizFinAcct == null ? null : wizFinAcct.Financial_Advisor_Team__c;
            allocationsToInsert.add(a);
        }

        if(!allocationsToInsert.isEmpty()){
            insert allocationsToInsert;
        }
    }
}