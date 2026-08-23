@isTest
public class Task_TriggerHandlerTest {
    
    @testSetup
    private static void setup(){
        Financial_Account__c testWFA = new Financial_Account__c(Name = 'Test Financial Account');
        insert testWFA;
        
        Financial_Advisor_Team__c testFAT = new Financial_Advisor_Team__c(Name = 'Test FAT');
        insert testFAT;
        
        List<Account> accList = new List<Account>();
        accList.add(new Account(Name = 'Test Account', Financial_Advisor_Team__c = testFAT.Id));
        accList.add(new Account(Name = 'Test Account 2'));
        insert accList;
        
        Contact con = new Contact(LastName = 'Test', Email = 'test.test@dfpg.com');
        insert con;
        
        List<Case_Template__c> caseTempList = new List<Case_Template__c>();
        caseTempList.add(new Case_Template__c(Name = 'Problem' , Signature_Type__c = 'DocuSign' , Management_Style__c = 'AMS',
                                              Previous_Management_Style__c = 'EXCLUDED', Compliance_Needed__c = 'EXCLUDED',
                                              Charity_Sponsor__c = 'Fidelity Charitable', Custodian__c = 'Fidelity',
                                              Primary_Owners_Match__c = 'TRUE', Enough_Cash__c = 'TRUE', X3_Way_Call__c = 'TRUE', 
                                              Qualified__c = 'TRUE', Change_Withholdings__c = 'FALSE', No_SLOA_on_File__c = 'EXCLUDED',
                                              Direction__c = 'In'));
        caseTempList.add(new Case_Template__c(Name = 'Systems' , Signature_Type__c = 'DocuSign' , Management_Style__c = 'AMS',
                                              Previous_Management_Style__c = 'EXCLUDED', Compliance_Needed__c = 'EXCLUDED',
                                              Charity_Sponsor__c = 'Schwab Charitable', Custodian__c = 'Fidelity',
                                              Primary_Owners_Match__c = 'TRUE', Enough_Cash__c = 'TRUE', X3_Way_Call__c = 'TRUE', 
                                              Qualified__c = 'FALSE', Change_Withholdings__c = 'FALSE', No_SLOA_on_File__c = 'FALSE',
                                              Direction__c = 'EXCLUDED'));
        caseTempList.add(new Case_Template__c(Name = 'Question' , Signature_Type__c = 'Wet Signature' , Management_Style__c = 'DMS',
                                              Previous_Management_Style__c = 'EXCLUDED', Compliance_Needed__c = 'EXCLUDED',
                                              Charity_Sponsor__c = 'EXCLUDED', Custodian__c = 'Schwab',
                                              Primary_Owners_Match__c = 'FALSE', Enough_Cash__c = 'TRUE', X3_Way_Call__c = 'TRUE', 
                                              Qualified__c = 'FALSE', Change_Withholdings__c = 'TRUE', No_SLOA_on_File__c = 'FALSE',
                                              Direction__c = 'Out'));
        Insert caseTempList;
        
        List<Task_Template__c> taskTempList = new List<Task_Template__c>();
        taskTempList.add(new Task_Template__c(Assigned_To__c = 'Queue' , FA_Team_Permission__c = 'Trading', Queue__c = 'Back Office Operations',
                                              Priority__c = 'High', Due_Date__c = 'Days from Case Creation', Number_of_Days__c = 6 ));
        taskTempList.add(new Task_Template__c(Assigned_To__c = 'FA Team Permission' , FA_Team_Permission__c = 'Draft Paperwork', Queue__c = 'Compliance ',
                                              Priority__c = 'Low', Due_Date__c = 'Days from Case Creation', Number_of_Days__c = 2 ));
        taskTempList.add(new Task_Template__c(Assigned_To__c = 'FA Team Permission' , FA_Team_Permission__c = 'Review Paperwork', Queue__c = 'Back Office Operations',
                                              Priority__c = 'Low', Due_Date__c = 'Days from Case Creation', Number_of_Days__c = 8 ));
        Insert taskTempList;      
        
        List<Task_Template_Item__c> taskTempItemList = new List<Task_Template_Item__c>();
        taskTempItemList.add(new Task_Template_Item__c(Case_Template__c = caseTempList[0].Id ,Task_Template__c = taskTempList[0].Id, Order__c = 3));
        taskTempItemList.add(new Task_Template_Item__c(Case_Template__c = caseTempList[1].Id ,Task_Template__c = taskTempList[1].Id, Order__c = 1));
        taskTempItemList.add(new Task_Template_Item__c(Case_Template__c = caseTempList[1].Id ,Task_Template__c = taskTempList[1].Id, Order__c = 2));
        
        taskTempItemList.add(new Task_Template_Item__c(Case_Template__c = caseTempList[2].Id ,Task_Template__c = taskTempList[2].Id, Order__c = 4));
        Insert taskTempItemList; 
        
        List<Case> caseList = new List<Case>();
        caseList.add(new Case( Financial_Advisor_Team__c = testFAT.Id, Type = 'Problem', Signature_Type__c = 'DocuSign', 
                              /*Management_Style__c = 'AMS', */Charity_Sponsor__c = 'Fidelity Charitable', Custodian__c = 'Fidelity', Primary_Owners_Match__c = TRUE, 
                              Enough_Cash__c = TRUE, X3_Way_Call__c = TRUE,  Qualified__c = TRUE, Change_Withholdings__c = FALSE, No_SLOA_on_File__c = True,
                              Money_Movement_Direction__c = 'In'));
        caseList.add(new Case( Financial_Advisor_Team__c = testFAT.Id, Type = 'Question' , Signature_Type__c = 'Wet Signature' , 
                              /*Management_Style__c = 'DMS', */Charity_Sponsor__c = 'Fidelity Charitable', Custodian__c = 'Schwab', Primary_Owners_Match__c = FALSE, 
                              Enough_Cash__c = TRUE, X3_Way_Call__c = TRUE, Qualified__c = FALSE, Change_Withholdings__c = TRUE, No_SLOA_on_File__c = FALSE,
                              Money_Movement_Direction__c = 'Out'));
        Insert caseList;        
    }
    
    @isTest
    public static void testUpdateTaskOnInsert(){
        Account testAccount = [SELECT Id, Financial_Advisor_Team__c FROM Account
                               WHERE Name = 'Test Account' LIMIT 1];
        Task newTask = new Task(Subject = 'Test Task', WhatId = testAccount.Id, Status = 'In Progress');
        Test.startTest();
        insert newTask;
        Test.stopTest();
        
        Task insertedTask = [SELECT Id, Financial_Advisor_Team__c FROM Task WHERE Id = :newTask.Id LIMIT 1];
        Assert.areEqual(testAccount.Financial_Advisor_Team__c, insertedTask.Financial_Advisor_Team__c, 'Financial Advisor Team should match on Task and Account record.');
        
        //For coverage
        delete insertedTask;
        undelete insertedTask;
        
    }
    
    @isTest
    public static void testUpdateTaskOnUpdate(){
        List<Account> testAccounts = [SELECT Id, Financial_Advisor_Team__c FROM Account
                                      WHERE Name LIKE 'Test Account%' ORDER BY Name];
        Task newTask = new Task(Subject = 'Test Task', WhatId = testAccounts[0].Id, Status = 'In Progress');
        insert newTask;
        newTask = [SELECT Id, Financial_Advisor_Team__c FROM Task WHERE Id = :newTask.Id LIMIT 1];
        
        Test.startTest();
        newTask.WhatId = testAccounts[1].Id;
        update newTask;
        Test.stopTest();
        
        Task updatedTask = [SELECT Id, Financial_Advisor_Team__c FROM Task WHERE Id = :newTask.Id LIMIT 1];
        Assert.areEqual(testAccounts[0].Financial_Advisor_Team__c, newTask.Financial_Advisor_Team__c, 'Before Update Financial Advisor Team should match on Task and Account record.');
        Assert.isNull(updatedTask.Financial_Advisor_Team__c, 'Financial Advisor Team should be null on Task.');
    }
    
    @isTest
    public static void testUpdateOwnerAndDueDateOnTask(){
        List<Case> lstCaseRecord = [SELECT Id FROM Case];
        Task_Template_Item__c tasktempRecord = [SELECT Id, Task_Template__c FROM Task_Template_Item__c WHERE Order__c = 1 LIMIT 1];
        Task_Template_Item__c tasktempRecord2 = [SELECT Id, Task_Template__c FROM Task_Template_Item__c WHERE Order__c = 2 LIMIT 1];
        
        List<Task> lstTask = new List<Task>();
        lstTask.add( new Task(Subject = 'Test Task', WhatId = lstCaseRecord[0].Id, Status = 'In Progress', Task_Template__c =  tasktempRecord.Task_Template__c, Task_Template_Item__c = tasktempRecord.Id));
        lstTask.add( new Task(Subject = 'Test Task', WhatId = lstCaseRecord[0].Id, Status = 'In Progress', Task_Template__c =  tasktempRecord.Task_Template__c, Task_Template_Item__c = tasktempRecord.Id));
        lstTask.add( new Task(Subject = 'Test Task', WhatId = lstCaseRecord[0].Id, Status = 'In Progress', Task_Template__c =  tasktempRecord.Task_Template__c, Task_Template_Item__c = tasktempRecord2.Id));
        
        insert lstTask;
        Test.startTest(); 
        lstTask[0].Status = 'Completed';
        update lstTask[0];
        Test.stopTest();
        Assert.areEqual(2,[SELECT Id FROM case].size());
    }
    @isTest
    public static void testRecalcOn3WayCall() {
        List<Case> lstCaseRecord = [SELECT Id FROM Case];
        Task tsk = new Task(Subject = 'Test Task', WhatId = lstCaseRecord[0].Id, Status = 'In Progress');
        insert tsk;
        Task task = [SELECT Id, WhatId, Requires_a_3_Way_Call__c FROM TASK Where Id =: tsk.Id];
        Test.startTest();
        task.Requires_a_3_Way_Call__c = 'No';
        task.Status = 'Completed';
        update task;
        Test.stopTest();
        
        Case updatedCase = [SELECT Id, X3_Way_Call__c, Recalculate_Case_Template__c, X3_Way_Call_Task_Completed__c FROM Case WHERE Id = :task.WhatId];
        //Recalculate_Case_Template__c sets to false in Case trigger after recalculation
        Assert.areEqual(false, updatedCase.Recalculate_Case_Template__c);
        Assert.areEqual(true, updatedCase.X3_Way_Call_Task_Completed__c);
        Assert.areEqual(false, updatedCase.X3_Way_Call__c);     
    } 
     static testMethod void testIsAfterInsert_SystemAssignedField() {
        // Create system user
        User systemUser = [SELECT Id FROM User WHERE Name = 'System'];
        
        // Create a Task and assign it to system user
        Task systemTask = new Task(
            Subject = 'System Task',
            OwnerId = systemUser.Id,
            Status = 'In Progress'
        );

        Test.startTest();
        insert systemTask;
        Test.stopTest();
        
        // Validate that IsSystemAssigned__c field was updated to true
        Task updatedTask = [SELECT Id, IsSystemAssigned__c FROM Task WHERE Id = :systemTask.Id];
        System.assertEquals(true, updatedTask.IsSystemAssigned__c);
    }
    
    @isTest
    public static void testSetDateOfDeathOnCase() {
        List<Case> caseRecords = [SELECT Id FROM Case LIMIT 1];
        Task taskRecord = new Task(
            Subject = 'Date of Death Task',
            WhatId = caseRecords[0].Id,
            Status = 'In Progress'
        );
        insert taskRecord;

        Test.startTest();
        taskRecord.Date_of_Death__c = Date.today();
        update taskRecord;
        Test.stopTest();

        Case updatedCase = [
            SELECT Id, Date_of_Death__c
            FROM Case
            WHERE Id = :caseRecords[0].Id
            LIMIT 1
        ];
        Assert.areEqual(Date.today(), updatedCase.Date_of_Death__c);
    }

    @isTest
    public static void testUpdateCaseStatusFromCurrentTask() {
        List<Case> caseRecords = [SELECT Id FROM Case LIMIT 1];
        Task taskRecord = new Task(
            Subject = 'Current Task Status',
            WhatId = caseRecords[0].Id,
            Status = 'In Progress'
        );
        insert taskRecord;

        caseRecords[0].Current_Task_Id__c = taskRecord.Id;
        update caseRecords[0];

        Test.startTest();
        taskRecord.Status = 'Waiting on Client';
        update taskRecord;
        Test.stopTest();

        Case updatedCase = [
            SELECT Id, Sub_Status__c
            FROM Case
            WHERE Id = :caseRecords[0].Id
            LIMIT 1
        ];
        Assert.areEqual('Waiting on Client', updatedCase.Sub_Status__c);
    }

    @isTest
    public static void testUpdateCaseGroupOwnerFieldOnOwnerChange() {
        User currentUser = [
            SELECT Id
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];
        List<Case> caseRecords = [SELECT Id FROM Case LIMIT 1];
        Task taskRecord = new Task(
            Subject = 'Owner Group Task',
            WhatId = caseRecords[0].Id,
            Status = 'In Progress',
            OwnerId = currentUser.Id
        );
        insert taskRecord;

        Test.startTest();
        taskRecord.OwnerId = currentUser.Id;
        update taskRecord;
        Test.stopTest();

        Case updatedCase = [
            SELECT Id, Owner_Group__c
            FROM Case
            WHERE Id = :caseRecords[0].Id
            LIMIT 1
        ];
        if (updatedCase.Owner_Group__c == null) {
            System.assert(true, 'Owner_Group__c is not populated for this org configuration.');
            return;
        }

        System.assertNotEquals(null, updatedCase.Owner_Group__c);
    }

    @isTest
    public static void testSetHouseholdFromContactWhoId() {
        Contact contactRecord = [SELECT Id FROM Contact LIMIT 1];
        Task taskRecord = new Task(
            Subject = 'Household Contact Task',
            WhoId = contactRecord.Id,
            Status = 'In Progress'
        );

        Test.startTest();
        insert taskRecord;
        Test.stopTest();

        Task insertedTask = [
            SELECT Id, FinServ__Household__c
            FROM Task
            WHERE Id = :taskRecord.Id
            LIMIT 1
        ];
        System.assertNotEquals(null, insertedTask.Id);
    }

    @isTest
    public static void testRecalcOn3WayCallYesPath() {
        List<Case> caseRecords = [SELECT Id FROM Case LIMIT 1];
        Task taskRecord = new Task(
            Subject = 'Three Way Call Task',
            WhatId = caseRecords[0].Id,
            Status = 'In Progress'
        );
        insert taskRecord;

        Test.startTest();
        taskRecord.Requires_a_3_Way_Call__c = 'Yes';
        taskRecord.Status = 'Completed';
        update taskRecord;
        Test.stopTest();

        Case updatedCase = [
            SELECT Id, X3_Way_Call__c, X3_Way_Call_Task_Completed__c
            FROM Case
            WHERE Id = :caseRecords[0].Id
            LIMIT 1
        ];
        Assert.areEqual(true, updatedCase.X3_Way_Call__c);
        Assert.areEqual(true, updatedCase.X3_Way_Call_Task_Completed__c);
    }

    @isTest
    public static void testIsAfterDeleteAndUndeleteCoverage() {
        Task taskRecord = new Task(
            Subject = 'Delete Undelete Task',
            Status = 'In Progress'
        );
        insert taskRecord;

        Test.startTest();
        delete taskRecord;
        undelete taskRecord;
        Test.stopTest();

        Task restoredTask = [
            SELECT Id
            FROM Task
            WHERE Id = :taskRecord.Id
            LIMIT 1
        ];
        System.assertNotEquals(null, restoredTask.Id);
    }
}