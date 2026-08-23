global class Batch_UpdateFATeam implements Database.Batchable<sObject> {
    public Map<String,Rep_Code__c> repCodeMapVar;
    public Set<Id> repCodeIds;
    public Set<String> repCodesSetVar;
    public Set<String> intTypesVar;
    global Batch_UpdateFATeam(Set<Id> repIds)
    {
        System.debug('repIds=='+repIds);
        repCodeIds = repIds;
        List<Rep_Code__c> repCodes = [Select Id,Name,Financial_Advisor_Team__c from Rep_Code__c where Id in:repCodeIds];
        Map<String,Rep_Code__c> repCodeMap = new Map<String,Rep_Code__c>();
        Set<String> repCodesSet = new Set<String>();
        Set<String> intTypes = new Set<String>();
        for(Rep_Code__c r:repCodes)
        {
            //repCodesSet.add(r.Name);
            //intTypes.add(r.Interface_Type__c);
            //repCodeMap.put(r.Code_Interface_Id__c,r);
        }
        repCodeMapVar = repCodeMap;
        repCodesSetVar =repCodesSet;
        intTypesVar = intTypes;
     
    }
    global Batch_UpdateFATeam()
    {
    }
    global Database.QueryLocator start(Database.BatchableContext BC) {
        System.debug('repCodeMapVar=='+repCodeMapVar);
        System.debug('repCodesSet=='+repCodesSetVar);
        System.debug('intTypes=='+intTypesVar);
        //return Database.getQueryLocator([SELECT Id, Rep_Code__c,Rep_Code_Lookup__c,Interface_Type__c,Code_Interface_Id__c FROM FinServ__FinancialAccount__c where Code_Interface_Id__c in:repCodeMapVar.keyset()]);  
        //return Database.getQueryLocator('SELECT Id, Rep_Code__c,Rep_Code_Lookup__c,Interface_Type__c,Code_Interface_Id__c FROM FinServ__FinancialAccount__c where Code_Interface_Id__c!=null AND Batch_Check__c = true and WrongTeamOrRepCode__c = true');  
        return Database.getQueryLocator([SELECT Id, Rep_Code__c,Rep_Code_Lookup__c FROM FinServ__FinancialAccount__c ]);  
		
  
    }
    
    global void execute(Database.BatchableContext BC, List<FinServ__FinancialAccount__c> scope){
       Set<String> codeInterfaceIds = new Set<String>();
        for(FinServ__FinancialAccount__c fa:scope)
        {
            //codeInterfaceIds.add(fa.Code_Interface_Id__c);
        }
        List<Rep_Code__c> repCodes = [Select Id,Name,Financial_Advisor_Team__c from Rep_Code__c];
        Map<String,Rep_Code__c> repCodeMap = new Map<String,Rep_Code__c>();
        for(Rep_Code__c r:repCodes)
        {
            //repCodesSet.add(r.Name);
            //intTypes.add(r.Interface_Type__c);
            //repCodeMap.put(r.Code_Interface_Id__c,r);
        }
        for(FinServ__FinancialAccount__c fa:scope)
        {
            /*if(repCodeMap.get(fa.Code_Interface_Id__c)!=null)
            {
                fa.Financial_Advisor_Team__c = repCodeMap.get(fa.Code_Interface_Id__c).Financial_Advisor_Team__c;
                fa.Rep_Code_Lookup__c = repCodeMap.get(fa.Code_Interface_Id__c).Id;
                
            }*/
            //fa.Batch_Check__c = false;
        }
        Database.update(scope,false); 
    }
    
    global void finish(Database.BatchableContext BC){  
        
    }
}