public class Account_TriggerHandler {
    public void isBeforeInsert(List<Account> newList){
        updateInvestmentObjectives(newList, null);
        //setOwnerOnAccount(newList, null);
    }
    
    public void isBeforeUpdate(Map<Id, Account> newMap, Map<Id, Account> oldMap){
        updateInvestmentObjectives(newMap.values(), oldMap);
        //setOwnerOnAccount(newMap.values(), oldMap);
        setAccreditationStatus(newMap, oldMap);
    }
    
    public void isBeforeDelete(Map<Id, Account> oldMap){
        
    }
    
    public void isAfterInsert(Map<Id, Account> newMap){
        createShareRecord(newMap, null);
        syncAccountRelationShares(newMap.keySet());

        //setAccountOnUser(newMap, null);
    }
    
    public void isAfterUpdate(Map<Id, Account> newMap, Map<Id, Account> oldMap){
        createShareRecord(newMap, oldMap);
        syncAccountRelationShares(newMap.keySet());
        //setAccountOnUser(newMap, oldMap);
        //setAccountValuesOnUser(newMap, oldMap);
    }
    
    public void isAfterDelete(Map<Id, Account> oldMap){
        
    }
    
    public void isAfterUnDelete(Map<Id, Account> newMap){
        
    }
    
    public void updateInvestmentObjectives(List<Account> newList, Map<Id,Account> oldMap){
        if(oldMap == null){
            for(Account a : newList){
                if(a.Investment_Objectives__c != null){
                    List<String> vals = a.Investment_Objectives__c.split(';');
                    a.DocuSignIOGrowth__c = null;
                    a.DocuSignIOIncome__c = null;
                    a.DocuSignIOBalanced__c = null;
                    a.DocuSignIOSpeculation__c = null;
                    a.DocuSignIOWealthAccumulation__c = null;
                    a.DocuSignIOPreserveWealth__c = null;
                    for(String v : vals){
                        if(v == 'Growth'){
                            a.DocuSignIOGrowth__c = vals.IndexOf(v) + 1;
                        } else if(v == 'Income'){
                            a.DocuSignIOIncome__c = vals.IndexOf(v) + 1;
                        } else if(v == 'Balanced'){
                            a.DocuSignIOBalanced__c = vals.IndexOf(v) + 1;
                        } else if(v == 'Speculation'){
                            a.DocuSignIOSpeculation__c = vals.IndexOf(v) + 1;
                        } else if(v == 'Wealth Accumulation'){
                            a.DocuSignIOWealthAccumulation__c = vals.IndexOf(v) + 1;
                        } else if(v == 'Preserve Wealth'){
                            a.DocuSignIOPreserveWealth__c = vals.IndexOf(v) + 1;
                        }
                    }
                }
            }
        } else {
            for(Account newAcc : newList){
                Account oldAcc = oldMap.get(newAcc.Id);
                if(newAcc.Investment_Objectives__c != null && newAcc.Investment_Objectives__c != oldAcc.Investment_Objectives__c){
                    List<String> vals = newAcc.Investment_Objectives__c.split(';');
                    newAcc.DocuSignIOGrowth__c = null;
                    newAcc.DocuSignIOIncome__c = null;
                    newAcc.DocuSignIOBalanced__c = null;
                    newAcc.DocuSignIOSpeculation__c = null;
                    newAcc.DocuSignIOWealthAccumulation__c = null;
                    newAcc.DocuSignIOPreserveWealth__c = null;
                    for(String v : vals){
                        if(v == 'Growth'){
                            newAcc.DocuSignIOGrowth__c = vals.IndexOf(v) + 1;
                        } else if(v == 'Income'){
                            newAcc.DocuSignIOIncome__c = vals.IndexOf(v) + 1;
                        } else if(v == 'Balanced'){
                            newAcc.DocuSignIOBalanced__c = vals.IndexOf(v) + 1;
                        } else if(v == 'Speculation'){
                            newAcc.DocuSignIOSpeculation__c = vals.IndexOf(v) + 1;
                        } else if(v == 'Wealth Accumulation'){
                            newAcc.DocuSignIOWealthAccumulation__c = vals.IndexOf(v) + 1;
                        } else if(v == 'Preserve Wealth'){
                            newAcc.DocuSignIOPreserveWealth__c = vals.IndexOf(v) + 1;
                        }
                    }
                }
            }
        }
    }
    
    private static void syncAccountRelationShares(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return;
        }

        FscRelAccountRelationShareService.syncSharesForRelatedAccounts(accountIds);
    }

    public static void createShareRecord(Map<Id, Account> newMap, Map<Id, Account> oldMap){
        Set<Id> fAccTeamIdSet = new Set<Id>();
        for(Account record : newMap.values()){
            if(oldMap==null){
                if(record.Financial_Advisor_Team__c != null)
                    fAccTeamIdSet.add(record.Financial_Advisor_Team__c);
            } else if(oldMap.get(record.Id).Financial_Advisor_Team__c!=record.Financial_Advisor_Team__c || oldMap.get(record.Id).OwnerId != record.OwnerId){
                if(record.Financial_Advisor_Team__c != null)
                    fAccTeamIdSet.add(record.Financial_Advisor_Team__c);
                if(oldMap.get(record.Id).Financial_Advisor_Team__c != null){
                    fAccTeamIdSet.add(oldMap.get(record.Id).Financial_Advisor_Team__c);
                }
            } 
        }
        if(!fAccTeamIdSet.isEmpty()){
            Map<Id, Financial_Advisor_Team__c> fATeamMap = new Map<Id, Financial_Advisor_Team__c>([Select Id, Public_Group_Id__c From Financial_Advisor_Team__c Where Id IN : fAccTeamIdSet]);
            if(fATeamMap.size() > 0){
                List<AccountShare> shareRecordList = new List<AccountShare>();
                //For revoke Share
                Set<Id> groupIdSet = new Set<Id>();
                Set<Id> parentIdSet = new Set<Id>();
                for(Account record : newMap.values()){
                    AccountShare shareRec = new AccountShare();
                    if(fATeamMap.get(record.Financial_Advisor_Team__c)!=null){
                        shareRec.AccountId = record.Id;
                        if(record.Financial_Advisor_Team__c != null){
                            shareRec.UserOrGroupId = fATeamMap.get(record.Financial_Advisor_Team__c).Public_Group_Id__c;
                        }
                        
                        shareRec.AccountAccessLevel = 'Edit';
                        shareRec.RowCause = Schema.AccountShare.RowCause.Manual;
                        shareRec.OpportunityAccessLevel = 'Edit';
                        if(oldMap == null){
                            if(record.Financial_Advisor_Team__c != null){
                                shareRecordList.add(shareRec);
                            }
                        } else if(oldMap != null && (oldMap.get(record.Id).Financial_Advisor_Team__c != record.Financial_Advisor_Team__c ||
                                        oldMap.get(record.Id).OwnerId != record.OwnerId)){
                            if(oldMap.get(record.Id).Financial_Advisor_Team__c != null 
                                && fATeamMap.get(oldMap.get(record.Id).Financial_Advisor_Team__c) != null){
                                    groupIdSet.add(fATeamMap.get(oldMap.get(record.Id).Financial_Advisor_Team__c).Public_Group_Id__c);
                                    parentIdSet.add(record.Id);
                                }            
                            if(record.Financial_Advisor_Team__c != null){
                                shareRecordList.add(shareRec);                                 
                            }
                        }
                    }
                }
                if(groupIdSet.size() > 0 && parentIdSet.size() > 0){
                    List<AccountShare> removeShareList = new List<AccountShare>();
                    for(AccountShare shareRec: [SELECT id, AccountId, UserOrGroupId FROM AccountShare WHERE AccountId IN: parentIdSet and UserOrGroupId IN: groupIdSet]){
                        if(groupIdSet.Contains(shareRec.UserOrGroupId) && parentIdSet.contains(shareRec.AccountId) ){
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
    
    private static void setOwnerOnAccount(List<Account> newList,  Map<Id, Account> oldMap){
        Set<Id> finAdvisorTeamIdSet = new Set<Id>();
        for(Account record : newList) {
            if(record.Financial_Advisor_Team__c != null && (oldMap == null || (oldMap != null && record.Financial_Advisor_Team__c != oldMap.get(record.Id).Financial_Advisor_Team__c))) {
                finAdvisorTeamIdSet.add(record.Financial_Advisor_Team__c);
            }
        }
        
        if(!finAdvisorTeamIdSet.isEmpty()){
            List<Financial_Advisor_Team__c> finAdTeamList = [SELECT Id, (SELECT ID, User__c FROM Financial_Advisor_Team_Members__r WHERE Active__c = true AND Role__c =: 'Financial Advisor') FROM Financial_Advisor_Team__c WHERE Id IN : finAdvisorTeamIdSet];
            if(!finAdTeamList.isEmpty()){
                Map<Id, Id> finAdTeamIdWithUserIdMap = new Map<Id, Id>();
                for(Financial_Advisor_Team__c finAdTeamRecord : finAdTeamList) {
                    List<Financial_Advisor_Team_Member__c> finAdTeamMemberList = finAdTeamRecord.Financial_Advisor_Team_Members__r;
                    if(!finAdTeamMemberList.isEmpty()) {
                        if(finAdTeamMemberList[0].User__c != null) {
                            finAdTeamIdWithUserIdMap.put(finAdTeamRecord.Id, finAdTeamMemberList[0].User__c);
                        }
                    }
                }
                for(Account record : newList) {
                    if(oldMap == null || (oldMap != null && record.Financial_Advisor_Team__c != oldMap.get(record.Id).Financial_Advisor_Team__c)) {
                        if(finAdTeamIdWithUserIdMap.get(record.Financial_Advisor_Team__c) != null) {
                            record.OwnerId = finAdTeamIdWithUserIdMap.get(record.Financial_Advisor_Team__c);
                        }
                    } 
                }
            }
        }
    }
    
    public static void setAccreditationStatus(Map<Id,Account> newMap, Map<Id,Account> oldMap){
        for(Account newAccount : newMap.values()){
            Account oldAccount = oldMap.get(newAccount.Id);
            if((newAccount.Net_Worth_Excluding_Primary_Residence__c  != null && 
               newAccount.Net_Worth_Excluding_Primary_Residence__c != oldAccount.Net_Worth_Excluding_Primary_Residence__c) || 
               (newAccount.Approximate_Annual_Income_All_Sources__c != null && newAccount.Approximate_Annual_Income_All_Sources__c != oldAccount.Approximate_Annual_Income_All_Sources__c)){
                if(newAccount.Net_Worth_Excluding_Primary_Residence__c > 5000000.00){
                    newAccount.Accreditation__c = 'Qualified Purchaser';
                } else if(newAccount.Net_Worth_Excluding_Primary_Residence__c > 1000000.00){
                    newAccount.Accreditation__c = 'Accredited';
                } else if(newAccount.Net_Worth_Excluding_Primary_Residence__c > 250000.00 || newAccount.Approximate_Annual_Income_All_Sources__c > 70000.00 && newAccount.Net_Worth_Excluding_Primary_Residence__c > 70000.00){
                    newAccount.Accreditation__c = 'Suitable';
                }
            }
        }
    }
    
    /*public void setAccountOnUser(Map<Id,Account> newMap, Map<Id,Account> oldMap){
        Map<Id,Id> accountUserMap = new Map<Id,Id>();
        List<User> usersToUpdate = new List<User>();
        if(oldMap == null){
            for(Account a : newMap.values()){
                if(a.User__c != null){
                    accountUserMap.put(a.Id,a.User__c);
                }
            }
        } else {
            for(Account newAccount : newMap.values()){
                Account oldAccount = oldMap.get(newAccount.Id);
                if(newAccount.User__c != null && newAccount.User__c != oldAccount.User__c){
                    accountUserMap.put(newAccount.Id,newAccount.User__c);
                }
            }
        }
        if(!accountUserMap.isEmpty()){
            Map<Id,User> userMap = new Map<Id,User>([SELECT Id, Diversify_Related_Person_ID__c FROM User WHERE Id in: accountUserMap.values()]);
            for(Id a : accountUserMap.keyset()){
                User u = userMap.get(accountUserMap.get(a));
                u.Diversify_Related_Person_ID__c = a;
                usersToUpdate.add(u);
            }
        }
        if(!usersToUpdate.isEmpty()){
            update usersToUpdate;
        }
    }
    
    public void setAccountValuesOnUser(Map<Id,Account> newMap, Map<Id,Account> oldMap){
        Map<Id,Id> accountUserMap = new Map<Id,Id>();
        List<User> usersToUpdate = new List<User>();
        if(oldMap == null){
            for(Account a : newMap.values()){
                if(a.User__c != null){
                    if(a.CRD_Number__c != null){
                        accountUserMap.put(a.Id, a.User__c);
                    }
                }
            }
        } else {
            for(Account newAccount : newMap.values()){
                Account oldAccount = oldMap.get(newAccount.Id);
                if(newAccount.User__c != null){
                    if(newAccount.CRD_Number__c != null && newAccount.CRD_Number__c != oldAccount.CRD_Number__c){
                        accountUserMap.put(newAccount.Id, newAccount.User__c);
                    }
                }
            }
        }
        if(!accountUserMap.isEmpty()){
            Map<Id,User> userMap = new Map<Id,User>([SELECT Id, CRD__c FROM User WHERE Id in: accountUserMap.values()]);
            for(Id a : accountUserMap.keyset()){
                User u = userMap.get(accountUserMap.get(a));
                u.CRD__c = newMap.get(a).CRD_Number__c;
                usersToUpdate.add(u);
            }
            
    	}
        if(!usersToUpdate.isEmpty()){
                update usersToUpdate;
            }
    }*/
}