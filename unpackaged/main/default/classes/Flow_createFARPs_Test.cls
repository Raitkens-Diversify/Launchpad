@istest
public class Flow_createFARPs_Test {
	/*@istest
    static void createFARPstest(){
        Flow_CreateFARPs.FlowInput flowInput=new Flow_CreateFARPs.FlowInput();
        List<Flow_CreateFARPs.FlowInput> flowInputList=new List<Flow_CreateFARPs.FlowInput>();
        List<Flow_CreateFARPs.FlowOutput> flowOutputList=new List<Flow_CreateFARPs.FlowOutput>();
        
        List<Wizard_Financial_Account__c> inputs=new List<Wizard_Financial_Account__c>();
        List<String> prodIds = new List<String>();
        Wizard_Financial_Account__c wizFin = new Wizard_Financial_Account__c();
        insert wizFin;
        inputs.add(wizFin);
        flowInput.finAccts=inputs;
        Product__c prod = new Product__c();
        insert prod;
        prodIds.add(prod.Id);
        flowInput.productIds=prodIds;
        flowInput.interviewId = 'test';
  		flowInputList.add(flowInput);       
        test.startTest();
        flowOutputList=Flow_CreateFARPs.createFARPs(flowInputList);
        test.stopTest();
       // boolean b=flowOutputList[0].collRemoved.contains('One');
        system.assertEquals(flowOutputList[0].count == 1, true);
        List<Financial_Account_Related_Product__c> farps = [SELECT Id FROM Financial_Account_Related_Product__c];
        delete farps;
        
    }*/
    
}