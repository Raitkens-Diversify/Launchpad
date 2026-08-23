public class FileUploadController {
	
    @AuraEnabled 
    public static void updateCVs(List<String> cvIds, String adType, String interviewId){
        List<ContentVersion> cvListToUpdate = new List<ContentVersion>();
        if(adType == null && interviewId == null){
            return;
        }
        for(String cvId : cvIds){
            ContentVersion cv = new ContentVersion(Id = cvId);
            cv.Advertising_Type__c = adType;
            cv.Flow_Interview_ID__c = interviewId;
            cvListToUpdate.add(cv);
        }
        
        if(!cvListToUpdate.isEmpty()){
            update cvListToUpdate;
        }
    }
    
    @AuraEnabled 
    public static void updateCVsNonAdReview(List<String> cvIds, String interviewId){
        List<ContentVersion> cvListToUpdate = new List<ContentVersion>();
        
        for(String cvId : cvIds){
            ContentVersion cv = new ContentVersion(Id = cvId);
            cv.Flow_Interview_ID__c = interviewId;
            cvListToUpdate.add(cv);
        }
        
        if(!cvListToUpdate.isEmpty()){
            update cvListToUpdate;
        }
    }
    
	@AuraEnabled    
    public static List<String> getCVAdvertisingTypeOpts(){
       List<String> pickListValuesList= new List<String>();
		Schema.DescribeFieldResult fieldResult = ContentVersion.Advertising_Type__c.getDescribe();
		List<Schema.PicklistEntry> ple = fieldResult.getPicklistValues();
		for( Schema.PicklistEntry pickListVal : ple){
			pickListValuesList.add(pickListVal.getLabel());
            System.debug('picklist: ' + pickListVal.getLabel());
		}
        System.debug('picklist: ' + pickListValuesList);
		return pickListValuesList;
    }
}