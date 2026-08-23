public class FlowSelectableCard_Controller {
    
    @AuraEnabled
    public static List<SObject> getRecordsInfo(String objectName, List<String> recordIds, String fields,string recordFilter){
        System.debug('recordIds: ' + recordIds);
                        System.debug('recordFilter: ' + recordFilter);

        String query ='Select ' + fields + ' FROM ' + objectName + ' WHERE Id IN: recordIds';
        if(!string.isEmpty(recordFilter) ){
            query ='Select ' + fields + ' FROM ' + objectName + ' WHERE ' + recordFilter;
        }
        System.debug(query);
        List<SObject> lstObject = Database.query(query);
        System.debug(lstObject);
        System.debug(lstObject[0]);
        return lstObject;
    }
    
    @AuraEnabled
    public static List<SObject> getRecordInfo(String objectName, String recordId, String fields,string recordFilter){
        System.debug('recordId: ' + recordId);
                System.debug('recordFilter: ' + recordFilter);

        String query ='Select ' + fields + ' FROM ' + objectName + ' WHERE Id =: recordId';
        if(!string.isEmpty(recordFilter) ){
            query ='Select ' + fields + ' FROM ' + objectName + ' WHERE ' + recordFilter;
        }        System.debug(query);
        List<SObject> lstObject = Database.query(query);
        System.debug(lstObject);
        System.debug(lstObject[0]);
        return lstObject;
    }
}