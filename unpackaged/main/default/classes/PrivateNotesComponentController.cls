public without sharing class PrivateNotesComponentController {
    
    @AuraEnabled 
    public static NoteWrapper fetchNotesRecords(String parentObjectId, String sObjectName){
        List<Notes__c> notesList = [Select Id, Name, CreatedDate, Type__c, Note__c, CreatedById, Created_Date__c, CreatedBy.Name From Notes__c
                                    Where Client__c =: parentObjectId OR Household__c =: parentObjectId
                                    OR Financial_Account__c =: parentObjectId
                                    Order By CreatedDate DESC];
        String fieldName = '';
        system.debug('Account :'+sObjectName);
        List<Notes__c> notesToggleList = new List<Notes__c>();
        if(sObjectName == 'Account'){
            String recordTypeName = [Select Id, RecordType.Name From Account Where id =: parentObjectId].RecordType.Name;
            system.debug('recordTypeName :'+recordTypeName);
            if(recordTypeName == 'Household'){
                fieldName = 'Household__c';
            }
            if(recordTypeName == 'Person Account'){
                fieldName = 'Client__c';
                List<FinServ__FinancialAccountRole__c> finAccRoleList = [SELECT Id, FinServ__FinancialAccount__c FROM FinServ__FinancialAccountRole__c 
                                                                         WHERE FinServ__RelatedAccount__c =: parentObjectId];
                Set<Id> finAccSet = new Set<Id>();
                for(FinServ__FinancialAccountRole__c record : finAccRoleList) {
                    finAccSet.add(record.FinServ__FinancialAccount__c);
                }
                notesToggleList = [SELECT Id, Name, CreatedDate, Type__c, Note__c, CreatedById, Created_Date__c, CreatedBy.Name FROM Notes__c
                                   WHERE Financial_Account__c IN:  finAccSet OR Client__c =: parentObjectId Order By CreatedDate DESC];
                } else if(recordTypeName == 'Household' || recordTypeName == 'Albridge Portfolio'){
                    List<FinServ__FinancialAccountRole__c> finAccRoleList = [SELECT Id, FinServ__FinancialAccount__c FROM FinServ__FinancialAccountRole__c 
                                                                                WHERE FinServ__RelatedAccount__c =: parentObjectId];
                    Set<Id> finAccSet = new Set<Id>();
                    for(FinServ__FinancialAccountRole__c record : finAccRoleList) {
                        finAccSet.add(record.FinServ__FinancialAccount__c);
                    }
                    List<AccountContactRelation> accConRelationList = [SELECT Id, ContactId, AccountId FROM AccountContactRelation 
                                                                        WHERE AccountId  =: parentObjectId];
                    Set<Id> contactIdSet = new Set<Id>();
                    for(AccountContactRelation record : accConRelationList) {
                        contactIdSet.add(record.ContactId);
                    }
                    List<Contact> conList = [SELECT Id, AccountId FROM Contact WHERE Id IN: contactIdSet];
                    Set<Id> accIdSet = new Set<Id>();
                    for(Contact record : conList) {
                        accIdSet.add(record.AccountId);
                    }
                    notesToggleList = [SELECT Id, Name, CreatedDate, Type__c, Note__c, CreatedById, Created_Date__c, CreatedBy.Name FROM Notes__c
                                        WHERE Financial_Account__c IN: finAccSet OR Household__c =: parentObjectId
                                        OR Client__c IN: accIdSet
                                        Order By CreatedDate DESC];
                }
            
        } else if(sObjectName == 'FinServ__FinancialAccount__c'){
            fieldName = 'Financial_Account__c';
        }
        NoteWrapper wrapper = new NoteWrapper(notesList, fieldName, notesToggleList);
        return wrapper;
    }
    
    @AuraEnabled 
    public static NoteWrapper searchNotesRecords(String parentObjectId, String searchStr,  String typeStr, Date startDate, Date endDate, List<Notes__c> toggleNoteList){
        system.debug('startDate :'+startDate);
        system.debug('endDate :'+endDate);
        system.debug('typeStr :'+typeStr);
        system.debug('searchStr :'+searchStr);
        String queryStr = 'Select Id, Name, CreatedDate, Type__c, Note__c, CreatedById, Created_Date__c, CreatedBy.Name From Notes__c Where (Client__c =: parentObjectId OR Household__c =: parentObjectId OR Financial_Account__c =: parentObjectId) ';
        
        if(String.isNotBlank(typeStr)){
            List<String> typeValuesList = new List<String> ();
            if(typeStr.contains(',')){
                typeValuesList = typeStr.split(',');
            } else{
                typeValuesList.add(typeStr);
            }
            queryStr +=' AND Type__c IN : typeValuesList ';
        }
        
        if(startDate != null && endDate == null){
            System.debug('endDate: ' + endDate);
            endDate = Date.today().addDays(1);
            Date testDate = Date.today();
            System.debug('testDate: ' + testDate);
            Time elevenFiftyNine = Time.newInstance(11,59,59,59);
            DateTime testDateTime = DateTime.newInstance(testDate, elevenFiftyNine);
            System.debug('testDateTime: ' + testDateTime); 
            System.debug('endDate plus 1: ' + endDate);
            System.debug('startDate: ' + startDate);
            system.debug('endDate null case :'+endDate);
            queryStr += ' AND (CreatedDate <=:endDate AND CreatedDate >= :startDate) ';
        } else if(startDate == null && endDate != null){
            queryStr += ' AND (CreatedDate <=:endDate) ';
        } else if(startDate != null && endDate != null){
            endDate = endDate.addDays(1);
            queryStr += ' AND (CreatedDate <=:endDate AND CreatedDate >= :startDate) ';
        }
        
        queryStr +=' Order By CreatedDate DESC';
        system.debug('notesList:'+queryStr);
        List<Notes__c> notesList = Database.query(queryStr);
        system.debug('notesList:'+notesList);
        List<Notes__c> filteredList = new  List<Notes__c>();
        List<Notes__c> filterToggleNotes = filterToggleNotes(searchStr, typeStr, startDate, endDate, toggleNoteList);
        NoteWrapper wrapper = new NoteWrapper(notesList, '', filterToggleNotes);
        if(String.isNotBlank(searchStr)){
            for(Notes__c note : notesList){
                if((String.isNotBlank(note.Name) && note.Name.toLowerCase().contains(searchStr.toLowerCase().trim())) || 
                   (String.isNotBlank(note.Note__c)  && note.Note__c.toLowerCase().contains(searchStr.toLowerCase().trim()))){
                       filteredList.add(note);
                }
            }
            wrapper = new NoteWrapper(filteredList, '', filterToggleNotes);
        } else{
            wrapper = new NoteWrapper(notesList, '', filterToggleNotes);
        }
        return wrapper;
    }
    
    @AuraEnabled
    public static Map<String, String> getNotesTemplates(){
        Profile p = [SELECT Id FROM Profile WHERE Name LIKE '%System Administrator%'];
        Map<String, String> templatesMap = new Map<String, String>();
        for(Notes_Template__c tem : [SELECT Id, Name,  Note__c, Is_Public__c, CreatedById FROM Notes_Template__c]){
            if(tem.Is_Public__c == true){
                templatesMap.put(tem.Name, tem.Note__c);
            } else if(tem.Is_Public__c == false && tem.CreatedById == UserInfo.getUserId()){
                templatesMap.put(tem.Name, tem.Note__c);
            } else if(UserInfo.getProfileId() == p.Id){
                templatesMap.put(tem.Name, tem.Note__c);
            }
        }
        if(!templatesMap.isEmpty()){
            system.debug('templatesMap::>>'+templatesMap);
            return templatesMap;
        }
        return null;
    }
    public without sharing class NoteWrapper {
        @AuraEnabled public List<Notes__c> notesList{get;set;}
        @AuraEnabled public String fieldName{get;set;}
        @AuraEnabled public List<Notes__c> notesToggleList{get;set;}
        public NoteWrapper(List<Notes__c> notesList, String fieldName, List<Notes__c> notesToggleList)  {
            this.notesList = notesList;
            this.fieldName = fieldName;
            this.notesToggleList = notesToggleList;
        }
    }

    private static List<Notes__c> filterToggleNotes(String searchStr,  String typeStr, Date startDate, Date endDate, List<Notes__c> toggleNoteList){
        Set<Id> notesIdSet = new Set<Id>();
        for(Notes__c note : toggleNoteList){
            notesIdSet.add(note.id);
        }
        String queryStr = 'Select Id, Name, CreatedDate, Type__c, Note__c, CreatedById, Created_Date__c, CreatedBy.Name From Notes__c Where Id IN: notesIdSet  ';
        if(String.isNotBlank(typeStr)){
            List<String> typeValuesList = new List<String> ();
            if(typeStr.contains(',')){
                typeValuesList = typeStr.split(',');
            } else{
                typeValuesList.add(typeStr);
            }
            queryStr +=' AND Type__c IN : typeValuesList ';
        }
     
        if(startDate != null && endDate == null){
            endDate = Date.today().addDays(1);
            queryStr += ' AND (CreatedDate <=:endDate AND CreatedDate >= :startDate) ';
        } else if(startDate == null && endDate != null){
            queryStr += ' AND (CreatedDate <=:endDate) ';
        } else if(startDate != null && endDate != null){
            endDate = endDate.addDays(1);
            queryStr += ' AND (CreatedDate <=:endDate AND CreatedDate >= :startDate) ';
        }
     
        queryStr +=' Order By CreatedDate DESC';
        List<Notes__c> notesList = Database.query(queryStr);
        List<Notes__c> filteredList = new  List<Notes__c>();
        if(String.isNotBlank(searchStr)){
            for(Notes__c note : notesList){
                if((String.isNotBlank(note.Name) && note.Name.toLowerCase().contains(searchStr.toLowerCase().trim())) || 
                (String.isNotBlank(note.Note__c)  && note.Note__c.toLowerCase().contains(searchStr.toLowerCase().trim()))){
                    filteredList.add(note);
                }
            }
            return filteredList;
        } else{
            return notesList;
        }
    }
}