@isTest
public class Batch_FindUnAssignedTasksTest {
    @testSetup
    private static void setup(){
        
        List<Case_Template__c> caseTempList = new List<Case_Template__c>();
        caseTempList.add(new Case_Template__c(Name = 'Problem' , Previous_Management_Style__c = 'EXCLUDED',
                                              Management_Style__c = 'EXCLUDED',
                                              Charity_Sponsor__c = 'EXCLUDED', Custodian__c = 'EXCLUDED',
                                              Enough_Cash__c = 'EXCLUDED', Live_SLOA_on_File__c = 'EXCLUDED',
                                              Money_Movement_Direction__c = 'EXCLUDED', Compliance_Needed__c = 'EXCLUDED',
                                              Check_in_Hand__c = 'EXCLUDED'));
        
        Insert caseTempList;
        
        List<Task_Template__c> taskTempList = new List<Task_Template__c>();
        taskTempList.add(new Task_Template__c(Assigned_To__c = 'Queue' , FA_Team_Permission__c = 'Trading', Queue__c = 'Back Office Operations',
                                              Priority__c = 'High', Due_Date__c = 'Days from Case Creation', Number_of_Days__c = 6 ));
        taskTempList.add(new Task_Template__c(Assigned_To__c = '' , FA_Team_Permission__c = 'Draft Paperwork', Queue__c = 'Compliance ',
                                              Priority__c = 'Low', Due_Date__c = 'Days from Case Creation', Number_of_Days__c = 2 ));
        Insert taskTempList;      
        
        List<Task_Template_Item__c> taskTempItemList = new List<Task_Template_Item__c>();
        taskTempItemList.add(new Task_Template_Item__c(Case_Template__c = caseTempList[0].Id ,Task_Template__c = taskTempList[0].Id, Order__c = 1));
        taskTempItemList.add(new Task_Template_Item__c(Case_Template__c = caseTempList[0].Id ,Task_Template__c = taskTempList[1].Id, Order__c = 2));
        
        Insert taskTempItemList; 
        Id accOpeningRecTypeId = Schema.sObjectType.Case.getRecordTypeInfosByName().get('Account Opening').getRecordTypeId(); 
        
        List<Case> caseList = new List<Case>();
        caseList.add(new Case(Origin= 'Service Request',RecordTypeId = accOpeningRecTypeId, Status = 'New', Type = 'Problem', Signature_Type__c = 'DocuSign', 
                              Management_Style__c = 'AMS', Charity_Sponsor__c = 'Schwab Charitable', Custodian__c = 'Fidelity', Primary_Owners_Match__c = TRUE,
                              Enough_Cash__c = TRUE, X3_Way_Call__c = TRUE, Qualified__c = FALSE, Change_Withholdings__c = FALSE, No_SLOA_on_File__c = FALSE,
                              Money_Movement_Direction__c = 'Out'));    
        Insert caseList;     
    }
    
    @isTest
    static void testBatchExecution() {
        // Create instance of the Batch_FindUnAssignedTasks class
        Batch_FindUnAssignedTasks batchInstance = new Batch_FindUnAssignedTasks();
        Group result = [select id from group where name='UnAssigned' AND Type = 'Queue'];
        
        // Test that no unassigned tasks have IsSystemAssigned__c set to true before the batch
        Task[] tasksBeforeBatch = [SELECT Id, IsSystemAssigned__c,Owner.Name,ownerId FROM Task WHERE isclosed = false AND OwnerId != :result.Id];
        
        tasksBeforeBatch[0].status ='Completed';
        update tasksBeforeBatch[0];
        
        System.assertEquals(false, tasksBeforeBatch[0].IsSystemAssigned__c);
        
        // Start the batch execution
        Test.startTest();
        Database.executeBatch(batchInstance);
        Test.stopTest();
        
        // Validate the Task after the batch has run
        Task[] tasksAfterBatch = [SELECT Id, IsSystemAssigned__c FROM Task WHERE OwnerId = :result.Id];
        System.assertEquals(true, tasksAfterBatch[0].IsSystemAssigned__c, 'Task should have IsSystemAssigned__c set to TRUE.');
    }    
}