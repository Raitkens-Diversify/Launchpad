public with sharing class EnvelopeFormAccountController {
    @AuraEnabled
    public Static List<Rep_Code__c> getRepCodesRelatedToFAT(Id householdId){
        
        if (householdId == null) {
            return new List<Rep_Code__c>();
        }
        
        // Get Financial Advisor Team Id safely
        Account acc = [
            SELECT Financial_Advisor_Team__c 
            FROM Account 
            WHERE Id = :householdId 
            LIMIT 1
        ];
        
        if (acc.Financial_Advisor_Team__c == null) {
            return new List<Rep_Code__c>();
        }
        
        // Query Rep Codes
        return [
            SELECT Id, Name, Financial_Advisor_Team__c
            FROM Rep_Code__c
            WHERE Financial_Advisor_Team__c = :acc.Financial_Advisor_Team__c
            WITH SECURITY_ENFORCED
            ORDER BY Name
        ];
    }
    
    @AuraEnabled
    public static String createOrUpdateFinancialAccountWithEnvelope(
        Id envelopeId,String accountNickname, Id existingAccountId) {
            if (String.isBlank(accountNickname) || envelopeId == null) {
                throw new AuraHandledException('Account Nickname and Envelope ID are required.');
            }
            try {
                // Get Envelope and related Household information
                Envelope__c envelope = [
                    SELECT Id, 
                    (SELECT Id, Account__c, 
                     Account__r.Financial_Advisor_Team__c, Wizard_Financial_Account__c
                     FROM Wizard_Envelope_Records__r
                     WHERE Account__c != null 
                     LIMIT 1)
                    FROM Envelope__c 
                    WHERE Id = :envelopeId 
                    LIMIT 1
                ];
                
                if (envelope.Wizard_Envelope_Records__r.isEmpty()) {
                    throw new AuraHandledException('No Household found related to this Envelope.');
                }
                
                Envelope_Content__c existingContent = envelope.Wizard_Envelope_Records__r[0];
                Id householdId = existingContent.Account__c;
                Id financialAdvisorTeamId = existingContent.Account__r.Financial_Advisor_Team__c;
                
                Financial_Account__c finAccount;
                
                // Check if we should update existing record or create new one
                if (existingAccountId != null) {
                    // Update existing Financial_Account__c record
                    finAccount = new Financial_Account__c(
                        Id = existingAccountId,
                        Name = accountNickname
                    );
                    update finAccount;               
                    return existingAccountId;
                } else {
                    // Create new Financial_Account__c record
                    finAccount = new Financial_Account__c(
                        Name = accountNickname,
                        Household__c = householdId,
                        Financial_Advisor_Team__c = financialAdvisorTeamId,
                        Submitted__c = false
                    );
                    
                    insert finAccount;
                    
                    
                    // create new Envelope_Content
                    Envelope_Content__c envelopeContent = new Envelope_Content__c(
                        Envelope__c = envelopeId,
                        Wizard_Financial_Account__c = finAccount.Id
                    );
                    insert envelopeContent;                
                    return finAccount.Id;
                }
                
            } catch (Exception e) {
                throw new AuraHandledException('Error creating/updating Financial Account: ' + e.getMessage());
            }
        }
    
    @AuraEnabled
    public static Map<String,List<String>> getAccountTypesFromMetadata(){
        Map<String,List<String>> accountTypesMap = new Map<String,List<String>>();
        
        try {
            List<Registration_Type__mdt> registrationTypes = [SELECT Category__c, MasterLabel 
                                                              FROM Registration_Type__mdt 
                                                              WHERE Category__c != null
                                                             ];
            
            if(registrationTypes.isEmpty()){
                System.debug('No Registration_Type__mdt records found with non-null Category__c.');
                return accountTypesMap;
            }
            
            for (Registration_Type__mdt rt : registrationTypes) {
                if (rt.Category__c == null) {
                    continue;
                }
                if (!accountTypesMap.containsKey(rt.Category__c)) {
                    accountTypesMap.put(rt.Category__c, new List<String>());
                }
                accountTypesMap.get(rt.Category__c).add(rt.MasterLabel);
            }
        }
        catch(Exception ex)
        {
            System.debug('Error while building category-to-labels map: ' + ex.getMessage());
        }
        
        return accountTypesMap;
    }
    @AuraEnabled
    public static Id createMember(Map<String, Object> acc, Id envelopeId) {
        
        if (acc == null || acc.isEmpty()) {
            throw new AuraHandledException('No account data provided');
        }
                system.debug('acc'+acc);

        
        // Record Type Mapping
        Map<String, String> recordTypeNameMap = new Map<String, String>{
            'client'   => 'PersonAccount',
                'business' => 'Business',
                'trust'    => 'Trust'
                };
                    
                    String recordType = (String) acc.get('RecordType');
        
        if (String.isBlank(recordType) || !recordTypeNameMap.containsKey(recordType.toLowerCase())) {
            throw new AuraHandledException('Invalid Record Type');
        }
        
        // Get Record Type Id
        Id recordTypeId = [
            SELECT Id
            FROM RecordType
            WHERE SobjectType = 'Account'
            AND DeveloperName = :recordTypeNameMap.get(recordType.toLowerCase())
            LIMIT 1
        ].Id;
        
        // Prepare Account Record
        Account accountRecord = new Account();
        accountRecord.RecordTypeId = recordTypeId;

        // Server-side backstop for the wizard's configured format rules.
        WizardFieldValidator.enforce('Account', acc);
        WizardFieldValidator.normalizeForStorage('Account', acc);

        // Dynamically map fields. Assignment failures collect and throw before DML: with formats
        // enforced up front, a key that still fails here is a real defect the caller must see.
        List<String> failedKeys = new List<String>();
        for (String key : acc.keySet()) {

            // Skip custom helper field
            if (key == 'RecordType') {
                continue;
            }

            try {
                accountRecord.put(key, acc.get(key));
            } catch (Exception e) {
                System.debug('Unable to map field: ' + key + ' Error: ' + e.getMessage());
                failedKeys.add(key);
            }
        }
        if (!failedKeys.isEmpty()) {
            throw new AuraHandledException(
                'These fields could not be saved: ' + String.join(failedKeys, ', '));
        }
        if (recordType.equalsIgnoreCase('client') && envelopeId != null) {
            List<Envelope_Content__c> householdContents = [
                SELECT Account__r.Financial_Advisor_Team__c
                FROM Envelope_Content__c
                WHERE Envelope__c = :envelopeId
                AND Account__c != null
                LIMIT 1
            ];
            if (!householdContents.isEmpty() && householdContents[0].Account__r.Financial_Advisor_Team__c != null) {
                accountRecord.Financial_Advisor_Team__c = householdContents[0].Account__r.Financial_Advisor_Team__c;
            }
        }
        system.debug('accountRecord'+accountRecord);
        insert accountRecord;
        // Create Envelope Content
        if (envelopeId != null) {

            insert new Envelope_Content__c(
                Envelope__c = envelopeId,
                Account__c = accountRecord.Id
            );
        }

        return accountRecord.Id;
    }
}