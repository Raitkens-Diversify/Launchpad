@IsTest
public class ConcentrationTableHelperTest {
    @IsTest
    private static void getCaseValues_Test(){ 
        Test.startTest();
        Case caseRecord =  new case(SREP_Total_including_Today__c = 0 , PE_Total_including_Today__c= 0, 
                                    PC_Total_including_Today__c= 0, IF_Total_including_Today__c= 0, EP_Total_including_Today__c= 0, 
                                    SN_Total_including_Today__c= 0, SREP_Total_as_of_Net_Worth__c= 0, PE_Total_as_of_Net_Worth__c= 0, 
                                    PC_Total_as_of_Net_Worth__c= 0, IF_Total_as_of_Net_Worth__c= 0, EP_Total_as_of_Net_Worth__c= 0, 
                                    SN_Total_as_of_Net_Worth__c= 0, ASAA_as_a_of_Net_Worth__c= 0);              
        insert caseRecord;    
        Case caseInserted =  ConcentrationTableHelper.getCaseValues(caseRecord.Id);
        Test.stopTest();
        Assert.areNotEqual(null, caseInserted,'Case list should be have one record');
        
    }
    
}