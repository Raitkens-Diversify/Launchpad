@isTest
public class Task_Comment_TriggerHandlerTest {

    /*@testSetup
    private static void setup(){
        Wizard_Financial_Account__c testWFA = new Wizard_Financial_Account__c(Name = 'Test Financial Account');
        insert testWFA;
        
        Financial_Advisor_Team__c testFAT = new Financial_Advisor_Team__c(Name = 'Test FAT');
        insert testFAT;
        
        List<Account> accList = new List<Account>();
        accList.add(new Account(Name = 'Test Account', Financial_Advisor_Team__c = testFAT.Id));
        accList.add(new Account(Name = 'Test Account 2'));
        insert accList;
        
        Contact con = new Contact(LastName = 'Test', Email = 'test.test@dfpg.com');
        insert con;
        
        
        Financial_Advisor_Team_Member__c fatm = new Financial_Advisor_Team_Member__c(Role__c = 'Financial Advisor', Active__c = true, Financial_Advisor_Team__c = testFAT.Id);
        //insert fatm;
     
    }
    
    @isTest
    public static void testTaskComment(){
        Case newCase = new Case(Origin = 'Web', Status = 'New');
        insert newCase;
        Task newTask = new Task(WhatId = newCase.Id, Status = 'New');
        insert newTask;
        Task_Comment__c taskComment = new Task_Comment__c(Task_Id__c = newTask.Id, CommentBody__c = 'test');
        
        Test.startTest();
        insert taskComment;
        Test.stopTest();
        
        List<CaseComment> caseComments = [SELECT Id FROM CaseComment WHERE ParentId = :newCase.Id LIMIT 1];
        Assert.areEqual(1, caseComments.size());
        
        //For coverage
        delete taskComment;
        undelete taskComment;
        
    }
    
    @isTest
    public static void testTaskCommentUpdate(){
        Case newCase = new Case(Origin = 'Web', Status = 'New');
        insert newCase;
        Task newTask = new Task(WhatId = newCase.Id, Status = 'New');
        insert newTask;
        Task_Comment__c taskComment = new Task_Comment__c(Task_Id__c = newTask.Id, CommentBody__c = 'test');
        insert taskComment;
        
        Test.startTest();
        Task_Comment__c tc = [SELECT Id, CommentBody__c FROM Task_Comment__c LIMIT 1];
        tc.CommentBody__c = 'Test 2';
        update tc;
        Test.stopTest();
        
        List<CaseComment> caseComments = [SELECT Id, CommentBody FROM CaseComment WHERE ParentId = :newCase.Id LIMIT 1];
        Assert.areEqual('Test 2', caseComments[0].CommentBody);
        
    }
    
    @isTest
    private static void getExistingRecordsTest(){
        
        Case newCase = new Case(Origin = 'Web', Status = 'New');
        insert newCase;
        Task newTask = new Task(WhatId = newCase.Id, Status = 'New');
        insert newTask;
        Task_Comment__c taskComment = new Task_Comment__c(Task_Id__c = newTask.Id, CommentBody__c = 'test');
        insert taskComment;
        
        Test.startTest();
        List<Task_Comment__c> lstRecords = TaskCommentController.getComments(newTask.Id);
        Test.stopTest();
        Assert.isTrue(lstRecords.size() == 1, 'Method should return list.');
    }*/
}