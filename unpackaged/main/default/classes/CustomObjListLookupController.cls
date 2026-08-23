public class CustomObjListLookupController {
    @AuraEnabled
    public static SObject getSelectedRecordDetails(String recordId){
        String sObjName = Id.valueOf(recordId).getSObjectType().getDescribe().getName();

        String query = 'SELECT Id, Name FROM '+sObjName+' WHERE Id = \''+recordId+'\'';
        List<SObject> rec = Database.query(query);
        return rec[0];
    }
    
     @AuraEnabled
    public static List<SObJectResult> getResults(String objectName, String fieldName, String value, String conditionFieldName, String conditionFieldValue,String filter) {
        List<SObJectResult> sObjectResultList = new List<SObJectResult>();
        String query = 'SELECT Id, '+fieldName+' FROM '+objectName+' WHERE '+fieldName+' LIKE \'%' + value + '%\'';
        if(conditionFieldName != null && conditionFieldValue != null){
            query = query + ' AND '+conditionFieldName+' = \''+conditionFieldValue+ '\'';
        }  
        if(!String.isEmpty(filter)){
         query = query + ' AND '+ filter;

        }
        System.debug(query);
        for(sObject so : Database.Query(query)) {
            String fieldvalue = (String)so.get(fieldName);
            sObjectResultList.add(new SObjectResult(fieldvalue, so.Id));
        }
        
        return sObjectResultList;
    }
    
    @AuraEnabled
    public static String getParentObjectName(String childObjectName,String parentFieldName){
        System.debug('childObjectName: ' + childObjectName);
        System.debug('parentFieldName: ' + parentFieldName);
        String parentObjectAPIName = parentFieldName;
        if(childObjectName != parentFieldName){
            Schema.DescribeFieldResult f = Schema.getGlobalDescribe().get(childObjectName).getDescribe().fields.getMap().get(parentFieldName).getDescribe();
            for(Schema.SObjectType reference:f.getReferenceTo()){
                parentObjectAPIName=reference.getDescribe().getName();
            }
        }
        
        return parentObjectAPIName;
    }
    
	@AuraEnabled
    public static String getIconName(String sObjectName){
        String u;
        List<Schema.DescribeTabSetResult> tabSetDesc = Schema.describeTabs();
        List<Schema.DescribeTabResult> tabDesc = new List<Schema.DescribeTabResult>();
        List<Schema.DescribeIconResult> iconDesc = new List<Schema.DescribeIconResult>();

        for(Schema.DescribeTabSetResult tsr : tabSetDesc) { tabDesc.addAll(tsr.getTabs()); }

        for(Schema.DescribeTabResult tr : tabDesc) {
            if( sObjectName == tr.getSobjectName() ) {
                if( tr.isCustom() == true ) {
                    iconDesc.addAll(tr.getIcons());
                } else {
                    u = 'standard:' + sObjectName.toLowerCase();
                }
            }
        }
        for (Schema.DescribeIconResult ir : iconDesc) {
            if (ir.getContentType() == 'image/svg+xml'){
                u = 'custom:' + ir.getUrl().substringBetween('custom/','.svg').substringBefore('_');
                break;
            }
        }
        return u;
    }
    
    public class SObJectResult {
        @AuraEnabled
        public String recName;
        @AuraEnabled
        public Id recId;
        
        public SObJectResult(String recNameTemp, Id recIdTemp) {
            recName = recNameTemp;
            recId = recIdTemp;
        }
    }
}