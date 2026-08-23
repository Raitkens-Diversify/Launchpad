public without sharing class FlowCreateMultipleController {
    
    @AuraEnabled
    public static List<FieldObj> getFieldAndDatatype(String sObjectName, List<String> sObjectFields, List<String> readOnlyFields){
        List<FieldObj> fieldObjValues = new List<FieldObj>();
        Map<String, String> mapAllSObjectFieldsWithDataTypes = new Map<String, String>();
        mapAllSObjectFieldsWithDataTypes =  getAllSObjectFieldsWithDataTypes(sObjectName);
        Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
        Schema.SObjectType objSchema = gd.get(sObjectName);
        Map<String, Schema.SObjectField> fieldMap = objSchema.getDescribe().fields.getMap();
        Schema.DescribeFieldResult dfr;
        Schema.SObjectField sof;
        for(String field : sObjectFields){
            if(mapAllSObjectFieldsWithDataTypes.containsKey(field) || field == 'Amount__c'){
                FieldObj fObj = new FieldObj();
                fObj.fieldName = field;
                fObj.label = fieldMap.get(field).getDescribe().getLabel();
                dfr=fieldMap.get(field).getDescribe();
                if(dfr.calculated){
                    system.debug(dfr.calculated);
                    fObj.formulaField = true; 
                }
                if(dfr.isUpdateable() && (readOnlyFields == null || readOnlyFields != null && !readOnlyFields.contains(field))){
                    fObj.isEditable = true;
                }
                fObj.dataType = mapAllSObjectFieldsWithDataTypes.get(field);
                System.debug('fObj.dataType: ' + fObj.dataType);
                if(fObj.dataType == 'PICKLIST'){
                    fObj.pickListOptions = getPicklistOptions(sObjectName ,field);
                }
                fieldObjValues.add(fObj); 
            }
        }
        return fieldObjValues;
    }
    
    public static Id getRecordTypeId(String objType, String recordTypeName)
    {
        Schema.DescribeSObjectResult objDescribe = Schema.getGlobalDescribe().get(objType).getDescribe();
        Map<String, Schema.RecordTypeInfo> rts = objDescribe.getRecordTypeInfosByName();
        
        return rts.containsKey(recordTypeName) ? rts.get(recordTypeName).getRecordTypeId() : null;
    }
    
    @AuraEnabled
    public static List<SObject> getExistingRecords(String parentRecordId, String objType, String parentLookup, List<String> fieldNames, String recordTypeName)
    {
        Id rtId;
        if(recordTypeName != null){
            rtId = getRecordTypeId(objType, recordTypeName);
        }
        
        String query = 'SELECT Id, ' + String.join(fieldNames, ',') + ' FROM ' + objType;
        query += rtId != null || (parentLookup != '' && parentRecordId != '') ? ' WHERE ' : '';
        query += rtId != null ? ' RecordTypeId = \'' + rtId + '\' AND ' : '';
        query += (parentLookup != '' && parentRecordId != '') ? parentLookup + ' = \'' + parentRecordId + '\'' : ''; 
        query += ' ORDER BY ' + fieldNames.get(0);
        System.debug(LoggingLevel.INFO, query);
        return database.query(query);
    }
    
    @AuraEnabled
    public static List<SObject> getExistingRecordsEvents(String interviewId, String objType, String parentLookup, List<String> fieldNames, String recordTypeName)
    {
        Id rtId;
        if(recordTypeName != null){
            rtId = getRecordTypeId(objType, recordTypeName);
        }
        
        String query = 'Select Id, ' + String.join(fieldNames, ',') + ' from ' + objType + ' WHERE ';
        query += rtId!=null ? 'RecordTypeId=\'' + rtId + '\' and ' : ''; 
        query += 'Flow_Interview_Id__c=\'' + interviewId + '\' ORDER BY ' + fieldNames.get(0);
        System.debug(LoggingLevel.INFO, query);
        return database.query(query);
    }
    
    @AuraEnabled
    public static Boolean deleteRecord(String parentRecordId, String objType, String parentLookup, String recordId)
    {
        try
        {
            String query = 'Select Id from ' + objType + ' where Id=\'' + recordId + '\' and ' + parentLookup + '=\'' + parentRecordId + '\' limit 1';
            system.debug(LoggingLevel.INFO, query);
            List<SObject> toDelete = database.query(query);
            if(toDelete.size()>0)
            {
                delete toDelete;
            }
            
            return true;
        }
        catch(Exception e)
        {
            System.debug(LoggingLevel.ERROR, 'Error Deleting: ' + e);
        }
        
        return false;
    }
    
    @AuraEnabled
    public static SObject upsertRecord(String objType, Map<String, String> recordValues, String recordTypeName)
    {
        Schema.SObjectType targetType = Schema.getGlobalDescribe().get( objType );
        if ( targetType == null ) {
            // throw an exception
            return null;
        }
        system.debug(recordValues);
        Id rtId = getRecordTypeId(objType, recordTypeName);
        
        Schema.DescribeSObjectResult objDescribe;
        List<Schema.SObjectField> tempFields;
        Set<String> outputFields = new Set<String>();
        
        Map<String, String> fieldMappings = new Map<String, String>();
        Set<String> fieldNamesNotEditable = new Set<String>();
        fieldMappings.put('Id', 'String');
        
        objDescribe = targetType.getDescribe();
        Map<String, Schema.SObjectField> fieldMap = objDescribe.fields.getMap();
        tempFields = fieldMap.values();
        Schema.DescribeFieldResult dfr;
        for(Schema.SObjectField sof : tempFields)
        {
            dfr = sof.getDescribe();
            if(!dfr.isCreateable())
            {
                continue;
            }
            if(!dfr.isUpdateable()){
                fieldNamesNotEditable.add(dfr.getName());
            }
            if(dfr.calculated){
                system.debug('ITs working: ' +dfr.calculated);
            }
            outputFields.add(dfr.getName());
            system.debug(dfr.getName());
            system.debug(String.valueOf(dfr.getType()));
            fieldMappings.put(dfr.getName(), String.valueOf(dfr.getType()));
        }   
        system.debug('fieldMappings'+fieldMappings);
        Sobject record = targetType.newSObject();
        if(objType == 'Order_Ticket__c'){
            record.put('Incomplete_Record__c', True);
            
        }
        String type;
        for(String key : recordValues.keySet())
        {   
            type = (fieldMappings.containsKey(key) ? fieldMappings.get(key).toLowerCase() : null);
            
            if(recordValues.get(key)==null)
            {
                continue;
            }
            else if(type=='string' || type=='reference')
            {
                
                if(record.get('Id') != null && fieldNamesNotEditable.contains(key)){
                    continue;
                }
                else{
                    record.put(key, recordValues.get(key));
                    
                }
            }
            else if(type=='double')
            {
                record.put(key, Double.valueOf(recordValues.get(key)));
            }
            else if(type=='decimal')
            {
                record.put(key, Decimal.valueOf(recordValues.get(key)));
            }
            else if(type=='percent')
            {
                record.put(key, Decimal.valueOf(recordValues.get(key)));
            }
            else if(type=='integer')
            {
                record.put(key, Integer.valueOf(recordValues.get(key)));
            }
            else if(type=='currency'){
                
                record.put(key, Decimal.valueOf(recordValues.get(key)));
            }
            else if(type=='boolean')
            {
                if(recordValues.get(key)=='true' || recordValues.get(key)=='1')
                {
                    record.put(key, true);
                }
                else
                {
                    record.put(key, false);
                }
            }
        }
        
        System.debug(LoggingLevel.INFO, JSON.serializePretty(record));
        if(record.get('Id')!=null)
        {
            update record;
        }
        else
        {
            if(rtId!=null)
            {
                record.put('RecordTypeId', rtId);
            }
            insert record;
        }
        return record;
    }
    
    @AuraEnabled
    public static Decimal getTotalFieldSum(String parentFieldName, String parentFieldId, String fieldName){
        String query = 'SELECT SUM('+fieldName+') total FROM Order_Ticket__c WHERE '+ parentFieldName+' = \''+parentFieldId+'\' GROUP BY Financial_Account__c';
        List<AggregateResult> agrResult = Database.query(query);
        Decimal result = !agrResult.isEmpty() && agrResult[0].get('total') != null ? (Decimal)agrResult[0].get('total') : 0;
        return result;
    }
    
    @AuraEnabled
    public static SumObj getTotalFieldSumBLSTCM(String parentFieldName, String parentFieldId){
        String query = 'SELECT Initial_Funding_Percentage__c,Initial_Funding_Amount__c,Total_Initial_Funding_Amount__c FROM Order__c WHERE '+ parentFieldName+' = \''+parentFieldId+'\'';
        List<Order__c> tickets = Database.query(query);
        System.debug('tickets: ' + tickets);
        Decimal totalInitialFundingAmount =0;
        SumObj sumObj = new SumObj();
        sumObj.result = 0;
        sumObj.bondLadder = false;
        sumObj.stcm = false;
        if(!tickets.isEmpty()){
            for(Order__c o : tickets){
                if(o.Total_Initial_Funding_Amount__c != null){
                    totalInitialFundingAmount = o.Total_Initial_Funding_Amount__c;
                    sumObj.result = sumObj.result + o.Initial_Funding_Amount__c;
                }else if(o.Initial_Funding_Percentage__c != null){
                    sumObj.result = sumObj.result + o.Initial_Funding_Percentage__c;
                }
                
                /*if(o.Bond_Ladder__c){
sumObj.bondLadder = true;
}
if(o.Short_Term_Cash_Management__c){
sumObj.stcm = true;
}*/
            }
            
        }              
        System.debug('totalInitialFundingAmount: ' + totalInitialFundingAmount);
        
        
        
        if(totalInitialFundingAmount >0 ){
            sumObj.result = (sumObj.result * 100)/totalInitialFundingAmount;
        }
        System.debug('sumObj: ' + sumObj);
        
        return sumObj;
    }
    
    @AuraEnabled
    public static Boolean getBondLadder(String parentFieldName, String parentFieldId){
        String query = 'SELECT Bond_Ladder__c FROM Order_Ticket__c WHERE '+ parentFieldName+' = \''+parentFieldId+'\'';
        List<Order_Ticket__c> otList = Database.query(query);
        Boolean bondLadder;
        for(Order_Ticket__c o : otList){
            if(o.Bond_Ladder__c == true){
                bondLadder = true;
            }
        }
        return bondLadder;
    }
    
    @AuraEnabled
    public static Boolean getSTCM(String parentFieldName, String parentFieldId){
        String query = 'SELECT Short_Term_Cash_Management__c FROM Order_Ticket__c WHERE '+ parentFieldName+' = \''+parentFieldId+'\'';
        List<Order_Ticket__c> otList = Database.query(query);
        Boolean stcm;
        for(Order_Ticket__c o : otList){
            if(o.Short_Term_Cash_Management__c == true){
                stcm = true;
            }
        }
        return stcm;
    }
    
    @AuraEnabled
    public static FieldTotalAgrObj getTotalAmount(String sObjectName, String parentFieldName, String parentFieldId, String fieldName){
        FieldTotalAgrObj fldTotalObj = new FieldTotalAgrObj();
        //Getting the Label for the Field API Name
        Map<String, Schema.SObjectType> schemaMap = Schema.getGlobalDescribe();
        Schema.SObjectType objectSchema = schemaMap.get(sObjectName);
        Map<String, Schema.SObjectField> fieldMap = objectSchema.getDescribe().fields.getMap(); 
        Schema.DescribeFieldResult fieldResult = fieldMap.get(fieldName).getDescribe();
        fldTotalObj.fieldLabel = fieldResult.getLabel();
        fldTotalObj.fieldType = fieldResult.getType().Name();
        //Calculate the Aggregate SUM for the field
        String query = 'SELECT SUM('+fieldName+') total, format(SUM('+fieldName+')) formattedTotal FROM '+sObjectName+ ' WHERE '
            + parentFieldName+' = \''+parentFieldId+'\' GROUP BY ' +parentFieldName;
        List<AggregateResult> agrResult = Database.query(query);
        Decimal total = !agrResult.isEmpty() && agrResult[0].get('total') != null ? (Decimal)agrResult[0].get('total') : 0;
        fldTotalObj.totalSum = total;
        return fldTotalObj;
    }
    
    public static Map<String, String> getAllSObjectFieldsWithDataTypes(String sObjectName)
    {
        Map<String, String> mapAllSObjectFieldsWithDataTypes = new Map<String, String>();
        mapAllSObjectFieldsWithDataTypes = getAPIAndDataTypes(sObjectName);
        return mapAllSObjectFieldsWithDataTypes;
    }
    
    public static Map<String, String> getAPIAndDataTypes(String objectName)
    {
        Map<String, String> mapAPINameToDataType = new Map<String, String>();
        String type=objectName;        
        Map<String, Schema.SObjectType> schemaMap = Schema.getGlobalDescribe();
        Schema.SObjectType objectSchema = schemaMap.get(type);
        Map<String, Schema.SObjectField> fieldMap = objectSchema.getDescribe().fields.getMap();        
        for(SObjectField fieldName: fieldMap.values()) {
            String dataType = fieldMap.get(String.valueOf(fieldName)).getDescribe().getType().name();
            mapAPINameToDataType.put(String.valueOf(fieldName), dataType);
        }
        return mapAPINameToDataType;
    }
    
    @AuraEnabled
    public static List<String> getPicklistOptions(String objObject, string fld) {
        List<String> allOpts = new List<String> ();
        SObject sObjType = ((SObject) Type.forName(objObject).newInstance());
        Schema.sObjectType objType = sObjType.getSObjectType();
        Schema.DescribeSObjectResult objDescribe = objType.getDescribe();
        Map<String, Schema.SObjectField> fieldMap = objDescribe.fields.getMap();
        List<Schema.PicklistEntry> values = fieldMap.get(fld).getDescribe().getPickListValues();        
        
        for (Schema.PicklistEntry a: values) {
            allOpts.add(a.getValue());
        }
        return allOpts;
    }
    
    
    @AuraEnabled
    public static List<SObject> getExistingRecordsForFARPs(String flowInterviewId, String objType, String flowInterviewFieldName, List<String> fieldNames, String recordTypeName, List<string> wFAIds, String wFAFieldName)
    {
        Id rtId;
        if(recordTypeName != null){
            rtId = getRecordTypeId(objType, recordTypeName);
        }
        
        System.debug('wfaIds: ' + wFAIds);
        String query = 'SELECT Id, ' + String.join(fieldNames, ',') + ' FROM ' + objType;
        query += rtId != null || (flowInterviewFieldName != '' && flowInterviewId != '' ) || (wFAIds.size()>0 && wFAFieldName != '' ) ? ' WHERE ' : '';
        query += rtId != null ? ' RecordTypeId = \'' + rtId + '\' AND ' : '';
        query += (flowInterviewFieldName != '' && flowInterviewId != '') ? flowInterviewFieldName + ' = \'' + flowInterviewId + '\'' : ''; 
        query += (wFAIds.size() > 0 && wFAFieldName != '') ? ' AND ' + wFAFieldName + ' IN : wFAIds':'' ;
        query += ' ORDER BY ' + fieldNames.get(0);
        System.debug(LoggingLevel.INFO, query);
        List<Financial_Account_Related_Product__c> farps = Database.query(query);
        System.debug('farps: ' + farps);
        return Database.query(query);
    }
    
    public class FieldObj {       
        @AuraEnabled public String label;
        @AuraEnabled public String fieldName;
        @AuraEnabled public String dataType;
        @AuraEnabled public List<String> pickListOptions;
        @AuraEnabled public boolean formulaField;
        @AuraEnabled public boolean isEditable = false;
    }
    
    public class SumObj {       
        @AuraEnabled public Boolean bondLadder;
        @AuraEnabled public Boolean stcm;
        @AuraEnabled public Decimal result;
    }
    
    public class FieldTotalAgrObj {
        @AuraEnabled public String fieldLabel;
        @AuraEnabled public Decimal totalSum;
        @AuraEnabled public String fieldType;
        @AuraEnabled public String currencyCode = UserInfo.getDefaultCurrency();
    }
}