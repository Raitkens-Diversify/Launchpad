public class Allocation_TriggerHandler {
	public void isBeforeInsert(List<Allocation__c> newList){

	}

	public void isBeforeUpdate(Map<Id,Allocation__c> newMap, Map<Id,Allocation__c> oldMap){

	}

	public void isBeforeDelete(Map<Id,Allocation__c> oldMap){

	}

	public void isAfterInsert(Map<Id,Allocation__c> newMap){
        createShareRecord(newMap, null);
		setAllocationStrategies(newMap);
        markOldAllocationInactive(newMap);
	}

	public void isAfterUpdate(Map<Id,Allocation__c> newMap, Map<Id,Allocation__c> oldMap){
		createShareRecord(newMap, oldMap);
	}

	public void isAfterDelete(Map<Id,Allocation__c> oldMap){

	}

	public void isAfterUndelete(Map<Id,Allocation__c> newMap){

	}
    
    public void createShareRecord(Map<Id, Allocation__c> newMap, Map<Id, Allocation__c> oldMap){
        Set<Id> fAccTeamIdSet = new Set<Id>();
        
        for(Allocation__c a : newMap.values()){
            if(oldMap == null){
                if(a.Financial_Advisor_Team__c != null)
                    fAccTeamIdSet.add(a.Financial_Advisor_Team__c);
            } else if(oldMap.get(a.Id).Financial_Advisor_Team__c != a.Financial_Advisor_Team__c || oldMap.get(a.Id).OwnerId != a.OwnerId){
                if(a.Financial_Advisor_Team__c != null)
                    fAccTeamIdSet.add(a.Financial_Advisor_Team__c);
                if(oldMap.get(a.Id).Financial_Advisor_Team__c != null){
                    fAccTeamIdSet.add(oldMap.get(a.Id).Financial_Advisor_Team__c);
                }
            } 
        }
        
        if(!fAccTeamIdSet.isEmpty()){
            Map<Id, Financial_Advisor_Team__c> fATeamMap = new Map<Id, Financial_Advisor_Team__c>([SELECT Id, Public_Group_Id__c FROM Financial_Advisor_Team__c WHERE Id IN : fAccTeamIdSet]);
            if(!fATeamMap.isEmpty()){
                List<Allocation__Share> shareRecordList = new List<Allocation__Share>();
                //For revoke Share
                Set<Id> groupIdSet = new Set<Id>();
                Set<Id> parentIdSet = new Set<Id>();
                for(Allocation__c a : newMap.values()){
                    Allocation__Share shareRec = new Allocation__Share();
                    if(fATeamMap.get(a.Financial_Advisor_Team__c)!=null){
                        shareRec.ParentId = a.Id;
                        if(a.Financial_Advisor_Team__c != null){
                            shareRec.UserOrGroupId = fATeamMap.get(a.Financial_Advisor_Team__c).Public_Group_Id__c;
                        }
                        
                        shareRec.AccessLevel = 'Edit';
                        shareRec.RowCause = Schema.Allocation__Share.RowCause.Manual;
                        if(oldMap == null){
                            if(a.Financial_Advisor_Team__c != null){
                                shareRecordList.add(shareRec);
                            }
                        } else if(oldMap != null && (oldMap.get(a.Id).Financial_Advisor_Team__c != a.Financial_Advisor_Team__c ||
                                                     oldMap.get(a.Id).OwnerId != a.OwnerId)){
                                                         if(oldMap.get(a.Id).Financial_Advisor_Team__c != null 
                                                            && fATeamMap.get(oldMap.get(a.Id).Financial_Advisor_Team__c) != null){
                                                                groupIdSet.add(fATeamMap.get(oldMap.get(a.Id).Financial_Advisor_Team__c).Public_Group_Id__c);
                                                                parentIdSet.add(a.Id);
                                                            }            
                                                         if(a.Financial_Advisor_Team__c != null){
                                                             shareRecordList.add(shareRec);                                 
                                                         }
                                                     }
                    }
                }
                if(groupIdSet.size() > 0 && parentIdSet.size() > 0){
                    List<Allocation__Share> removeShareList = new List<Allocation__Share>();
                    for(Allocation__Share shareRec: [SELECT Id, ParentId, UserOrGroupId FROM Allocation__Share WHERE ParentId IN: parentIdSet and UserOrGroupId IN: groupIdSet]){
                        if(groupIdSet.Contains(shareRec.UserOrGroupId) && parentIdSet.contains(shareRec.ParentId) ){
                            removeShareList.add(shareRec);
                        }
                    }
                    if(removeShareList.size() > 0){
                        Database.delete(removeShareList,false);
                    } 
                }
                if(shareRecordList.size() > 0){
                    Database.insert(shareRecordList,false);
                }
            }
        }
    }
    

    /**
     * Copy the originating order ticket's orders onto the new allocation as strategies.
     * An allocation with no originating ticket, or whose ticket has no orders, simply gets no
     * strategies (the earlier code dereferenced a null list and failed the whole insert).
     */
    public void setAllocationStrategies(Map<Id,Allocation__c> newMap){
        List<Allocation_Strategy__c> stratsToInsert = new List<Allocation_Strategy__c>();
        Set<Id> orderTicketIds = new Set<Id>();
        Map<Id,List<Order__c>> orderTicketToOrders = new Map<Id,List<Order__c>>();
        for(Allocation__c a : newMap.values()){
            if(a.Request_Allocation_Originated_From__c != null){
                orderTicketIds.add(a.Request_Allocation_Originated_From__c);
            }
        }
        if(orderTicketIds.isEmpty()){
            return;
        }
        // Funding_Basis__c stays on its own line here and below: manifest/order-ticket-allocation
        // derives the prod build (prod has no Funding_Basis__c yet) by dropping those lines.
        List<Order__c> orders = [SELECT Id, Excluded_From_Allocation__c,
                                        Funding_Basis__c,
                                        Initial_Funding_Amount__c, Initial_Funding_Percentage__c, Order_Ticket__c, Order_Type__c,
                                        Principal_Amount__c, Share_Price__c, Share_Quantity__c, Strategy_Code__c, Strategy__c,
                                        Total_Initial_Funding_Amount__c FROM Order__c WHERE Order_Ticket__c IN :orderTicketIds];
        for(Order__c o : orders){
            if(!orderTicketToOrders.containsKey(o.Order_Ticket__c)){
                orderTicketToOrders.put(o.Order_Ticket__c, new List<Order__c>());
            }
            orderTicketToOrders.get(o.Order_Ticket__c).add(o);
        }

        for(Allocation__c a : newMap.values()){
            List<Order__c> orderList = orderTicketToOrders.get(a.Request_Allocation_Originated_From__c);
            if(orderList == null){
                continue;
            }
            for(Order__c o : orderList){
                Allocation_Strategy__c astrat = new Allocation_Strategy__c();
                astrat.Allocation__c = a.Id;
                // Carried forward with the basis, and for the same reason: an exception sleeve's
                // dollars were taken off the account value before the other sleeves' target weights
                // were calculated, and the completed allocation has to keep saying so without
                // re-resolving the strategy's current Sleeve Basis Rule.
                astrat.Excluded_From_Allocation__c = o.Excluded_From_Allocation__c;
                astrat.Funding_Basis__c = o.Funding_Basis__c;
                astrat.Initial_Funding_Amount__c = o.Initial_Funding_Amount__c;
                astrat.Initial_Funding_Percentage__c = o.Initial_Funding_Percentage__c;
                astrat.Order_Type__c = o.Order_Type__c;
                astrat.Principal_Amount__c = o.Principal_Amount__c;
                astrat.Share_Price__c = o.Share_Price__c;
                astrat.Share_Quantity__c = o.Share_Quantity__c;
                astrat.Strategy__c = o.Strategy__c;
                astrat.Strategy_Code__c = o.Strategy_Code__c;
                astrat.Total_Initial_Funding_Amount__c = o.Total_Initial_Funding_Amount__c;
                stratsToInsert.add(astrat);
            }
        }

        if(!stratsToInsert.isEmpty()){
            insert stratsToInsert;
        }
    }

    /**
     * A new allocation replaces every other current allocation on the same wizard Financial
     * Account: those are flagged inactive, stamped with the ticket that superseded them and the
     * new allocation's implemented date. Keyed on Wizard_Financial_Account__c (the wizard writes
     * that on every ticket); an allocation without one has nothing to supersede.
     */
    public void markOldAllocationInactive(Map<Id,Allocation__c> newMap){
        Set<Id> finAcctIds = new Set<Id>();
        for(Allocation__c a : newMap.values()){
            if(a.Wizard_Financial_Account__c != null){
                finAcctIds.add(a.Wizard_Financial_Account__c);
            }
        }
        if(finAcctIds.isEmpty()){
            return;
        }

        Map<Id,List<Allocation__c>> finIdToOldAllocations = new Map<Id,List<Allocation__c>>();
        for(Allocation__c old : [SELECT Id, Request_Allocation_Inactivated_From__c, Current_Allocation__c, Date_Inactivated__c,
                                        Wizard_Financial_Account__c FROM Allocation__c
                                 WHERE Current_Allocation__c = TRUE AND Wizard_Financial_Account__c IN :finAcctIds
                                 AND Id NOT IN :newMap.keySet()]){
            if(!finIdToOldAllocations.containsKey(old.Wizard_Financial_Account__c)){
                finIdToOldAllocations.put(old.Wizard_Financial_Account__c, new List<Allocation__c>());
            }
            finIdToOldAllocations.get(old.Wizard_Financial_Account__c).add(old);
        }

        // Keyed by Id so two new allocations for the same account in one batch retire each
        // predecessor once instead of listing it twice in the update.
        Map<Id,Allocation__c> allocationsToUpdate = new Map<Id,Allocation__c>();
        for(Allocation__c a : newMap.values()){
            List<Allocation__c> oldAllocations = finIdToOldAllocations.get(a.Wizard_Financial_Account__c);
            if(oldAllocations == null){
                continue;
            }
            for(Allocation__c oldAllocation : oldAllocations){
                oldAllocation.Request_Allocation_Inactivated_From__c = a.Request_Allocation_Originated_From__c;
                oldAllocation.Current_Allocation__c = false;
                oldAllocation.Date_Inactivated__c = a.Date_Implemented__c;
                allocationsToUpdate.put(oldAllocation.Id, oldAllocation);
            }
        }

        if(!allocationsToUpdate.isEmpty()){
            update allocationsToUpdate.values();
        }
    }
}