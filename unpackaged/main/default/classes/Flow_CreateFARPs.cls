global class Flow_CreateFARPs {

    @InvocableMethod(label='Flow_CreateFARPS' description='Pass in a Collection of Strings that are Product Ids and a collection of wizard fin accts and it will create a FARP for each fin acct.')
    global static List<FlowOutput> createFARPs(List<FlowInput> inputs){
		List<Financial_Account__c> wizFins = inputs[0].finAccts;
        List<String> productIds = inputs[0].productIds;
        List<String> farpIdsFromInsert = new List<String>();
        List<Financial_Account_Related_Product__c> farps = new List<Financial_Account_Related_Product__c>();
        Integer i;
        for(i=0;i<wizFins.size();i++){
            Financial_Account_Related_Product__c farp = new Financial_Account_Related_Product__c();
            farp.Financial_Account__c = wizFins[i].Id;
            farp.Product__c = productIds[i];
            farp.Flow_Interview_Id__c = inputs[0].interviewId;
            farps.add(farp);
        }
        insert farps;
        List<Financial_Account_Related_Product__c> farpList = [SELECT Id FROM Financial_Account_Related_Product__c WHERE Flow_Interview_Id__c =: inputs[0].interviewId];
        System.debug('farps: ' + farps);
        System.debug('farpList: ' + farpList);
        List <FlowOutput> outputs = new List<FlowOutput>();
        FlowOutput objOutput = new FlowOutput();
        objOutput.count = farps.size();
        for(Financial_Account_Related_Product__c f : farps){
            farpIdsFromInsert.add(f.Id);
        }
        objOutput.farpIds = farpIdsFromInsert;
        outputs.add(objOutput);
        return outputs;
    }
    
    global class FlowInput {
        
        @InvocableVariable
        global List<Financial_Account__c> finAccts;
        
        @InvocableVariable
        global List<String> productIds;
             
        @InvocableVariable
        global String interviewId;
    }
    
    global class FlowOutput {
        
        @InvocableVariable
        global Integer count;
        
        @InvocableVariable
        global List<String> farpIds;
        
    }
}