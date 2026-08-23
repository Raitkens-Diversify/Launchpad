global class ReCalculateSharingBatch implements Database.Batchable<sObject>,Database.Stateful {
    
    global Database.QueryLocator start(Database.BatchableContext bc) {
                //NOTE : For QA Testing Use This one(Use Same Id In ResetFATBatch And ReCalculateSharingBatch )
        //return Database.getQueryLocator('SELECT Id, OASP_FSC__Orion_Rep_ID__c, Financial_Advisor_Team__c,Financial_Advisor_Team__r.Public_Group_Id__c FROM FinServ__FinancialAccount__c WHERE Id = \'a0874000000u2MuAAI\'');
        return Database.getQueryLocator('SELECT Id, OASP_FSC__Orion_Rep_ID__c, Financial_Advisor_Team__c,Financial_Advisor_Team__r.Public_Group_Id__c FROM FinServ__FinancialAccount__c WHERE Financial_Advisor_Team__c != null');
    }
    
    global void execute(Database.BatchableContext bc, List<FinServ__FinancialAccount__c> scope) {
        Set<Id> groupIdSet = new Set<Id>();
        Set<Id> parentIdSet = new Set<Id>();
        Set<String> keySet = new Set<String>();
        for(FinServ__FinancialAccount__c record : scope){
            if(record.Financial_Advisor_Team__c != null){
                groupIdSet.add(record.Financial_Advisor_Team__r.Public_Group_Id__c);
                parentIdSet.add(record.Id);
            } 
        }
        
        if(groupIdSet.size() > 0 && parentIdSet.size() > 0){
            List<FinServ__FinancialAccount__Share> removeShareList = new List<FinServ__FinancialAccount__Share>();
            for(FinServ__FinancialAccount__Share shareRec: [SELECT id, ParentId, UserOrGroupId FROM FinServ__FinancialAccount__Share WHERE ParentId IN: parentIdSet and UserOrGroupId IN: groupIdSet]){
                if(groupIdSet.Contains(shareRec.UserOrGroupId) && parentIdSet.contains(shareRec.ParentId))
                {
                    keySet.add(shareRec.UserOrGroupId +':'+ shareRec.ParentId);
                }
            }
        }
        
        
        List<FinServ__FinancialAccount__Share> shareRecordList = new List<FinServ__FinancialAccount__Share>();                
        for(FinServ__FinancialAccount__c record : scope){
            FinServ__FinancialAccount__Share shareRec = new FinServ__FinancialAccount__Share();
            if(record.Financial_Advisor_Team__c != null){
                shareRec.ParentId = record.Id;
                shareRec.UserOrGroupId = record.Financial_Advisor_Team__r.Public_Group_Id__c;                        
                shareRec.AccessLevel = 'Edit';
                shareRec.RowCause = Schema.FinServ__FinancialAccount__Share.RowCause.Manual;
                if(!keySet.contains(record.Financial_Advisor_Team__r.Public_Group_Id__c +':'+ record.Id)){
                    shareRecordList.add(shareRec);
                } 
                
            }            
        }                
        if(shareRecordList.size() > 0){
            Database.insert(shareRecordList,false);
        }
    }
    
    global void finish(Database.BatchableContext bc) {
        
    }
    
}