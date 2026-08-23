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
    
    
    public void setAllocationStrategies(Map<Id,Allocation__c> newMap){
        List<Allocation_Strategy__c> stratsToInsert = new List<Allocation_Strategy__c>();
        Set<Id> orderTicketIds = new Set<Id>();
        Map<Id,List<Order__c>> orderTicketToOrders = new Map<Id,List<Order__c>>();
        for(Allocation__c a : newMap.values()){
            orderTicketIds.add(a.Request_Allocation_Originated_From__c);
        }
        Map<Id,Order__c> ordersMap = new Map<Id,Order__c>([SELECT Id, Funding_Basis__c, Initial_Funding_Amount__c, Initial_Funding_Percentage__c, Order_Ticket__c, Order_Type__c,
                                                           Principal_Amount__c, Share_Price__c, Share_Quantity__c, Strategy_Code__c, Strategy__c,
                                                           Total_Initial_Funding_Amount__c FROM Order__c WHERE Order_Ticket__c in: orderTicketIds]);
        for(Order__c o : ordersMap.values()){
            if(orderTicketToOrders.get(o.Order_Ticket__c) == null){
                List<Order__c> tempList = new List<Order__c>();
                tempList.add(o);
                orderTicketToOrders.put(o.Order_Ticket__c, tempList);
            } else {
                List<Order__c> tempList = orderTicketToOrders.get(o.Order_Ticket__c);
                tempList.add(o);
                orderTicketToOrders.put(o.Order_Ticket__c, tempList);
            }
        }
        
        for(Allocation__c a : newMap.values()){
            List<Order__c> orderList = orderTicketToOrders.get(a.Request_Allocation_Originated_From__c);
            for(Order__c o : orderList){
                Allocation_Strategy__c astrat = new Allocation_Strategy__c();
                astrat.Allocation__c = a.Id;
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
    
    public void markOldAllocationInactive(Map<Id,Allocation__c> newMap){
        Set<Id> finAcctIds = new Set<Id>();
        Map<Id,Allocation__c> finIdToAllocation = new Map<Id,Allocation__c>();
        List<Allocation__c> allocationsToUpdate = new List<Allocation__c>();
        for(Allocation__c a : newMap.values()){
            finAcctIds.add(a.Financial_Account__c);
        }
        
        List<Allocation__c> oldAllocs = [SELECT Id, Request_Allocation_Inactivated_From__c, Current_Allocation__c, Date_Inactivated__c, 
                                                   Financial_Account__c FROM Allocation__c WHERE Current_Allocation__c = TRUE AND Financial_Account__c in: finAcctIds
                                                  AND Id NOT IN: newMap.keyset()];
        
        for(Allocation__c a : oldAllocs){
            finIdToAllocation.put(a.Financial_Account__c, a);
        }
        
        for(Allocation__c a : newMap.values()){
            if(finIdToAllocation.get(a.Financial_Account__c) != null){
                Allocation__c oldAllocation = finIdToAllocation.get(a.Financial_Account__c);
                oldAllocation.Request_Allocation_Inactivated_From__c = a.Request_Allocation_Originated_From__c;
                oldAllocation.Current_Allocation__c = false;
                oldAllocation.Date_Inactivated__c = a.Date_Implemented__c;
                allocationsToUpdate.add(oldAllocation);
            }
        }
        
        if(!allocationsToUpdate.isEmpty()){
            update allocationsToUpdate;
        }
    }
}