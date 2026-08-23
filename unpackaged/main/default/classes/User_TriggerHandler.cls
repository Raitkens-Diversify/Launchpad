/**
* User_TriggerHandler - 
* @description Handler of the User_Trigger
* @author Metacube software
* @date 2020-07-01
*/
public without sharing class User_TriggerHandler {
    public User_TriggerHandler() {}
    public void isBeforeInsert(List<User> newList){}
    public void isBeforeUpdate(Map<Id, User> newMap, Map<Id, User> oldMap){}
    
    public void isAfterInsert(Map<Id, User> newMap){
        updateFATMRecordUserField(newMap, Null);
    }
    
    public void isAfterUpdate(Map<Id, User> newMap, Map<Id, User> oldMap){
        updateFATMRecordUserField(newMap, oldMap);
        setRegisteredStateOnFATM(newMap, oldMap);
    }
    
    private void updateFATMRecordUserField(Map<Id, User> newMap, Map<Id, User> oldMap){
        Set<String> advisorSSNSet = new Set<String>();
        for(User record : newMap.values()){
            if((oldMap == null && String.isNotBlank(record.Advisor_SSN__c)) || (oldMap != null && record.Advisor_SSN__c != oldMap.get(record.Id).Advisor_SSN__c)){
                advisorSSNSet.add(record.Advisor_SSN__c);
            }
        }   
        if(!advisorSSNSet.isEmpty()){
            List<Financial_Advisor_Team_Member__c> fatmList = [SELECT Id, User_SSN__c, User__c FROM Financial_Advisor_Team_Member__c WHERE User_SSN__c IN : advisorSSNSet];
            Map<String, List<Financial_Advisor_Team_Member__c>> ssnWithFATMRecordsMap = new Map<String, List<Financial_Advisor_Team_Member__c>>();
            for(Financial_Advisor_Team_Member__c fatmRec : fatmList){
                if(ssnWithFATMRecordsMap.containsKey(fatmRec.User_SSN__c)) {
                    List<Financial_Advisor_Team_Member__c> fatmRecList = ssnWithFATMRecordsMap.get(fatmRec.User_SSN__c);
                    fatmRecList.add(fatmRec);
                    ssnWithFATMRecordsMap.put(fatmRec.User_SSN__c, fatmRecList);
                } else {
                    ssnWithFATMRecordsMap.put(fatmRec.User_SSN__c, new List<Financial_Advisor_Team_Member__c> {fatmRec});
                }
            }
            List<Financial_Advisor_Team_Member__c> toBeUpdateFATMList = new List<Financial_Advisor_Team_Member__c>();
            for(User record : newMap.values()){
                if(String.isNotBlank(record.Advisor_SSN__c) && ssnWithFATMRecordsMap.get(record.Advisor_SSN__c) != null){
                    List<Financial_Advisor_Team_Member__c> fATMRecList = ssnWithFATMRecordsMap.get(record.Advisor_SSN__c);
                    for(Financial_Advisor_Team_Member__c fatmRec : fATMRecList){
                        fatmRec.User__c = record.Id;
                        toBeUpdateFATMList.add(fatmRec);
                    }
                }
            }   
            update toBeUpdateFATMList;
        }
    }
    
    private void setRegisteredStateOnFATM(Map<Id,User> newMap, Map<Id,User> oldMap){
        Map<Id,List<Financial_Advisor_Team_Member__c>> fatMap=new Map<Id,List<Financial_Advisor_Team_Member__c>>();
        List<Financial_Advisor_Team_Member__c> fatmList=[select Id,Registered_States__c,User__c from Financial_Advisor_Team_Member__c where User__c IN:newMap.keySet()];
        List<Financial_Advisor_Team_Member__c> fatmToBeUpdated=new List<Financial_Advisor_Team_Member__c>();
        
        for(Financial_Advisor_Team_Member__c fatm:fatmList){
            if(fatm.User__c !=null){
                if(fatMap.containsKey(fatm.User__c)){
                    List<Financial_Advisor_Team_Member__c> fatmember=fatMap.get(fatm.User__c);
                    fatMember.add(fatm);
                    fatMap.put(fatm.User__c,fatMember);  
                }else{
                    fatMap.put(fatm.User__c,new List<Financial_Advisor_Team_Member__c>{fatm});
                }
                
            }
        }
        for(User u:newMap.values()){
            User oldUser=oldMap.get(u.Id);
            if(u.Registered_States__c !=oldUser.Registered_States__c){
                if(u.Registered_States__c !=null && !fatMap.isEmpty() && fatMap.containsKey(u.Id)){
                    for(Financial_Advisor_Team_Member__c fatm: fatMap.get(u.Id)){
                        fatm.Registered_States__c=u.Registered_States__c;
                        fatmToBeUpdated.add(fatm);
                    }
                }
            }
        }
        if(fatmToBeUpdated.size()>0){
            update fatmToBeUpdated; 
        }
        
    }
}