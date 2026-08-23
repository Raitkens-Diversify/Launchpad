public class TypeHeadLookupController {
    
    @AuraEnabled
    public static List<String> getselectOptions(sObject objObject, string fld) {
        List<String> allOpts = new List<String> ();
        
        Schema.sObjectType objType = objObject.getSObjectType();
        Schema.DescribeSObjectResult objDescribe = objType.getDescribe();
        Map<String, Schema.SObjectField> fieldMap = objDescribe.fields.getMap();
        List<Schema.PicklistEntry> values = fieldMap.get(fld).getDescribe().getPickListValues();

        for (Schema.PicklistEntry a: values) {
            allOpts.add(a.getValue());
        }
        return allOpts;
    }

}