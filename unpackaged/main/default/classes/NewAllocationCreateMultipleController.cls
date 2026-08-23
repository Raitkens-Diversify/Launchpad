public class NewAllocationCreateMultipleController {

    @AuraEnabled
    public static List<SObject> getExistingRecordsToCreateNew(String allocationRecordId, String wizardFinId, String objType, List<String> fieldNames, String orderTicketId){
        System.debug('getExistingRecordsToCreateNew');
        if(orderTicketId == null){
            if(!String.isEmpty(allocationRecordId)){
                Allocation__c alloc = [SELECT Id, Wizard_Financial_Account__c FROM Allocation__c WHERE Id =: allocationRecordId LIMIT 1];
            }
            
            Order_Ticket__c ot = new Order_Ticket__c();
            ot.Wizard_Financial_Account__c = wizardFinId;
            insert ot;
            List<Order__c> orderListToInsert = new List<Order__c>();
            if(!String.isEmpty(allocationRecordId)){
                List<Allocation_Strategy__c> allocStratsList = [SELECT Id, Allocation__r.Wizard_Financial_Account__c, Strategy__c, Initial_Funding_Percentage__c FROM Allocation_Strategy__c WHERE Allocation__c =: allocationRecordId ORDER BY Strategy__c];

                for(Allocation_Strategy__c a : allocStratsList){
                    Order__c o = new Order__c();
                    o.Strategy__c = a.Strategy__c;
                    o.Initial_Funding_Percentage__c = a.Initial_Funding_Percentage__c;
                    o.Order_Ticket__c = ot.Id;
                    orderListToInsert.add(o);
                }
            }
            insert orderListToInsert;
            System.debug('orderListToInsert: ' + orderListToInsert);
            return orderListToInsert;
        } else {
            List<Order__c> ordersList = [SELECT Id, Strategy__c, Initial_Funding_Percentage__c, Order_Ticket__c FROM Order__c WHERE Order_Ticket__c =: orderTicketId];
            return ordersList;
        }
        
    }
    
    @AuraEnabled
    public static Id createNew(String wizardFinId, String objType, List<String> fieldNames){
        System.debug('createNew');
            Order_Ticket__c ot = new Order_Ticket__c();
            ot.Wizard_Financial_Account__c = wizardFinId;
            insert ot;
        return ot.Id;
        
    }
    
    @AuraEnabled
    public static Boolean deleteRecord(String recordId){
        System.debug('deleteRecord');
        try{
            String query = 'SELECT Id FROM Order__c WHERE Id=\'' + recordId + '\' LIMIT 1';
            system.debug(LoggingLevel.INFO, query);
            List<SObject> toDelete = database.query(query);
            if(toDelete.size()>0){
                delete toDelete;
            }
            return true;
        }
        catch(Exception e){
            System.debug(LoggingLevel.ERROR, 'Error Deleting: ' + e);
        }
        return false;
    }
    
    @AuraEnabled
    public static List<FieldObj> getFieldAndDatatype(String sObjectName, List<String> sObjectFields, List<String> readOnlyFields){
        System.debug('getFieldAndDatatype');
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
    
    public static Map<String, String> getAllSObjectFieldsWithDataTypes(String sObjectName){
        System.debug('getAllSObjectFieldsWithDataTypes');
        Map<String, String> mapAllSObjectFieldsWithDataTypes = new Map<String, String>();
        mapAllSObjectFieldsWithDataTypes = getAPIAndDataTypes(sObjectName);
        return mapAllSObjectFieldsWithDataTypes;
    }
    
    public static Map<String, String> getAPIAndDataTypes(String objectName){
        System.debug('getAPIAndDataTypes');
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
        System.debug('getPicklistOptions');
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
    public static SumObj getTotalFieldSumBLSTCM(String orderTicketId){
        System.debug('getTotalFieldSumBLSTCM');
        System.debug('orderTicketId: ' + orderTicketId);
        String query = 'SELECT Initial_Funding_Percentage__c,Initial_Funding_Amount__c,Total_Initial_Funding_Amount__c FROM Order__c WHERE Order_Ticket__c  = \''+orderTicketId+'\'';
        List<Order__c> allocs = Database.query(query);
        System.debug('tickets: ' + allocs);
        Decimal totalInitialFundingAmount =0;
        SumObj sumObj = new SumObj();
        sumObj.result = 0;
        sumObj.bondLadder = false;
        sumObj.stcm = false;
        if(!allocs.isEmpty()){
            for(Order__c a : allocs){
                if(a.Total_Initial_Funding_Amount__c != null){
                    totalInitialFundingAmount = a.Total_Initial_Funding_Amount__c;
                    sumObj.result = sumObj.result + a.Initial_Funding_Amount__c;
                }else if(a.Initial_Funding_Percentage__c != null){
                    sumObj.result = sumObj.result + a.Initial_Funding_Percentage__c;
                }
                //if(a.Bond_Ladder__c){
					//sumObj.bondLadder = true;
				//}
				//if(a.Short_Term_Cash_Management__c){
					//sumObj.stcm = true;
				//}
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
    public static SObject upsertRecordForCurrentAllocation(Map<String, String> recordValues, String allocationRecordId, String wizId){
        System.debug('upsertRecordForCurrentAllocation');
        System.debug('wizId: ' + wizId);
        Order_Ticket__c ot = [SELECT Id FROM Order_Ticket__c WHERE Wizard_Financial_Account__c =: wizId order by createddate desc limit 1];
        recordValues.put('Order_Ticket__c', ot.Id);
        Schema.SObjectType targetType = Schema.getGlobalDescribe().get( 'Order__c' );
        
        
        
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
        for(Schema.SObjectField sof : tempFields) {
            System.debug('sof: ' + sof);
            dfr = sof.getDescribe();
            if(!dfr.isCreateable()) {
                continue;
            }
            if(!dfr.isUpdateable()) {
                fieldNamesNotEditable.add(dfr.getName());
            }
            if(dfr.calculated) {
                system.debug('ITs working: ' +dfr.calculated);
            }
            outputFields.add(dfr.getName());
            system.debug(dfr.getName());
            system.debug(String.valueOf(dfr.getType()));
            fieldMappings.put(dfr.getName(), String.valueOf(dfr.getType()));
        }   
        system.debug('fieldMappings'+fieldMappings);
        Sobject record = targetType.newSObject();

        String type;
        System.debug('fieldMappings: ' + fieldMappings);
        for(String key : recordValues.keySet()){   
            type = (fieldMappings.containsKey(key) ? fieldMappings.get(key).toLowerCase() : null);
            System.debug('type: ' + type);
            
            if(recordValues.get(key)==null) {
                continue;
            } else if(type=='string' || type=='reference') {
                
                if(record.get('Id') != null && fieldNamesNotEditable.contains(key)) {
                    continue;
                } else {
                    record.put(key, recordValues.get(key));
                }
            } else if(type=='double') {
                record.put(key, Double.valueOf(recordValues.get(key)));
            } else if(type=='decimal') {
                record.put(key, Decimal.valueOf(recordValues.get(key)));
            } else if(type=='percent') {
                record.put(key, Decimal.valueOf(recordValues.get(key)));
            } else if(type=='integer') {
                record.put(key, Integer.valueOf(recordValues.get(key)));
            } else if(type=='currency') {
                record.put(key, Decimal.valueOf(recordValues.get(key)));
            } else if(type=='boolean') {
                if(recordValues.get(key)=='true' || recordValues.get(key)=='1') {
                    record.put(key, true);
                } else {
                    record.put(key, false);
                }
            }
        }
        
        System.debug(LoggingLevel.INFO, JSON.serializePretty(record));
        if(record.get('Id')!=null) {
            update record;
        } else {
            insert record;
        }
        return record;
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