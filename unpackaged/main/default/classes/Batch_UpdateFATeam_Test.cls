@istest
public class Batch_UpdateFATeam_Test {
	@testSetup
    private static void testSetup(){
        List<Account> accList=new List<Account>();
        
        List<Financial_Advisor_Team__c> fatTeam=new List<Financial_Advisor_Team__c>();
        List<Rep_Code__c> repCodeList=new List<Rep_Code__c>();
        List<FinServ__FinancialAccount__c> finAccountList=new List<FinServ__FinancialAccount__c>();
       	Id recTypeId=Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('IndustriesIndividual').getRecordTypeId();
        
        Account acc=new Account(Name='Primary Owner',RecordTypeId=recTypeId, Type = 'Other');
        Account acct=new Account(Name='Joint Owner',RecordTypeId=recTypeId, Type = 'Other');
        accList.add(acc);
        accList.add(acct);
        insert accList;
        for(Integer i=0;i<5;i++){
            Financial_Advisor_Team__c fat=new Financial_Advisor_Team__c();
            fat.Name='Test'+i;
            fat.Orion_ID__c=i;
            fatTeam.add(fat);
        }
         //Make a default team 
                    Financial_Advisor_Team__c fat = new Financial_Advisor_Team__c(Name='Default Team');
        fatTeam.add(fat);
        insert fatTeam;
        
        for(Integer i=0;i<fatTeam.size();i++){
            Rep_Code__c repCode=new Rep_Code__c();
            repCode.Name='TestRepCode'+i;
            //repCode.Interface_Type__c='0';
            //repCode.va_Code__C=String.valueOf(i);
            repCode.Financial_Advisor_Team__c=fatTeam[i].Id;
            repCodeList.add(repCode);
        }
        insert repCodeList;
        for(Integer i=0;i<repCodeList.size();i++){
            FinServ__FinancialAccount__c finAcct=new FinServ__FinancialAccount__c();
            finAcct.Name='FINAccount'+i;
            finAcct.Rep_Code__c='TestRepCode'+i;
            //finAcct.Interface_Type__c='0';
            //finAcct.VA_Code__c=String.valueOf(i);
            finAcct.FinServ__PrimaryOwner__c=acc.Id;
            finAcct.FinServ__JointOwner__c=acct.Id;
            finAccountList.add(finAcct);
        }
       
        insert finAccountList;
    }
    @istest
    private static void tBatch_UpdatefatTeamtest(){
        set<Id> repIds=new set<Id>();
        Rep_Code__c reptest=[select Id,Financial_Advisor_Team__c from Rep_Code__c limit 1];
        FinServ__FinancialAccount__c finAccount=[select Id from FinServ__FinancialAccount__c Limit 1];
        for(Rep_Code__c rep:[select Id from Rep_Code__c]){
            repIds.add(rep.Id);
        }
        test.startTest();
        Database.executeBatch(new Batch_UpdateFATeam(repIds));
        test.stopTest();
        //system.assertEquals(reptest.Id,[select Id,Rep_Code_Lookup__c from FinServ__FinancialAccount__c where Id=:finAccount.Id][0].Rep_Code_Lookup__c);
        //system.assertEquals(reptest.Financial_Advisor_Team__c,[select Id,Financial_Advisor_Team__c from FinServ__FinancialAccount__c where Id=:finAccount.Id][0].Financial_Advisor_Team__c);
    }
}