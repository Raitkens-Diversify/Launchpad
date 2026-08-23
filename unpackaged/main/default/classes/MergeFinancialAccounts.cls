public class MergeFinancialAccounts {
    
    @InvocableMethod(label='Merge Financial Accounts' description='Method used to merge two Financial Accounts')
    public static List<Response> mergeAccounts(List<Request> requests) {
        List<Response> responseList = new List<Response>();
        try{
            if (requests.isEmpty()){
                return responseList;
            } 
            Id recordId = requests[0].recordId;
            Id selectedRecordId = requests[0].selectedRecordId;
            
            // Fetch fields for Financial Account
            List<String> fatFieldNames = getUpdatableFields('FinServ__FinancialAccount__c');
            List<SObject> financialAccounts = queryRecords('FinServ__FinancialAccount__c', fatFieldNames, recordId, selectedRecordId);
            
            if (financialAccounts.size() < 2) {
                return addErrorResponse(responseList, 'Insufficient Financial Account records found.');
            }
            system.debug('financialAccounts[0]'+financialAccounts[0].get('Name'));
            system.debug('financialAccounts[1]'+financialAccounts[1].get('Name'));
            
            SObject recordFat ;
            SObject selectedRecordFat;
            if(financialAccounts[0].get('Id') == recordId){
                recordFat = financialAccounts[0];
                selectedRecordFat = financialAccounts[1];
            }else{
                selectedRecordFat = financialAccounts[0];
                recordFat = financialAccounts[1];
            }
            
            SObject recordFatToUpdate = recordFat.clone();
            system.debug('recordFatId'+recordFat.get('Id'));
            system.debug('selectedRecordFatId'+selectedRecordFat.get('Id'));
            
            recordFatToUpdate.put('Id', recordFat.get('Id'));
            
            // Fetch fields for Wizard Financial Account
            Id wfaRecordId = (Id) recordFat.get('Wizard_Financial_Account__c');
            Id wfaSelectedRecordId = (Id) selectedRecordFat.get('Wizard_Financial_Account__c');
            
            List<String> wfaFieldNames = getUpdatableFields('Wizard_Financial_Account__c');
            List<SObject> wizardFinancialAccounts = queryRecords('Wizard_Financial_Account__c', wfaFieldNames, wfaRecordId, wfaSelectedRecordId);
            
            if (wizardFinancialAccounts.size() < 2) {
                return addErrorResponse(responseList, 'Insufficient Wizard Financial Account records found.');
            }
            SObject recordWFA;
            SObject selectedRecordWFA;
            if(wizardFinancialAccounts[0].get('Id') == wfaRecordId){
                recordWFA = wizardFinancialAccounts[0];
                selectedRecordWFA = wizardFinancialAccounts[1];
            }else{
                selectedRecordWFA = wizardFinancialAccounts[0];
                recordWFA = wizardFinancialAccounts[1];
            }
            
            
            if (!mergeRecords(recordWFA, selectedRecordWFA, wfaFieldNames, recordFat, selectedRecordFat)) {
                system.debug('Product_Type__c'+ recordWFA.get('Product_Type__c'));
                
                return addErrorResponse(responseList, 'These Financial Accounts cannot be merged.');
            }
            
            system.debug('Product_Type__c'+ recordWFA.get('Product_Type__c'));
            system.debug('recordWFA'+ recordWFA);
            
            update recordWFA;
            
            if (!mergeRecords(recordFatToUpdate, selectedRecordFat, fatFieldNames, recordFat, selectedRecordFat)) {
                return addErrorResponse(responseList, 'These Financial Accounts cannot be merged.');
            }
            system.debug('recordFatToUpdate'+recordFatToUpdate);
            system.debug('recordFatToUpdateId'+recordFatToUpdate.get('Id')                        );
            
            update recordFatToUpdate;
            
            // Update related records
            updateRelatedRecords(recordId, selectedRecordId, wfaRecordId, wfaSelectedRecordId);
            delete selectedRecordFat;
            delete selectedRecordWFA;
            return responseList; 
        }
        catch(Exception ex){
            system.debug('responseList'+responseList);
            system.debug('ex'+ex);
            
            return addErrorResponse(responseList, 'These Financial Accounts cannot be merged.');
            
        }
        
    }
    
    private static List<String> getUpdatableFields(String sObjectType) {
        Schema.DescribeSObjectResult describeResult = Schema.getGlobalDescribe().get(sObjectType).getDescribe();
        Map<String, Schema.SObjectField> fieldsMap = describeResult.fields.getMap();
        
        Set<String> excludedFields = new Set<String>{
            'ownerid','IsDeleted', 'RecordTypeId', 'CreatedDate',
                'CreatedById', 'LastModifiedDate', 'LastModifiedById',
                'SystemModstamp', 'LastActivityDate', 'LastViewedDate', 'LastReferencedDate'
                };
                    
                    List<String> fieldNames = new List<String>();
        for (String fieldName : fieldsMap.keySet()) {
            Schema.DescribeFieldResult fieldDescribe = fieldsMap.get(fieldName).getDescribe();
            if (!excludedFields.contains(fieldName) && fieldDescribe.isUpdateable()) {
                fieldNames.add(fieldName);
            }
        }
        system.debug('fieldNames'+fieldNames);
        return fieldNames;
    }
    
    private static List<SObject> queryRecords(String sObjectType, List<String> fields, Id recordId, Id selectedRecordId) {
        String query = 'SELECT ' + String.join(fields, ', ') + ' FROM ' + sObjectType + ' WHERE Id = :recordId OR Id = :selectedRecordId';
        return Database.query(query);
    }
    
    private static boolean mergeRecords(SObject target, SObject source, List<String> fields, SObject originalFat, SObject selectedFat) {
        system.debug('fields'+fields);
        for (String field : fields) {
            
            if(field == 'Wizard_Financial_Account__c'){
                continue;
            }
            Object targetValue = target.get(field);
            Object sourceValue = source.get(field);
            System.debug('field '+ field);
            System.debug('targetValue '+targetValue);
            System.debug('sourceValue '+sourceValue);
            
            if (sourceValue == null || targetValue == sourceValue|| (targetValue == null && sourceValue == null )) continue;
            
            if (targetValue != null && sourceValue != null) {
                if (selectedFat.get('FinServ__SourceSystemId__c') != null && originalFat.get('FinServ__SourceSystemId__c') != null) {
                    System.debug('I am here');              
                    
                    return false;
                }
                if (originalFat.get('FinServ__SourceSystemId__c') != null) continue;
                if (selectedFat.get('FinServ__SourceSystemId__c') != null) {
                    System.debug('I am here');              
                    target.put(field, sourceValue);
                    continue;
                }
            } else if (targetValue == null && sourceValue != null ) {
                System.debug('I am here');              
                target.put(field, sourceValue);
            }
        }
        return true;
    }
    
    private static void updateRelatedRecords(Id recordId, Id selectedRecordId, Id wfaRecordId, Id wfaSelectedRecordId) {
        // Query all related records
        List<Case> caseRecords = [
            SELECT Id, FinServ__FinancialAccount__c, Wizard_Financial_Account__c
            FROM Case
            WHERE FinServ__FinancialAccount__c =: selectedRecordId OR
            Wizard_Financial_Account__c =: wfaSelectedRecordId
        ];
        
        
        List<Financial_Account_Related_Product__c> productRecords = [
            SELECT Id, Financial_Account__c, Wizard_Financial_Account__c
            FROM Financial_Account_Related_Product__c
            WHERE Financial_Account__c = : selectedRecordId OR
            Wizard_Financial_Account__c = : wfaSelectedRecordId
        ];
        
        List<Check_Deposit__c> depositRecords = [
            SELECT Id, Financial_Account__c
            FROM Check_Deposit__c
            WHERE Financial_Account__c = : selectedRecordId
        ];
        
        List<Check_Log__c> logRecords = [
            SELECT Id, Financial_Account__c, Wizard_Financial_Account__c
            FROM Check_Log__c
            WHERE Financial_Account__c = : selectedRecordId OR
            Wizard_Financial_Account__c = :wfaSelectedRecordId
        ];
        
        List<Instruction__c> instructionRecords = [
            SELECT Id, Financial_Account__c
            FROM Instruction__c
            WHERE Financial_Account__c = : selectedRecordId
        ];
        
        List<Order_Ticket__c> ticketRecords = [
            SELECT Id, Financial_Account__c, Wizard_Financial_Account__c
            FROM Order_Ticket__c
            WHERE Financial_Account__c = : selectedRecordId OR
            Wizard_Financial_Account__c = : wfaSelectedRecordId
        ];
        
        List<Standing_Letter_of_Authorization__c> authorizationRecords = [
            SELECT Id, Financial_Account__c
            FROM Standing_Letter_of_Authorization__c
            WHERE Financial_Account__c = : selectedRecordId
        ];
        
        List<Trade_Error_Impacted_Account__c> tradeErrorRecords = [
            SELECT Id, Financial_Account__c
            FROM Trade_Error_Impacted_Account__c
            WHERE Financial_Account__c = : selectedRecordId
        ];
        
        // Update each record as per the requirements
        for (Case caseRecord : caseRecords) {
            caseRecord.FinServ__FinancialAccount__c = recordId;
            caseRecord.Wizard_Financial_Account__c = wfaRecordId;
        }
        
        for (Financial_Account_Related_Product__c productRecord : productRecords) {
            productRecord.Financial_Account__c = recordId;
            productRecord.Wizard_Financial_Account__c = wfaRecordId;
        }
        
        for (Check_Deposit__c depositRecord : depositRecords) {
            depositRecord.Financial_Account__c = recordId;
        }
        
        for (Check_Log__c logRecord : logRecords) {
            logRecord.Financial_Account__c = recordId;
            logRecord.Wizard_Financial_Account__c = wfaRecordId;
        }
        
        for (Instruction__c instructionRecord : instructionRecords) {
            instructionRecord.Financial_Account__c = recordId;
        }
        
        for (Order_Ticket__c ticketRecord : ticketRecords) {
            ticketRecord.Financial_Account__c = recordId;
            ticketRecord.Wizard_Financial_Account__c = wfaRecordId;
        }
        
        for (Standing_Letter_of_Authorization__c authorizationRecord : authorizationRecords) {
            authorizationRecord.Financial_Account__c = recordId;
        }
        
        for (Trade_Error_Impacted_Account__c tradeErrorRecord : tradeErrorRecords) {
            tradeErrorRecord.Financial_Account__c = recordId;
        }
        
        // Perform updates
        update caseRecords;
        update productRecords;
        update depositRecords;
        update logRecords;
        update instructionRecords;
        update ticketRecords;
        update authorizationRecords;
        update tradeErrorRecords;
    }
    
    private static List<Response> addErrorResponse(List<Response> responseList, String message) {
        Response response = new Response();
        response.message = message;
        responseList.add(response);
        return responseList;
    }
    
    public class Request {
        @InvocableVariable
        public Id recordId;
        
        @InvocableVariable
        public Id selectedRecordId;
    }
    
    public class Response {
        @InvocableVariable
        public String message;
    }
}