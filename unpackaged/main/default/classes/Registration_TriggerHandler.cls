public class Registration_TriggerHandler {
    //List of Ids for all matching Registrations
    public static Set<Id> existingMatchRecIds = new Set<Id>();
    
    public void isBeforeInsert(List<Registration__c> newList){
        setUserOnRegistrations(newList);
        setCRDOnRegistrations(newList);
    }
    
    public void isBeforeUpdate(Map<Id, Registration__c> newMap, Map<Id, Registration__c> oldMap){
        
    }
    
    public void isBeforeDelete(Map<Id, Registration__c> oldMap){
    
    }
    
    public void isAfterInsert(Map<Id, Registration__c> newMap){
        setEndDateOnExpiredRegs(newMap);
        deleteDuplicateRegistrations(newMap);
        setRegisteredStatesOnFAT();
    }
    
    public void isAfterUpdate(Map<Id, Registration__c> newMap, Map<Id, Registration__c> oldMap){
    
    }
    
    public void isAfterDelete(Map<Id, Registration__c> oldMap){
        
    }
    
    public void isAfterUndelete(Map<Id, Registration__c> newMap){
        
    }
    
    public void setUserOnRegistrations(List<Registration__c> newList){
        Set<String> crdList = new Set<String>();
        Set<String> stateList = new Set<String>();
        Map<String, Registration__c> mapUniqueKeyToExistingReg = new Map<String, Registration__c>();
        Map<String, Id> mapCRDToUserId = new Map<String, Id>(); 
        
        for(Registration__c reg : newList){
            if(reg.CRD__c != null && reg.State__c != null){
                crdList.add(reg.CRD__c);
                stateList.add(reg.State__c);            
            }
        } 
        
        List<Registration__c> existingRegs = [SELECT Id, CRD__c, State__c FROM Registration__c WHERE
                                              CRD__c IN :crdList AND State__c IN :stateList];
        for(Registration__c reg : existingRegs){
            String regFormatString = reg.CRD__c + ':' + reg.State__c;
            mapUniqueKeyToExistingReg.put(regFormatString, reg);
        }    
        
        List<User> usrList = [SELECT Id, CRD__c FROM User WHERE CRD__c IN :crdList];
        for(User u : usrList){
            mapCRDToUserId.put(u.CRD__c, u.Id);
        }
        
        //Loop to get Id of existing matching records and to set Active and User values on new unique records
        for(Registration__c reg : newList){
            if(reg.User__c == null){
                String regFormatString = reg.CRD__c + ':' + reg.State__c;
                if(!mapUniqueKeyToExistingReg.isEmpty() && mapUniqueKeyToExistingReg.containsKey(regFormatString)){
                    //reg.addError('Duplicate found');
                    existingMatchRecIds.add(mapUniqueKeyToExistingReg.get(regFormatString).Id);
                }
                else{
                    reg.Active__c = true;
                    reg.User__c = (!mapCRDToUserId.isEmpty() && mapCRDToUserId.containsKey(reg.CRD__c))
                        ? mapCRDToUserId.get(reg.CRD__c) : null;
                }
            }
        }
    }
    
    public void setCRDOnRegistrations(List<Registration__c> newList){
        Set<Id> userIds = new Set<Id>();
        Map<Id,String> userIdsToCRD = new Map<Id,String>();
        List<Registration__c> registrationsToUpdate = new List<Registration__c>();
        for(Registration__c r : newList){
            if(r.User__c != null && r.CRD__c == null){
                r.isManuallyCreated__c = true;
                userIds.add(r.User__c);
                registrationsToUpdate.add(r);
            }
        }
        List<User> users = [SELECT Id, CRD__c FROM User WHERE Id in: userIds];
        for(User u : users){
            userIdsToCRD.put(u.Id, u.CRD__c);
        }
        for(Registration__c r : registrationsToUpdate){
            r.CRD__c = userIdsToCRD.get(r.User__c);
        }
    }
    
    public void setEndDateOnExpiredRegs(Map<Id, Registration__c> newMap){
        Boolean skipEndDate = false;
        if(newMap.size() == 1){
            for(Registration__c r : newMap.values()){
                if(r.isManuallyCreated__c == true){
                    skipEndDate = true;
                }
            }
        }
        if(!skipEndDate){
            Set<Id> activeRegIds = new Set<Id>();
            activeRegIds.addAll(newMap.keySet());
            activeRegIds.addAll(existingMatchRecIds);
            System.debug('activeRegIds: ' + activeRegIds);
            //Getting All the Registrations which are not part of active and new created registrations
            List<Registration__c> existingRegsToUpdate = [SELECT Id, End_Date__c FROM Registration__c WHERE Id NOT IN :activeRegIds AND End_Date__c = null AND (isManuallyCreated__c = false OR (isManuallyCreated__c = true AND CreatedDate != Today))];
            
            System.debug('existingRegsToUpdate: ' + existingRegsToUpdate);
            //Set End Date 
            for(Registration__c reg : existingRegsToUpdate){
                reg.End_Date__c = Date.Today();
                reg.Active__c = false;
            }
            if(!existingRegsToUpdate.isEmpty()){
                update existingRegsToUpdate;
            }
        }
    }
    
    public void deleteDuplicateRegistrations(Map<Id, Registration__c> newMap){
        //Delete new matching records
        List<Registration__c> duplicateNewRegsToDelete = [SELECT Id, Name FROM Registration__c WHERE Id IN :newMap.keySet() AND Active__c = false];
        if(!duplicateNewRegsToDelete.isEmpty()){
            delete duplicateNewRegsToDelete;
        }
    }
    
    @future
    public static void setRegisteredStatesOnFAT(){
        List<Financial_Advisor_Team__c> fatsToUpdate = new List<Financial_Advisor_Team__c>();
        Map<Id, List<String>> mapFATIdtoFATMstates = new Map<Id, List<String>>();
        List<Financial_Advisor_Team_Member__c> fatmList = [SELECT Id, Name, Role__c, Registered_States__c, Financial_Advisor_Team__c
                                                           FROM Financial_Advisor_Team_Member__c WHERE Role__c = 'Financial Advisor' AND
                                                           Registered_States__c != null and User__r.CRD__c != null and User__r.Registered_States__c != null];
        for(Financial_Advisor_Team_Member__c fatm : fatmList){
            if(!mapFATIdtoFATMstates.containsKey(fatm.Financial_Advisor_Team__c)) {
                mapFATIdtoFATMstates.put(fatm.Financial_Advisor_Team__c, new List<String> {fatm.Registered_States__c});
            }
            else{
                List<String> existingStates = mapFATIdtoFATMstates.get(fatm.Financial_Advisor_Team__c);
                existingStates.add(fatm.Registered_States__c);
                mapFATIdtoFATMstates.put(fatm.Financial_Advisor_Team__c, existingStates);
            }
        }
        
        for (Id fatId : mapFATIdtoFATMstates.keySet()) {
            Financial_Advisor_Team__c fatObj = new Financial_Advisor_Team__c(Id = fatId);
            Set<String> commonStates = new Set<String>();
            List<String> fatmStates = mapFATIdtoFATMstates.get(fatId);
            
            if (fatmStates != null && !fatmStates.isEmpty()) {
                // Convert the comma-separated strings into sets of states
                List<Set<String>> fatmStatesSets = new List<Set<String>>();
                for (String fatmStateStr : fatmStates) {
                    fatmStatesSets.add(new Set<String>(fatmStateStr.split(',')));
                }
                
                // Calculate the common states from the sets of states
                commonStates.addAll(fatmStatesSets[0]);
                for (Integer i = 1; i < fatmStatesSets.size(); i++) {
                    commonStates.retainAll(fatmStatesSets[i]);
                }
            }
            
            // Convert the set of common states back to a comma-separated string
            String commonStatesStr = String.join(new List<String>(commonStates), ',');
            
            // Update the Finanical Account Team with the common states string
            fatObj.Registered_States__c = commonStatesStr;
            fatsToUpdate.add(fatObj);
        }
        
        if(!fatsToUpdate.isEmpty()){
            update fatsToUpdate;
        }
    }
}