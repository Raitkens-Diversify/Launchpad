public without sharing class Financial_Account_TriggerHandler{
    
    /*CODE REVIEWED BY RACHEL ON 03/07/2025*/
    /*TODO: Decide between Public and Private Methods in Triggers*/
    
    public void isBeforeInsert(List<Financial_Account__c> newList){
        setOwnerOnWizardFinancialAccount(newList, null);
        setDMSOnHousehold(newList, null);
        setHousehold(newList);
        setFinancialAccountName(newList);
        setMaestroAccountType(newList, null);
        setCustodianOnDPI(newList);
        //setWizFinAccountName(newList);
    }
    
    public void isBeforeUpdate(Map<Id, Financial_Account__c> newMap, Map<Id, Financial_Account__c> oldMap){
        setOwnerOnWizardFinancialAccount(newMap.values(), oldMap);
        setDMSOnHousehold(newMap.values(), oldMap);
        setReportAcctNumber_Before(newMap.values(), oldMap);
        setMaestroAccountType(newMap.values(), oldMap);
        setFinancialAccountNameOnUpdate(newMap, oldMap);
        //setWizFinAccountName(newMap.values());
        
    }
    
    public void isBeforeDelete(Map<Id, Financial_Account__c>  oldMap){
        
    }
    
    public void isAfterInsert(Map<Id, Financial_Account__c> newMap){
        createShareRecord(newMap, null);
        //setFinancialAccountOnRider(newMap);
        setReportAcctNumber_AfterInsert(newMap.values());
    }
    
    public void isAfterUpdate(Map<Id, Financial_Account__c> newMap, Map<Id, Financial_Account__c> oldMap){
        createShareRecord(newMap, oldMap);
        updateRelatedCase(newMap, oldMap);
    }
    
    public void isAfterDelete(Map<Id, Financial_Account__c> oldMap){
        
    }
    
    public void isAfterUnDelete(Map<Id, Financial_Account__c> newMap){
        
    }
    
    /*Method to set the record owner to related FAT's member's User if member has a role of Financial Advisor.*/
    public void setOwnerOnWizardFinancialAccount(List<Financial_Account__c> newList, Map<Id, Financial_Account__c> oldMap){
        Set<Id> finAdvisorTeamIdSet = new Set<Id>();
        for(Financial_Account__c record : newList) {
            if(record.Financial_Advisor_Team__c != null && (oldMap == null || (record.Financial_Advisor_Team__c != oldMap.get(record.Id)?.Financial_Advisor_Team__c))){
                finAdvisorTeamIdSet.add(record.Financial_Advisor_Team__c);
            }
        }
        
        if(!finAdvisorTeamIdSet.isEmpty()){
            Map<Id, Id> finAdTeamIdWithUserIdMap = new Map<Id, Id>();
            List<Financial_Advisor_Team__c> finAdTeamList = [SELECT Id, (SELECT ID, User__c FROM Financial_Advisor_Team_Members__r WHERE Active__c = true AND Role__c =: 'Financial Advisor' LIMIT 1) FROM Financial_Advisor_Team__c WHERE Id IN : finAdvisorTeamIdSet];
            for(Financial_Advisor_Team__c finAdTeamRecord : finAdTeamList){
                if(!finAdTeamRecord.Financial_Advisor_Team_Members__r.isEmpty() && finAdTeamRecord.Financial_Advisor_Team_Members__r[0].User__c != null){
                    finAdTeamIdWithUserIdMap.put(finAdTeamRecord.Id, finAdTeamRecord.Financial_Advisor_Team_Members__r[0].User__c);
                }
            }
            
            for(Financial_Account__c record : newList){
                if(record.Financial_Advisor_Team__c != null && (oldMap == null || record.Financial_Advisor_Team__c != oldMap.get(record.Id)?.Financial_Advisor_Team__c)){
                    if(finAdTeamIdWithUserIdMap.containsKey(record.Financial_Advisor_Team__c)){
                        record.OwnerId = finAdTeamIdWithUserIdMap.get(record.Financial_Advisor_Team__c);
                    }
                } 
            }
        }
    }
    
    //Do we still need this method?  The Financial Account Name is set in the Wizard.
    //No, Clickup 86dw6gjzh remove this method.
    /*public void setWizFinAccountName(List<Wizard_Financial_Account__c> newList){
for(Wizard_Financial_Account__c wfa : newList){
if(!wfa.IsCreatedFromFinancialAccount__c && wfa.Registration_Type__c != 'Revocable Trust'){
wfa.Name = wfa.Primary_Owner_Name__c;
if(!String.isEmpty(wfa.Registration_Type__c)){
wfa.Name = wfa.Name + ' - ' + wfa.Registration_Type__c;
}
if(!String.isEmpty(wfa.Account_Number__c)){
wfa.Name = wfa.Name +  ' - ' + wfa.Account_Number__c;
}
}
}
}*/
    
    /*Method to create share record between record and related FAT's public group*/
    public void createShareRecord(Map<Id, Financial_Account__c> newMap, Map<Id, Financial_Account__c> oldMap){
        Set<Id> fAccTeamIdSet = new Set<Id>();
        for(Financial_Account__c record : newMap.values()){
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
                List<Financial_Account__Share> shareRecordList = new List<Financial_Account__Share>();
                
                //For revoke Share
                Set<Id> groupIdSet = new Set<Id>();
                Set<Id> parentIdSet = new Set<Id>();
                for(Financial_Account__c record : newMap.values()){
                    Financial_Account__Share shareRec = new Financial_Account__Share();
                    if(fATeamMap.get(record.Financial_Advisor_Team__c)!=null){
                        shareRec.ParentId = record.Id;
                        if(record.Financial_Advisor_Team__c != null){
                            shareRec.UserOrGroupId = fATeamMap.get(record.Financial_Advisor_Team__c).Public_Group_Id__c;
                        }
                        shareRec.AccessLevel = 'Edit';
                        shareRec.RowCause = Schema.Financial_Account__Share.RowCause.Manual;
                        if(oldMap == null){
                            if(record.Financial_Advisor_Team__c != null){
                                shareRecordList.add(shareRec);
                            }
                        } else if(oldMap != null && (oldMap.get(record.Id).Financial_Advisor_Team__c != record.Financial_Advisor_Team__c || oldMap.get(record.Id).OwnerId != record.OwnerId)){
                            if(oldMap.get(record.Id).Financial_Advisor_Team__c != null && fATeamMap.get(oldMap.get(record.Id).Financial_Advisor_Team__c) != null){
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
                    List<Financial_Account__Share> removeShareList = new List<Financial_Account__Share>();
                    for(Financial_Account__Share shareRec: [SELECT id, ParentId, UserOrGroupId FROM Financial_Account__Share WHERE ParentId IN: parentIdSet and UserOrGroupId IN: groupIdSet]){
                        if(groupIdSet.Contains(shareRec.UserOrGroupId) && parentIdSet.contains(shareRec.ParentId)){
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
    
    // A DPI is always held DIRECT, so stamp the custodian at creation. Insert-only: this is the
    // opening default, not an ongoing lock, so a later custodian change on an existing DPI stands.
    public void setCustodianOnDPI(List<Financial_Account__c> newList){
        for(Financial_Account__c fa : newList){
            if(fa.DPI__c == true){
                fa.Custodian__c = 'DIRECT';
            }
        }
    }

    public void setDMSOnHousehold(List<Financial_Account__c> newList, Map<Id,Financial_Account__c> oldMap){
        Set<Id> managementStyles = new Set<Id>();
        Set<Id> hhSet = new Set<Id>();
        List<Account> hhToUpdate = new List<Account>();
        for(Financial_Account__c newFinAcct : newList){
            if(oldMap == null){
                if(newFinAcct.Managed_Account_Platform__c != null && (newFinAcct.Managed_Account_Platform__c == 'DMS' || newFinAcct.Managed_Account_Platform__c == 'DMS (Wrap)')){
                    hhSet.add(newFinAcct.Household__c);
                }
            } else {
                Financial_Account__c oldFinAcct = oldMap.get(newFinAcct.Id);
                if(newFinAcct.Managed_Account_Platform__c != oldFinAcct.Managed_Account_Platform__c && newFinAcct.Managed_Account_Platform__c != null && 
                   (newFinAcct.Managed_Account_Platform__c == 'DMS' || newFinAcct.Managed_Account_Platform__c == 'DMS (Wrap)')){
                       hhSet.add(newFinAcct.Household__c);
                   }
            }
        }	
        if(!hhSet.isEmpty()){
            for(Id hhId : hhSet){
                Account hh = new Account(Id = hhId, Has_FAs_that_are_DMS__c = true);
                hhToUpdate.add(hh);
            }
        }
        if(!hhToUpdate.isEmpty()){
            update hhToUpdate;
        }
    }
    
    public static void setReportAcctNumber_Before(List<Financial_Account__c> newList, Map<Id,Financial_Account__c> oldMap){
        
        for(Financial_Account__c f : newList){
            if(!String.isEmpty(f.Account_Number__c)){
                String faNumber = f.Account_Number__c.replaceAll('-', '');
                List<String> numberList = new List<String>();
                
                if(faNumber.contains('_')){
                    numberList = faNumber.split('_');
                }
                
                if(!numberList.isEmpty()){
                    f.Account_Number_for_Report__c = numberList[0];
                } else {
                    f.Account_Number_for_Report__c = faNumber;
                }
            }
        }
    }
    public static void setReportAcctNumber_AfterInsert(List<Financial_Account__c> newList){
        
        List<Financial_Account__c> toUpdate = new List<Financial_Account__c>();
        
        for(Financial_Account__c f : newList){
            if(f.BD_or_RIA__c == 'BD' && (f.Brokerage__c == false || f.Account_Number__c == null)){
                
                f.Account_Number_for_Report__c = 'NX' + f.Id.toString().mid(7,8);
                toUpdate.add(f);
            }
        }
        
        if(!toUpdate.isEmpty()){
            update toUpdate;
        }
    }
    
    public static void setHousehold(List<Financial_Account__c> newList){
        Set<Id> setOfId = new set<Id>();
        Set<Id> setOfPrimaryOwnerId = new set<Id>();
        
        Map<Id,Id> accountIdAndPersonContIdMap = new Map<Id,Id>();
        
        for(Financial_Account__c finAcct : newList){
            if(finAcct.Household__c == null && !String.isEmpty(finAcct.Primary_Owner__c)){
                setOfPrimaryOwnerId.add(finAcct.Primary_Owner__c);
            }
        }
        List<Account> PrimaryOwners = [SELECT Id,PersonContactId FROM Account WHERE Id IN :setOfPrimaryOwnerId];
        for(Account po : PrimaryOwners){
            accountIdAndPersonContIdMap.put(po.Id,po.PersonContactId);
        }
        
        for(Financial_Account__c finAcct : newList){
            if(finAcct.Household__c == null && !String.isEmpty(finAcct.Primary_Owner__c)){
                if(accountIdAndPersonContIdMap.containsKey(finAcct.Primary_Owner__c)){
                    setOfId.add(accountIdAndPersonContIdMap.get(finAcct.Primary_Owner__c));
                }
            }
        }
        List<AccountContactRelation> acctContRelList = [SELECT AccountId,ContactId FROM AccountContactRelation WHERE ContactId IN :setOfId];
        Map<Id,Id> contactIdAndAccountIdMap = new Map<Id,Id>();
        for(AccountContactRelation acctContRel : acctContRelList){
            contactIdAndAccountIdMap.put(acctContRel.ContactId,acctContRel.AccountId);
        }
        
        for(Financial_Account__c finAcct : newList){
            if(finAcct.Household__c == null && !String.isEmpty(finAcct.Primary_Owner__c)){
                if(contactIdAndAccountIdMap.containsKey(accountIdAndPersonContIdMap.get(finAcct.Primary_Owner__c))){
                    finAcct.Household__c = contactIdAndAccountIdMap.get(accountIdAndPersonContIdMap.get(finAcct.Primary_Owner__c));
                }
            }
        }
    }
    
    public static void setFinancialAccountName(List<Financial_Account__c> FinAccounts){
        Set<Id> accountIdSet = new Set<Id>();
        for(Financial_Account__c fa : FinAccounts){
            if(!String.IsEmpty(fa.Primary_Owner__c)){
                accountIdSet.add(fa.Primary_Owner__c);
            }
        }
        
        Map<Id,Account> accountMap = new Map<Id,Account>([SELECT Id,FirstName,LastName FROM Account WHERE Id IN : accountIdSet]);
        for(Financial_Account__c fa : FinAccounts){
            if(fa.Name == null){
                if(accountMap.containsKey(fa.Primary_Owner__c)){
                    Account primaryOwner = accountMap.get(fa.Primary_Owner__c);
                    fa.Name = String.isEmpty(primaryOwner.FirstName)? '': primaryOwner.FirstName;
                    fa.Name += String.isEmpty(fa.Name)? '': ' ' ;
                    fa.Name += String.isEmpty(primaryOwner.LastName)? '': primaryOwner.LastName;
                }
                if(!String.isEmpty(fa.Registration_Type__c)){
                    fa.Name += String.isEmpty(fa.Name)? '':' - ';
                    fa.Name += fa.Registration_Type__c;
                }
                if(!String.isEmpty(fa.Account_Number__c)){
                    fa.Name += String.isEmpty(fa.Name)? '': ' - ' ;
                    fa.Name += fa.Account_Number__c;
                }
            }
            if (fa.Name != null && fa.Name.length() > 80) {
                fa.Name = fa.Name.substring(0, 80);
            }        
        }        
    }
    
    /*public void setMaestroAccountType(List<Financial_Account__c> newList, Map<Id,Financial_Account__c> oldMap){
List<Maestro_Account_Type__mdt> maestroTypes = [SELECT Id, MasterLabel, Account_Type__c, BD_RIA__c FROM Maestro_Account_Type__mdt];
Map<String,String> bdMaestroAccountTypes = new Map<String,String>();
Map<String,String> riaMaestroAccountTypes = new Map<String,String>();
for(Maestro_Account_Type__mdt m : maestroTypes){
if(m.BD_RIA__c == 'BD'){
bdMaestroAccountTypes.put(m.MasterLabel,m.Account_Type__c);
} else {
riaMaestroAccountTypes.put(m.MasterLabel,m.Account_Type__c);
}
}
if(oldMap == null){
for(Financial_Account__c f : newList){
if(f.Registration_Type__c != null){
if(f.BD_or_RIA__c == 'BD' && bdMaestroAccountTypes.get(f.Registration_Type__c) != null){
f.Maestro_Account_Type__c = bdMaestroAccountTypes.get(f.Registration_Type__c);
} else if(f.BD_or_RIA__c == 'RIA' && riaMaestroAccountTypes.get(f.Registration_Type__c) != null){
f.Maestro_Account_Type__c = riaMaestroAccountTypes.get(f.Registration_Type__c);
}
}
}
} else {
for(Financial_Account__c newFA : newList){
Financial_Account__c oldFA = oldMap.get(newFA.Id);
Boolean registrationTypeChanged = newFA.Registration_Type__c != oldFA.Registration_Type__c;
Boolean bdOrRiaChangedFromNull = oldFA.BD_or_RIA__c == null && newFA.BD_or_RIA__c != null;
if ((registrationTypeChanged || bdOrRiaChangedFromNull) && newFA.Registration_Type__c != null) {
if(newFA.BD_or_RIA__c == 'BD' && bdMaestroAccountTypes.get(newFA.Registration_Type__c) != null){
newFA.Maestro_Account_Type__c = bdMaestroAccountTypes.get(newFA.Registration_Type__c);
} else if(newFA.BD_or_RIA__c == 'RIA' && riaMaestroAccountTypes.get(newFA.Registration_Type__c) != null){
newFA.Maestro_Account_Type__c = riaMaestroAccountTypes.get(newFA.Registration_Type__c);
}
}
}
}
}*/
    public void setMaestroAccountType(List<Financial_Account__c> newList, Map<Id,Financial_Account__c> oldMap){
        
        Map<String, Registration_Type__mdt> regTypeMap = new Map<String, Registration_Type__mdt>();
        
        for(Registration_Type__mdt r : [
            SELECT MasterLabel, BD_Account_Type__c, RIA_Account_Type__c 
            FROM Registration_Type__mdt
        ]){
            regTypeMap.put(r.MasterLabel, r);
        }
        
        if(oldMap == null){
            for(Financial_Account__c f : newList){
                setAccountType(f, regTypeMap);
            }
        } else {
            for(Financial_Account__c newFA : newList){
                Financial_Account__c oldFA = oldMap.get(newFA.Id);
                
                Boolean registrationTypeChanged = newFA.Registration_Type__c != oldFA.Registration_Type__c;
                Boolean bdOrRiaChangedFromNull = oldFA.BD_or_RIA__c == null && newFA.BD_or_RIA__c != null;
                
                if ((registrationTypeChanged || bdOrRiaChangedFromNull)) {
                    setAccountType(newFA, regTypeMap);
                }
            }
        }
    }
    
    private void setAccountType(Financial_Account__c f, Map<String, Registration_Type__mdt> regTypeMap){
        system.debug('regTypeMap :'+regTypeMap);
        
        if(f.Registration_Type__c == null || f.BD_or_RIA__c == null){
            return;
        }
        
        Registration_Type__mdt meta = regTypeMap.get(f.Registration_Type__c);
        system.debug('meta :'+meta);
        if(meta == null){
            return;
        }
        
        if(f.BD_or_RIA__c == 'BD'){
            f.Maestro_Account_Type__c = meta.BD_Account_Type__c;
        } 
        else if(f.BD_or_RIA__c == 'RIA'){
            f.Maestro_Account_Type__c = meta.RIA_Account_Type__c;
        }
    }
    
    public static void setFinancialAccountNameOnUpdate(Map<Id, Financial_Account__c> newMap,Map<Id, Financial_Account__c> oldMap){
        List<Financial_Account__c> finAccountsToUpdate = new List<Financial_Account__c>();
        Set<Id> accountIdSet = new Set<Id>();
        for(Financial_Account__c fa : newMap.values()){
            if(!String.IsEmpty(fa.Primary_Owner__c)){
                accountIdSet.add(fa.Primary_Owner__c);
            }
        }
        Map<Id,Account> accountMap = new Map<Id,Account>([SELECT Id,FirstName,LastName FROM Account WHERE Id IN : accountIdSet]);
        for(Financial_Account__c fa : newMap.values()){
            if( fa.Registration_Type__c != oldMap.get(fa.Id).Registration_Type__c && !String.isEmpty(fa.Registration_Type__c)){
                if(accountMap.containsKey(fa.Primary_Owner__c)){
                    Account primaryOwner = accountMap.get(fa.Primary_Owner__c);
                    fa.Name = String.isEmpty(primaryOwner.FirstName)? '': primaryOwner.FirstName;
                    fa.Name += String.isEmpty(fa.Name)? '': ' ' ;
                    fa.Name += String.isEmpty(primaryOwner.LastName)? '': primaryOwner.LastName;
                }
                if(!String.isEmpty(fa.Registration_Type__c)){
                    fa.Name += String.isEmpty(fa.Name)? '':' - ';
                    fa.Name += fa.Registration_Type__c;
                }
                if(!String.isEmpty(fa.Account_Number__c)){
                    fa.Name += String.isEmpty(fa.Name)? '': ' - ' ;
                    fa.Name += fa.Account_Number__c;
                }
            }
        }  
    }
    
    public void setFinancialAccountOnRider(Map<Id,Financial_Account__c> newMap){
        /*Set<Id> wfaIds = new Set<Id>();
for(FinServ__FinancialAccount__c fa : newMap.values()){
if(!String.isEmpty(fa.Wizard_Financial_Account__c)){
wfaIds.add(fa.Wizard_Financial_Account__c);
}
}
List<X1035_Rider__c> riders = [SELECT Id, Wizard_Financial_Account__c FROM X1035_Rider__c WHERE Wizard_Financial_Account__c IN : wfaIds];
Map<Id,List<X1035_Rider__c>> wfaIdAndRidersMap = new Map<Id,List<X1035_Rider__c>>();
for(X1035_Rider__c rid : riders){
if(!wfaIdAndRidersMap.containsKey(rid.Wizard_Financial_Account__c)){
wfaIdAndRidersMap.put(rid.Wizard_Financial_Account__c,new List<X1035_Rider__c>());
}
wfaIdAndRidersMap.get(rid.Wizard_Financial_Account__c).add(rid);
}     

List<X1035_Rider__c> ridersToUpdate =  new List<X1035_Rider__c>();
for(FinServ__FinancialAccount__c fa : newMap.values()){
if(!String.isEmpty(fa.Wizard_Financial_Account__c) && wfaIdAndRidersMap.containsKey(fa.Wizard_Financial_Account__c)){
for(X1035_Rider__c rid : wfaIdAndRidersMap.get(fa.Wizard_Financial_Account__c)){
rid.Financial_Account__c =  fa.Id;   
ridersToUpdate.add(rid);
}         
}
}
if(!ridersToUpdate.isEmpty()){
update ridersToUpdate;
}*/
    }
    
    // A DPI's Product Type decides the kind of work its Case represents, so the wizard Case opens
    // generically as 'Account Opening' (EnvelopeISAController) and is retyped here, at submit, once
    // the interview has settled the product. Add a product type by adding a row — no code change.
    // Only product types listed here retype the Case; anything else keeps the 'Account Opening' type.
    //
    // Keyed by Financial_Account__c.Product_Type__c. Case.Type is an unrestricted picklist (the wizard
    // already writes free-text types like 'Account Opening' that are not defined picklist values), so a
    // value here need not be added in Setup — but adding it keeps reports and filters tidy.
    //
    // A value here MAY match an account-action Case Type (e.g. 'Purchase Alternative Investment', which
    // is also one of EnvelopeActionCaseController's account actions): the outline tells the two apart
    // by the Case's Financial Account being an envelope account/DPI entity, not by Type, so a retyped
    // DPI Case is not mistaken for an action item — see WizardEnvelopeStateService.readActionCases.
    private static final Map<String, String> DPI_PRODUCT_TYPE_TO_CASE_TYPE =
        new Map<String, String>{
            'Variable Annuity' => 'Purchase a Variable Annuity',
            'Alternative Investment' => 'Purchase Alternative Investment'
        };

    private void updateRelatedCase(
        Map<Id, Financial_Account__c> newMap,
        Map<Id, Financial_Account__c> oldMap
    ) {
        System.debug('updateRelatedCase');
        Set<Id> submittedFAIds = new Set<Id>();
        
        // 1. Get Financial Accounts whose Submitted__c changed from false to true
        for (Financial_Account__c fa : newMap.values()) {
            Financial_Account__c oldFA = oldMap.get(fa.Id);
            
            if (fa.Submitted__c == true && oldFA != null && oldFA.Submitted__c == false) {
                submittedFAIds.add(fa.Id);
            }
        }
        
        if (submittedFAIds.isEmpty()) {
            return;
        }
        
        // Get metadata-defined fields
        Set<String> fieldApiNames = new Set<String>();
        
        for (Envelope_Field__mdt fieldMetadata : [
            SELECT Field_API__c
            FROM Envelope_Field__mdt
            WHERE
            Type__c IN ('ISA - DPI', 'ISA - Fin Acct')
            AND Object__c = 'Financial_Account__c'
            AND Field_API__c != NULL
        ]) {
            fieldApiNames.add(fieldMetadata.Field_API__c.trim());
        }
        
        if (fieldApiNames.isEmpty()) {
            return;
        }
        
        // Validate fields exist on both Financial Account and Case
        Map<String, Schema.SObjectField> financialAccountFields = Financial_Account__c.SObjectType.getDescribe()
            .fields.getMap();
        
        Map<String, Schema.SObjectField> caseFields = Case.SObjectType.getDescribe()
            .fields.getMap();
        
        Set<String> validFieldApiNames = new Set<String>();
        System.debug('validFieldApiNames: ' + validFieldApiNames);
        
        for (String fieldApiName : fieldApiNames) {
            if (financialAccountFields.containsKey(fieldApiName) && caseFields.containsKey(fieldApiName)) {
                validFieldApiNames.add(fieldApiName);
            }
        }
		validFieldApiNames.add('Managed_Account_Platform__c');        
        if (validFieldApiNames.isEmpty()) {
            return;
        }
        
        // Get Envelope related to each Financial Account
        Map<Id, Id> faToEnvelopeMap = new Map<Id, Id>();
        
        for (Envelope_Content__c ec : [
            SELECT Envelope__c, Wizard_Financial_Account__c
            FROM Envelope_Content__c
            WHERE
            Wizard_Financial_Account__c IN :submittedFAIds
            AND Envelope__c != NULL
        ]) {
            faToEnvelopeMap.put(ec.Wizard_Financial_Account__c, ec.Envelope__c);
        }
        
        if (faToEnvelopeMap.isEmpty()) {
            return;
        }
        
        // Get Cases related to the Financial Accounts
        List<Case> relatedCases = [
            SELECT Id, Wizard_Financial_Account__c, Submitted__c, Recalculate_Case_Template__c
            FROM Case
            WHERE Wizard_Financial_Account__c IN :submittedFAIds
        ];
        
        if (relatedCases.isEmpty()) {
            return;
        }
        
        //Get Envelope related to each Case
        Map<Id, Id> caseToEnvelopeMap = new Map<Id, Id>();
        
        for (Envelope_Content__c ec : [
            SELECT Case__c, Envelope__c
            FROM Envelope_Content__c
            WHERE Case__c IN :relatedCases AND Envelope__c != NULL
        ]) {
            caseToEnvelopeMap.put(ec.Case__c, ec.Envelope__c);
        }
        
        // Match Financial Account + Case using the same Envelope
        List<Case> casesToUpdate = new List<Case>();
        System.debug('c.Id: ' + relatedCases[0].Id);
        
        for (Case c : relatedCases) {
            Id financialAccountId = c.Wizard_Financial_Account__c;
            
            Id financialAccountEnvelope = faToEnvelopeMap.get(financialAccountId);
            
            Id caseEnvelope = caseToEnvelopeMap.get(c.Id);
            
            // Case must belong to the same Envelope as Financial Account
            if (
                financialAccountEnvelope == null ||
                caseEnvelope == null ||
                financialAccountEnvelope != caseEnvelope
            ) {
                continue;
            }
            
            // Get Financial Account directly from Trigger.newMap
            Financial_Account__c fa = newMap.get(financialAccountId);
            
            if (fa == null) {
                continue;
            }
            
            for (String fieldApiName : validFieldApiNames) {
                Object value = fa.get(fieldApiName);
                System.debug('fieldApiName: ' + fieldApiName);
                if(fieldApiName == 'Managed_Account_Platform__c'){
                    fieldApiName = 'Management_Style__c';
                }
                    c.put(fieldApiName, value);
                	
                System.debug('value: ' + value);
                System.debug('fieldApiName: ' + fieldApiName);
            }

            // Retype a DPI's Case from its Product Type. Only DPIs carry a product-driven Case type;
            // a regular account keeps whatever type it opened with. A product type not in the map (or
            // a blank one) leaves the Case type untouched rather than clearing it.
            if (fa.DPI__c == true && fa.Product_Type__c != null) {
                String mappedCaseType = DPI_PRODUCT_TYPE_TO_CASE_TYPE.get(fa.Product_Type__c);
                if (mappedCaseType != null) {
                    c.Type = mappedCaseType;
                }
            }

          	c.Recalculate_Case_Template__c = true;
            casesToUpdate.add(c);
        }
        
        if (!casesToUpdate.isEmpty()) {
            update casesToUpdate;
        }
    }
    
}