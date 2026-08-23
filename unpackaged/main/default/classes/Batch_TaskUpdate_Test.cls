@istest
public class Batch_TaskUpdate_Test {
	@testSetup
    private static void testSetup(){
        List<Case> caseList=new List<Case>();
        Id accOpenRT = Schema.SObjectType.Case.getRecordTypeInfosByName().get('Account Opening').getRecordTypeId();
    	Id accServRT = Schema.SObjectType.Case.getRecordTypeInfosByName().get('Account Servicing').getRecordTypeId();
        Date todaysDate = Date.today();
        List<Task_Template_Item__c> ttiList = new List<Task_Template_Item__c>();
        List<Task> tasklist = new List<Task>();
        
        Case case1 = new Case(Subject = 'Account Opening', RecordTypeId = accOpenRT);
        Case case2 = new Case(Subject = 'Account Servicing', RecordTypeId = accServRT);
        caseList.add(case1);
        caseList.add(case2);
        insert caseList;
        
        Case_Template__c ct = new Case_Template__c(Name = 'Case Template');
        insert ct;
        Task_Template__c tt = new Task_Template__c(Name = 'Task Template');
        insert tt;
        
        for(Integer i=0;i<2;i++){
            Task_Template_Item__c tti = new Task_Template_Item__c();
            tti.Case_Template__c = ct.Id;
            tti.Task_Template__c  = tt.Id;
            tti.Order__c = i;
            ttiList.add(tti);
        }
        insert ttiList;
        
        for(Integer i=0;i<1;i++){
            Task t = new Task();
            t.Task_Template_Item__c = ttiList[i].Id;
            t.WhatId = case1.Id;
            t.ActivityDate = todaysDate;
            t.OwnerId = UserInfo.getUserId();
            t.Status = 'New';
            taskList.add(t);
        }
        for(Integer i=0;i<2;i++){
            Task t = new Task();
            t.Task_Template_Item__c = ttiList[i].Id;
            t.WhatId = case2.Id;
            t.ActivityDate = todaysDate;
            t.OwnerId = UserInfo.getUserId();
            t.Status = 'New';
            taskList.add(t);
        }
        insert taskList;
    }
    
    @istest
    private static void Batch_TaskUpdateTest(){
        Date todaysDate = Date.today();
        test.startTest();
        Database.executeBatch(new Batch_TaskUpdate());
        test.stopTest();
        List<Case> cases = [SELECT Id, Date_Task_Script_Last_Ran__c, Current_Task_Id__c, Number_of_Open_Tasks__c, 
                            Due_Date_of_Current_Task__c FROM Case];
        Assert.areEqual(todaysDate, cases[1].Date_Task_Script_Last_Ran__c);
        Assert.areEqual(todaysDate, cases[1].Due_Date_of_Current_Task__c);
        Assert.areEqual(2, cases[1].Number_of_Open_Tasks__c);
        Assert.isNotNull(cases[1].Current_Task_Id__c);
        
    }
}