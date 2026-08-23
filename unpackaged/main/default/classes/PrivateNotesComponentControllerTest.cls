@isTest
private class PrivateNotesComponentControllerTest{
    
    private static testMethod void testPrivateNotesComponentController() {
        String recTypeId = [SELECT Id FROM RecordType WHERE (Name = 'Person Account') AND (SobjectType = 'Account')].Id;
        String recTypeIdHouseHold = [SELECT Id FROM RecordType WHERE (Name = 'Household') AND (SobjectType = 'Account')].Id;
        
        Account newAccount = new Account(RecordTypeID = recTypeId, FirstName = 'Test FName', LastName = 'Test LName', PersonEmail = 'test@test.com');        
        Account newHouseHoldAccount = new Account(RecordTypeID = recTypeIdHouseHold, Name = 'Test');        
        insert new List<Account>{newAccount, newHouseHoldAccount};         
            
            Notes__c notes = new Notes__c(Name = 'Test', Note__c = 'Test', Type__c = 'Call', Client__c = newAccount.Id);
        Notes__c noteHouseHold = new Notes__c(Name = 'Test', Note__c = 'Test', Type__c = 'Call', Household__c = newHouseHoldAccount.Id);
        List<Notes__c> lstNotes = new List<Notes__c>{notes, noteHouseHold};  
        insert lstNotes;
            
            PrivateNotesComponentController.NoteWrapper wrap = PrivateNotesComponentController.fetchNotesRecords(newAccount.Id, 'Account');
        System.assertEquals('Client__c', wrap.fieldName, 'Notes Wrappper field Name should be Client');
        System.assertEquals(1, wrap.notesList.size(), 'Notes size should be 1');
        
        wrap = PrivateNotesComponentController.fetchNotesRecords(newHouseHoldAccount.Id, 'Account');
        System.assertEquals('Household__c', wrap.fieldName, 'Notes Wrappper field Name should be Household');
        System.assertEquals(1, wrap.notesList.size(), 'Notes size should be 1');
        
        Test.startTest();
        PrivateNotesComponentController.NoteWrapper notesList = PrivateNotesComponentController.searchNotesRecords(newAccount.Id, 'Test', 'Call', Null, Null,lstNotes);
        //System.assertEquals(1, notesList.size(), 'Notes size should be 1');
        
        notesList = PrivateNotesComponentController.searchNotesRecords(newAccount.Id, 'Test', 'Call, Meeting', Null, Date.today(),lstNotes);
        //System.assertEquals(0, notesList.size(), 'Notes size should be zero');
        Test.stopTest();
        
        notesList = PrivateNotesComponentController.searchNotesRecords(newAccount.Id, 'Test', 'Call, Meeting', Date.today(), Null,lstNotes);
    }
    
    private static testMethod void testGetNotesTemplatesNotNull(){
        Notes_Template__c noteTemplate = new Notes_Template__c(
            Name='Call Note', 
            Note__c='This is a test template note');
        insert noteTemplate;
        
        Test.startTest();
        Map<String, String> noteTemplate1 = PrivateNotesComponentController.getNotesTemplates();
        Test.stopTest();
        Set<String> templateName = noteTemplate1.keySet();
        System.assertEquals('Call Note', templateName.iterator().next());
    }
    
    private static testMethod void testGetNotesTemplatesPublic(){
        Notes_Template__c noteTemplate = new Notes_Template__c(
            Name='Call Note', 
            Note__c='This is a test template note',
            Is_Public__c=true);
        insert noteTemplate;
        
        Test.startTest();
        Map<String, String> noteTemplate1 = PrivateNotesComponentController.getNotesTemplates();
        Test.stopTest();
        Set<String> templateName = noteTemplate1.keySet();
        System.assertEquals('Call Note', templateName.iterator().next());
    }
    private static testMethod void testGetNotesTemplatesNull(){
        Test.startTest();
        Map<String, String> noteTemplate1 = PrivateNotesComponentController.getNotesTemplates();
        Test.stopTest();
        System.assertEquals(null, noteTemplate1);
    }
}