public class ConcentrationTableHelper {

    @AuraEnabled
    public static Case getCaseValues(String recordId){
        Case caseToReturn = [SELECT Id, SREP_Total_including_Today__c, PE_Total_including_Today__c, 
                             PC_Total_including_Today__c, IF_Total_including_Today__c, EP_Total_including_Today__c, 
                             SN_Total_including_Today__c, SREP_Total_as_of_Net_Worth__c, PE_Total_as_of_Net_Worth__c, 
                             PC_Total_as_of_Net_Worth__c, IF_Total_as_of_Net_Worth__c, EP_Total_as_of_Net_Worth__c, 
                             SN_Total_as_of_Net_Worth__c, ASAA_as_a_of_Net_Worth__c FROM Case WHERE Id =: recordId];
        System.debug(caseToReturn);
        return caseToReturn;
    }
}