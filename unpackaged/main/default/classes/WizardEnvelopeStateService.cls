public with sharing class WizardEnvelopeStateService {
    public class EnvelopeState {
        @AuraEnabled public Id envelopeId;
        @AuraEnabled public String envelopeJson;
        @AuraEnabled public String stateStorage;
        @AuraEnabled public String householdName;
        @AuraEnabled public String currentStepId;
        @AuraEnabled public String status;
        @AuraEnabled public String envelopeName;
        @AuraEnabled public Datetime lastSaved;
    }
    
    private static final Integer JSON_SAFE_LIMIT = 120000;

    // The Case a wizard Financial Account opens against. A mixed interview type (Envelope_Field__mdt
    // rows for both Financial_Account__c and Case under one Type__c) writes its Case-targeted answers
    // here and reads them back from the same record, so the criteria live in one place: the write
    // below and FieldDetailController.getCaseValuesForAccounts must always resolve the same Case.
    public static final String WIZARD_CASE_ORIGIN = 'Wizard';
    public static final String ACCOUNT_OPENING_CASE_TYPE = 'Account Opening';

    // The related-product row a wizard Financial Account's product answer lives on. Its own record is
    // the answer, so the criteria that resolve it live in one place: the write below and
    // FieldDetailController.getRelatedProductValuesForAccounts must always resolve the same row.
    public static final String RELATED_PRODUCT_OBJECT = 'Financial_Account_Related_Product__c';
    
    // missingItemsCount / missingItemsHasPlus are the envelope's outstanding-input total, computed by
    // the wizard (c/envelopeFormSchema) over the same action items its own screens count, and stored so
    // the envelope list can render its Missing Items column without re-deriving it. The list cannot
    // derive it: the answers live on the records now (Accounts, Financial Accounts, Services and the
    // action-item Cases), and c/envelopeShellV2 strips every record-backed entity out of
    // Envelope_JSON__c, so the blob no longer holds what a count would have to read.
    //
    // A null count leaves both fields untouched — the client sends null when a schema it needed had
    // not loaded, and a stale real number beats overwriting it with a wrong zero.
    @AuraEnabled
    public static EnvelopeState saveEnvelopeState(
        Id wizardEnvelopeId,
        String envelopeJson,
        String envelopeName,
        String householdName,
        String currentStepId,
        String status,
        Integer missingItemsCount,
        Boolean missingItemsHasPlus
    ) {
        if (String.isBlank(envelopeJson)) {
            throw new AuraHandledException('Envelope data is empty.');
        }
        
        Envelope__c record = wizardEnvelopeId == null
            ? new Envelope__c()
            : new Envelope__c(Id = wizardEnvelopeId);
        
        if (!String.isBlank(envelopeName)) {
            record.Name = envelopeName;
        }
        if (!String.isBlank(status)) {
            record.Status__c = status;
        }
        // JACKSON DEAD CODE CLEANUP: dead branch — empty body (its one statement is commented out). The
        // householdName parameter is accepted and echoed back in the response but never persisted. Either wire it
        // up or delete the branch. docs/envelope-wizard-audit.md Appendix A.
        /*if (!String.isBlank(householdName)) {
            // record.Household__r.Name = householdName;
         }*/
        if (!String.isBlank(currentStepId)) {
            record.Current_Step__c = currentStepId;
        }
        record.Envelope_Version__c = 1;
        record.Last_Saved__c = System.now();
        if (missingItemsCount != null) {
            record.Missing_Items_Count__c = missingItemsCount;
            record.Missing_Items_Has_Plus__c = missingItemsHasPlus == true;
        }
        
        upsert record;
        
        Boolean fitsInField = envelopeJson.length() <= JSON_SAFE_LIMIT;
        if (fitsInField) {
            record = new Envelope__c(
                Id = record.Id,
                Envelope_JSON__c = envelopeJson,
                State_Storage__c = 'Field',
                State_File_DocumentId__c = null
            );
            update record;
        } else {
            ContentVersion version = new ContentVersion(
                Title = 'Envelope State ' + record.Id,
                PathOnClient = 'EnvelopeState.json',
                VersionData = Blob.valueOf(envelopeJson),
                FirstPublishLocationId = record.Id
            );
            insert version;
            
            ContentVersion savedVersion = [
                SELECT ContentDocumentId
                FROM ContentVersion
                WHERE Id = :version.Id
                LIMIT 1
            ];
            
            record = new Envelope__c(
                Id = record.Id,
                Envelope_JSON__c = null,
                State_Storage__c = 'File',
                State_File_DocumentId__c = savedVersion.ContentDocumentId
            );
            update record;
        }
        
        EnvelopeState response = new EnvelopeState();
        response.envelopeId = record.Id;
        response.envelopeName = envelopeName;
        response.householdName = householdName;
        response.currentStepId = currentStepId;
        response.status = status;
        response.stateStorage = fitsInField ? 'Field' : 'File';
        response.lastSaved = System.now();
        return response;
    }
    
    @AuraEnabled
    public static EnvelopeState loadEnvelopeState(Id wizardEnvelopeId) {
        EnvelopeState response = new EnvelopeState();
        if (wizardEnvelopeId == null) {
            return response;
        }
        
        Envelope__c record = [
            SELECT Id, Name, Status__c, Household__r.Name, Current_Step__c,
            Envelope_JSON__c, State_Storage__c, State_File_DocumentId__c,
            Last_Saved__c
            FROM Envelope__c
            WHERE Id = :wizardEnvelopeId
            LIMIT 1
        ];
        
        response.envelopeId = record.Id;
        response.envelopeName = record.Name;
        response.status = record.Status__c;
        response.householdName = record.Household__r.Name;
        response.currentStepId = record.Current_Step__c;
        response.stateStorage = record.State_Storage__c;
        response.lastSaved = record.Last_Saved__c;
        
        if (!String.isBlank(record.Envelope_JSON__c)) {
            response.envelopeJson = record.Envelope_JSON__c;
            return response;
        }
        
        if (!String.isBlank(record.State_File_DocumentId__c)) {
            ContentVersion latestVersion = [
                SELECT VersionData
                FROM ContentVersion
                WHERE ContentDocumentId = :record.State_File_DocumentId__c
                ORDER BY VersionNumber DESC
                LIMIT 1
            ];
            response.envelopeJson = latestVersion.VersionData.toString();
        }
        
        return response;
    }
    
    // JACKSON DEAD CODE CLEANUP: dead method. Zero JS callers anywhere and no test invokes it. Remove with
    // Tier 4d of docs/envelope-wizard-audit.md.
    /* @AuraEnabled
public static void saveWizardViewPreference(String viewMode) {
update new User(
Id = UserInfo.getUserId(),
Wizard_View_Preference__c = viewMode
);
}*/
    
    @AuraEnabled
    public static void saveAccountInfo(Map<String, Object> data) {

        if (data == null || !data.containsKey('Id') || data.get('Id') == null) {
            throw new AuraHandledException('Record Id is required for update.');
        }
        
        Id recordId = (Id) data.get('Id');
        Financial_Account__c faRecord = new Financial_Account__c(Id = recordId);
        
        // Server-side backstop for the wizard's configured format rules (the client filters
        // format-invalid values out of autosave payloads before they get here).
        WizardFieldValidator.enforce('Financial_Account__c', data);
        
        Map<String, Schema.SObjectField> fieldMap =
            Financial_Account__c.SObjectType.getDescribe().fields.getMap();
        
        // Assignment failures collect and throw before DML: with formats enforced up front, a key
        // that still fails here is a real defect the caller must see, not debug-log noise. Values
        // are coerced first — lightning-input emits numbers and dates as strings, which a bare
        // put() rejects ("Illegal assignment from String to Decimal").
        List<String> failedKeys = new List<String>();
        for (String key : data.keySet()) {
            if (key == 'Id') continue;
            
            if (fieldMap.containsKey(key)) {
                try {
                    faRecord.put(key, coerceFieldValue(fieldMap.get(key), data.get(key)));
                } catch (Exception e) {
                    System.debug('Error setting field ' + key + ': ' + e.getMessage());
                    failedKeys.add(key);
                }
            }
        }
        if (!failedKeys.isEmpty()) {
            throw new AuraHandledException(
                'These fields could not be saved: ' + String.join(failedKeys, ', '));
        }
        try {
            update faRecord;
        } catch (DmlException e) {
            throw new AuraHandledException('Update failed: ' + e.getDmlMessage(0));
        }
    }
    
    // saveAccountInfo's counterpart for the Case half of a mixed account interview: writes the
    // Case-targeted answers onto the Financial Account's wizard Case. `caseData` is keyed by real
    // Case field API names and carries the FINANCIAL ACCOUNT id under 'Id' — the Case is resolved
    // from it, not addressed directly.
    //
    // Accounts opened through the wizard already have their Case (EnvelopeISAController creates it
    // with the account), but an account that existed on the household before the envelope has none,
    // so one is created on demand and linked to the envelope the same way. Creation is gated on the
    // payload carrying at least one filled answer, so neither an id-only payload nor a draft whose
    // answers have all been cleared conjures an empty Case.
    @AuraEnabled
    public static void saveAccountCaseInfo(Map<String, Object> caseData, Id envelopeId) {
        if (caseData == null || !caseData.containsKey('Id') || caseData.get('Id') == null) {
            throw new AuraHandledException('Record Id is required for update.');
        }

        Id faId = (Id) caseData.get('Id');

        // Server-side backstop for the wizard's configured format rules (the client filters
        // format-invalid values out of autosave payloads before they get here).
        WizardFieldValidator.enforce('Case', caseData);

        Map<String, Schema.SObjectField> fieldMap =
            Case.SObjectType.getDescribe().fields.getMap();

        // Assignment failures collect and throw before DML: with formats enforced up front, a key
        // that still fails here is a real defect the caller must see, not debug-log noise. Values
        // are coerced first — lightning-input emits numbers and dates as strings, which a bare
        // put() rejects ("Illegal assignment from String to Decimal").
        // Cleared answers count as assigned (a blank coerces to null and has to reach the record, or
        // clearing a field in the interview would never stick) but not as answered — an all-blank
        // draft must not open a Case for an account that never had one.
        Case caseRecord = new Case();
        List<String> failedKeys = new List<String>();
        Integer assignedFields = 0;
        Integer answeredFields = 0;
        for (String key : caseData.keySet()) {
            if (key == 'Id') continue;

            if (fieldMap.containsKey(key)) {
                try {
                    Object value = coerceFieldValue(fieldMap.get(key), caseData.get(key));
                    caseRecord.put(key, value);
                    assignedFields++;
                    if (value != null) {
                        answeredFields++;
                    }
                } catch (Exception e) {
                    System.debug('Error setting field ' + key + ': ' + e.getMessage());
                    failedKeys.add(key);
                }
            }
        }
        if (!failedKeys.isEmpty()) {
            throw new AuraHandledException(
                'These fields could not be saved: ' + String.join(failedKeys, ', '));
        }
        if (assignedFields == 0) {
            return;
        }

        // Oldest first, matching FieldDetailController.getCaseValuesForAccounts, so the record this
        // writes is always the one the interview displays.
        List<Case> caseRecords = [
            SELECT Id
            FROM Case
            WHERE Wizard_Financial_Account__c = :faId
            AND Origin = :WIZARD_CASE_ORIGIN
            AND Type = :ACCOUNT_OPENING_CASE_TYPE
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];

        if (!caseRecords.isEmpty()) {
            caseRecord.Id = caseRecords[0].Id;
            try {
                update caseRecord;
            } catch (DmlException e) {
                throw new AuraHandledException('Update failed: ' + e.getDmlMessage(0));
            }
            return;
        }

        if (answeredFields == 0) {
            return;
        }
        createAccountCase(caseRecord, faId, envelopeId);
    }

    // Open the account's wizard Case around the answers already assigned to `caseRecord`, mirroring
    // the record EnvelopeISAController creates alongside a wizard-created Financial Account so both
    // paths produce the same shape, and link it to the envelope like the create path does.
    private static void createAccountCase(Case caseRecord, Id faId, Id envelopeId) {
        List<Financial_Account__c> accounts = [
            SELECT Id, Household__c, Financial_Advisor_Team__c
            FROM Financial_Account__c
            WHERE Id = :faId
            LIMIT 1
        ];
        if (accounts.isEmpty()) {
            throw new AuraHandledException('The account these answers belong to no longer exists.');
        }
        Financial_Account__c faRecord = accounts[0];

        Id householdId = EnvelopeHouseholdResolver.resolveHouseholdId(envelopeId);
        caseRecord.Subject = 'New Financial Account';
        caseRecord.Origin = WIZARD_CASE_ORIGIN;
        caseRecord.Type = ACCOUNT_OPENING_CASE_TYPE;
        caseRecord.Household__c = householdId != null ? householdId : faRecord.Household__c;
        caseRecord.Financial_Advisor_Team__c = faRecord.Financial_Advisor_Team__c;
        caseRecord.Wizard_Financial_Account__c = faRecord.Id;
        caseRecord.Submitted__c = false;

        try {
            insert caseRecord;
            if (envelopeId != null) {
                insert new Envelope_Content__c(
                    Envelope__c = envelopeId,
                    Case__c = caseRecord.Id
                );
            }
        } catch (DmlException e) {
            throw new AuraHandledException('Save failed: ' + e.getDmlMessage(0));
        }
    }
    
    
    /**
     * saveAccountCaseInfo's counterpart for the product a Financial Account's interview selects. The
     * answer is a record rather than a field value: it lives on the account's related-product row.
     *
     * One such row per wizard Financial Account. The product is the row's master and cannot be
     * emptied, so a cleared answer removes the row rather than blanking it, and a row only comes into
     * existence once a product has actually been chosen.
     *
     * The wizard is the only path that creates these rows, so Wizard_Financial_Account__c alone
     * resolves the interview's row — read, update and delete all resolve it the same way, so the
     * interview can never display one row and write another.
     *
     * The row is also stamped with the account's wizard Case (Case__c) so the product is linked to the
     * Case from creation. The Case may not exist yet when only the product has been answered
     * (saveAccountCaseInfo opens the Case on demand from the first filled Case answer), so a missing
     * Case leaves Case__c null and a later save backfills it. Once stamped it is never repointed.
     *
     * Amount__c mirrors the same Case's Amount__c — the interview captures the amount as a Case field
     * (saveAccountCaseInfo runs before this in every call site, so the Case value is already current)
     * and the product row carries a copy of it. Unlike the Case link it is kept in sync: an edited or
     * cleared amount tracks onto the row. It is null whenever the Case is not resolved yet.
     *
     * @param productId          the chosen product, or null to clear
     * @param financialAccountId the wizard Financial Account the answer belongs to
     */
    @AuraEnabled
    public static void saveRelatedProduct(Id productId, Id financialAccountId) {
        if (financialAccountId == null) {
            throw new AuraHandledException('Financial Account Id is required.');
        }

        List<Financial_Account_Related_Product__c> existing = [
            SELECT Id, Product__c, Case__c, Amount__c
            FROM Financial_Account_Related_Product__c
            WHERE Wizard_Financial_Account__c = :financialAccountId
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];

        // The account's wizard Case, resolved the same way as saveAccountCaseInfo so this row links to
        // the Case the interview writes to. Amount__c is read here so the row mirrors the Case's amount.
        // Empty when the Case has not been opened yet.
        List<Case> wizardCases = [
            SELECT Id, Amount__c
            FROM Case
            WHERE Wizard_Financial_Account__c = :financialAccountId
            AND Origin = :WIZARD_CASE_ORIGIN
            AND Type = :ACCOUNT_OPENING_CASE_TYPE
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];
        Id caseId = wizardCases.isEmpty() ? null : wizardCases[0].Id;
        Decimal caseAmount = wizardCases.isEmpty() ? null : wizardCases[0].Amount__c;

        try {
            if (productId == null) {
                if (!existing.isEmpty()) {
                    delete existing[0];
                }
                return;
            }

            if (existing.isEmpty()) {
                insert new Financial_Account_Related_Product__c(
                    Product__c = productId,
                    Wizard_Financial_Account__c = financialAccountId,
                    Case__c = caseId,
                    Amount__c = caseAmount
                );
                return;
            }

            // Repoint the row rather than replacing it: it is history-tracked and each write announces
            // it downstream by id, so a delete-and-insert would read as a different record. Skipping an
            // unchanged write is also what stops an idle interview re-announcing it on every autosave.
            Boolean productChanged = existing[0].Product__c != productId;
            // Backfill the Case only while it is still empty: the row may have been created before the
            // Case existed, and once stamped the Case must not be repointed.
            Boolean needsCaseBackfill = existing[0].Case__c == null && caseId != null;
            // Keep the amount in step with the Case's, but only while a Case is resolved, so a momentary
            // empty Case lookup never wipes an amount the row already carries.
            Boolean amountChanged = caseId != null && existing[0].Amount__c != caseAmount;
            if (productChanged) {
                existing[0].Product__c = productId;
            }
            if (needsCaseBackfill) {
                existing[0].Case__c = caseId;
            }
            if (amountChanged) {
                existing[0].Amount__c = caseAmount;
            }
            if (productChanged || needsCaseBackfill || amountChanged) {
                update existing[0];
            }
        } catch (DmlException e) {
            throw new AuraHandledException('Save failed: ' + e.getDmlMessage(0));
        }
    }

    /**
     * saveRelatedProduct's counterpart for an Account Action Item (e.g. Purchase Alternative
     * Investments), whose interview is also mixed-object (Case + Financial_Account_Related_Product__c)
     * but whose Case is a servicing action, not the account-opening Case.
     *
     * The row is scoped to the action's own Case (Case__c = caseId), not just the Financial Account,
     * so it never touches or repoints the account's existing account-opening product row — an existing
     * account may already carry one. Amount__c mirrors this action Case's Amount__c, kept in sync the
     * same way saveRelatedProduct keeps it in step with the opening Case.
     *
     * @param productId          the chosen product, or null to clear (deletes this action's row)
     * @param financialAccountId the wizard Financial Account the answer belongs to
     * @param caseId             the action's Case, which scopes and links the row
     */
    @AuraEnabled
    public static void saveActionRelatedProduct(Id productId, Id financialAccountId, Id caseId) {
        if (financialAccountId == null) {
            throw new AuraHandledException('Financial Account Id is required.');
        }
        if (caseId == null) {
            throw new AuraHandledException('Case Id is required.');
        }

        // Scoped by Case, so the action's row is independent of the account-opening row (which carries
        // a different Case, or none).
        List<Financial_Account_Related_Product__c> existing = [
            SELECT Id, Product__c, Case__c, Amount__c
            FROM Financial_Account_Related_Product__c
            WHERE Wizard_Financial_Account__c = :financialAccountId
            AND Case__c = :caseId
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];

        // The amount the row mirrors is this action Case's own Amount__c (the interview captures it as a
        // Case field, written before this call in every call site).
        List<Case> actionCases = [
            SELECT Id, Amount__c FROM Case WHERE Id = :caseId LIMIT 1
        ];
        Decimal caseAmount = actionCases.isEmpty() ? null : actionCases[0].Amount__c;

        try {
            if (productId == null) {
                if (!existing.isEmpty()) {
                    delete existing[0];
                }
                return;
            }

            if (existing.isEmpty()) {
                insert new Financial_Account_Related_Product__c(
                    Product__c = productId,
                    Wizard_Financial_Account__c = financialAccountId,
                    Case__c = caseId,
                    Amount__c = caseAmount
                );
                return;
            }

            // Repoint the row rather than replacing it (history-tracked, announced downstream by id).
            Boolean productChanged = existing[0].Product__c != productId;
            Boolean amountChanged = existing[0].Amount__c != caseAmount;
            if (productChanged) {
                existing[0].Product__c = productId;
            }
            if (amountChanged) {
                existing[0].Amount__c = caseAmount;
            }
            if (productChanged || amountChanged) {
                update existing[0];
            }
        } catch (DmlException e) {
            throw new AuraHandledException('Save failed: ' + e.getDmlMessage(0));
        }
    }


    // saveAccountInfo's counterpart for Service Agreements: writes a service interview's field
    // values onto the real Service__c record (update-only, keyed by real field API names). String
    // values are coerced to the field's Apex type — the service schema carries date fields, which
    // arrive from the client as ISO strings.
    @AuraEnabled
    public static void saveServiceInfo(Map<String, Object> data) {
        
        if (data == null || !data.containsKey('Id') || data.get('Id') == null) {
            throw new AuraHandledException('Record Id is required for update.');
        }
        
        Id recordId = (Id) data.get('Id');
        Service__c serviceRecord = new Service__c(Id = recordId);
        
        // Server-side backstop for the wizard's configured format rules (the client filters
        // format-invalid values out of autosave payloads before they get here).
        WizardFieldValidator.enforce('Service__c', data);
        
        Map<String, Schema.SObjectField> fieldMap =
            Service__c.SObjectType.getDescribe().fields.getMap();
        
        List<String> failedKeys = new List<String>();
        for (String key : data.keySet()) {
            if (key == 'Id') continue;
            
            if (fieldMap.containsKey(key)) {
                try {
                    serviceRecord.put(key, coerceFieldValue(fieldMap.get(key), data.get(key)));
                } catch (Exception e) {
                    System.debug('Error setting field ' + key + ': ' + e.getMessage());
                    failedKeys.add(key);
                }
            }
        }
        if (!failedKeys.isEmpty()) {
            throw new AuraHandledException(
                'These fields could not be saved: ' + String.join(failedKeys, ', '));
        }
        try {
            update serviceRecord;
        } catch (DmlException e) {
            throw new AuraHandledException('Update failed: ' + e.getDmlMessage(0));
        }
    }
    
    // String-to-field-type coercion for the record-write save paths (saveAccountInfo /
    // saveServiceInfo): lightning-input emits numbers and dates as strings. Non-string values
    // (real booleans and numbers from JSON) pass through; a blank string means "cleared" and
    // becomes null.
    // Public so the other wizard controllers writing interview answers to a record share one
    // coercion, rather than each carrying its own copy of these type rules.
    public static Object coerceFieldValue(Schema.SObjectField field, Object value) {
        if (field == null || !(value instanceof String)) {
            return value;
        }
        String text = (String) value;
        if (String.isBlank(text)) {
            return null;
        }
        switch on field.getDescribe().getType() {
            when DATE {
                return Date.valueOf(text);
            }
            when DATETIME {
                return Datetime.valueOfGmt(text.replace('T', ' ').removeEnd('Z'));
            }
            when BOOLEAN {
                return Boolean.valueOf(text);
            }
            when DOUBLE, CURRENCY, PERCENT {
                return Decimal.valueOf(text);
            }
            when INTEGER {
                return Integer.valueOf(text);
            }
            when else {
                return value;
            }
        }
    }
    
    @AuraEnabled(cacheable=false)
    public static UserPreferenceWrapper getUserPreferences() {
        User u = [
            SELECT Wizard_View_Preference__c, Relationship_to_firm__c, Profile.UserLicense.Name
            FROM User
            WHERE Id = :UserInfo.getUserId()
        ];

        return new UserPreferenceWrapper(
            u.Wizard_View_Preference__c,
            u.Relationship_to_firm__c,
            u.Profile.UserLicense.Name
        );
    }
    // JACKSON DEAD CODE CLEANUP: dead-path method. Only importer is the superseded V1 envelopeShell (zero live
    // callers). Remove with Tier 4d after the V1 tree (Tier 3a) is gone. docs/envelope-wizard-audit.md.
    /*@AuraEnabled(cacheable=true)
public static Map<String, List<FieldInfo>> getRequiredFieldInfoByType() {

Map<String, List<FieldInfo>> result = new Map<String, List<FieldInfo>>();

for (Envelope_Field__mdt fieldMdt : [
SELECT Type__c,
Required__c,
Key_Decision__c,
Field_API__c,
Label__c,
Required_WHERE_Statement__c
FROM Envelope_Field__mdt
]) {

String type = fieldMdt.Type__c;

if (String.isNotBlank(type) && type.startsWith('Client - ')) {
type = type.replace('Client - ', '').trim();
}

if (!result.containsKey(type)) {
result.put(type, new List<FieldInfo>());
}
if (fieldMdt.Required__c || fieldMdt.Key_Decision__c || fieldMdt.Required_WHERE_Statement__c != null) {
FieldInfo fieldInfo = new FieldInfo();
fieldInfo.fieldApiName = fieldMdt.Field_API__c;
fieldInfo.fieldLabel = fieldMdt.Label__c;
fieldInfo.required = fieldMdt.Required__c;
fieldInfo.keyDecision = fieldMdt.Key_Decision__c;
fieldInfo.requiredWhereStatement = fieldMdt.Required_WHERE_Statement__c;
result.get(type).add(fieldInfo);
}
}

return result;
}*/
    @AuraEnabled
    public static String createServiceAgreement(
        Id envelopeId,String serviceNickname) {
            if (String.isBlank(serviceNickname) || envelopeId == null) {
                throw new AuraHandledException('Service Agreement Nickname and Envelope ID are required.');
            }
            try {
                // Resolve the household from the envelope's Household-record-type content row so the
                // service is stamped with the household and reloads via getHouseholdMembersAndAccounts.
                List<Envelope_Content__c> householdContent = [
                    SELECT Account__c
                    FROM Envelope_Content__c
                    WHERE Envelope__c = :envelopeId
                    AND Account__c != null
                    AND Account__r.RecordType.Name = 'Household'
                    LIMIT 1
                ];
                Id householdId = householdContent.isEmpty() ? null : householdContent[0].Account__c;
                
                Service__c service = new Service__c(
                    Name = serviceNickname,
                    Household__c = householdId
                );
                insert service;
                
                // create new Envelope_Content
                Envelope_Content__c envelopeContent = new Envelope_Content__c(
                    Envelope__c = envelopeId,
                    Service__c = service.Id
                );
                insert envelopeContent;                
                return service.Id;
            }
            catch (Exception e) {
                throw new AuraHandledException('Error creating Service Agreement : ' + e.getMessage());
            }
        }
    
    
    // Each of these returns the *other* records the removal took out of the envelope — the related
    // parties left without the role that put them here. The caller owns the outline, and those rows
    // are entities in their own right, so it has to be told which ones went rather than inferring it
    // from a later read. Empty when the removal took nothing else with it.
    @AuraEnabled
    public static List<Id> removeHouseholdMembers(List<Id> memberIds, Id envelopeId) {
        return deleteRecordsAndEnvelopeContent(memberIds, envelopeId);
    }

    @AuraEnabled
    public static List<Id> removeFinancialAccounts(List<Id> accountIds, Id envelopeId) {
        return deleteRecordsAndEnvelopeContent(accountIds, envelopeId);
    }

    @AuraEnabled
    public static List<Id> removeServices(List<Id> serviceIds, Id envelopeId) {
        return deleteRecordsAndEnvelopeContent(serviceIds, envelopeId);
    }

    // The Account_Account_Relationship__c record type carrying a related party's role. Mirrors
    // EnvelopeHouseholdMemberController.RELATED_PARTY_RECORD_TYPE: relationships of any other record
    // type belong to something else and are never removed here.
    private static final String RELATED_PARTY_RECORD_TYPE = 'Fiduciary_Legal';

    // Takes a record out of one envelope, and deletes it only if nothing else still uses it.
    //
    // Removing a member is not the same as deleting them. The same person can be created in one
    // envelope and picked as a related party in another, so this unlinks the record from the given
    // envelope first and then asks whether anything anywhere still references it. Only a record that
    // nothing references is deleted, along with everything saveEntity created for it — otherwise the
    // record survives, simply no longer part of this envelope.
    //
    // The related parties the removed record held are judged on the same terms straight after: one
    // still serving this envelope on another entity keeps its place, and the rest leave the envelope
    // with the record whose role was their only reason to be here.
    //
    // A blank envelopeId means "no envelope context": the links are then not envelope-scoped, and the
    // record is only deleted if it is unused, on the same terms.
    //
    // Returns the parties that left the envelope with the record, for the caller's outline.
    private static List<Id> deleteRecordsAndEnvelopeContent(List<Id> recordIds, Id envelopeId)
    {
        if (recordIds == null || recordIds.isEmpty()) {
            return new List<Id>();
        }
        Set<Id> ids = new Set<Id>();
        for (Id recordId : recordIds) {
            if (recordId != null) {
                ids.add(recordId);
            }
        }
        if (ids.isEmpty()) {
            return new List<Id>();
        }

        Set<Id> strandedParties = deleteRelatedPartyLinks(ids, envelopeId);
        unlinkAndDeleteIfUnused(ids, envelopeId);

        // Run after the removal above so the record being removed is no longer part of the envelope
        // when the parties are judged against it — otherwise a relationship it still carries would
        // read as a reason to keep a party whose only role was on it. A party also in this batch is
        // dropped: its own removal has already dealt with it.
        strandedParties.removeAll(ids);
        return new List<Id>(
            unlinkDroppedPartiesAndDeleteIfUnused(strandedParties, envelopeId)
        );
    }

    // Takes related parties the wizard no longer holds out of an envelope, and deletes the ones
    // nothing else uses. Called by whoever has already removed exactly the relationships that went:
    // the related-party reconcile, which drops the one the user cleared, and an outline removal, which
    // drops the ones the removed record held. Neither may run deleteRelatedPartyLinks on the parties
    // themselves — that would also strip the roles they still hold on other entities in this envelope.
    //
    // A record still serving this envelope keeps its link: losing one role says nothing about the
    // others, and unlinking it would take it off the Household Outline while it is still a party.
    // Everything past that filter is judged on the same terms as an outline removal.
    //
    // Returns the ids actually taken out of the envelope, so a caller rendering the outline can drop
    // exactly those rows instead of working out which ones went.
    public static Set<Id> unlinkDroppedPartiesAndDeleteIfUnused(Set<Id> ids, Id envelopeId) {
        if (ids == null || ids.isEmpty()) {
            return new Set<Id>();
        }
        Set<Id> toUnlink = new Set<Id>(ids);
        toUnlink.removeAll(idsStillUsedInEnvelope(ids, envelopeId));
        unlinkAndDeleteIfUnused(toUnlink, envelopeId);
        return toUnlink;
    }

    // Unlink from one envelope, then delete whatever nothing references any more. Shared by the
    // outline removal above and the related-party reconcile, so the two cannot drift apart.
    private static void unlinkAndDeleteIfUnused(Set<Id> ids, Id envelopeId) {
        if (ids == null || ids.isEmpty()) {
            return;
        }
        deleteEnvelopeLinks(ids, envelopeId);

        // Asked after the links above are gone, so the record is judged on what remains rather than on
        // the envelope it is being removed from.
        Set<Id> unused = idsNoLongerInUse(ids);
        if (unused.isEmpty()) {
            return;
        }
        deleteUnusedRecords(unused);
    }

    // Of the given records, the ones this envelope still has a reason to hold: they play a
    // related-party role on a member it contains, or an ownership role on one of its Financial
    // Accounts. Scoped to this envelope's contents on purpose — a role held only on an entity another
    // envelope owns is not a reason for this one to keep the record.
    private static Set<Id> idsStillUsedInEnvelope(Set<Id> ids, Id envelopeId) {
        Set<Id> stillUsed = new Set<Id>();
        if (ids == null || ids.isEmpty() || envelopeId == null) {
            return stillUsed;
        }
        Set<Id> entityIds = accountIdsInEnvelope(envelopeId);
        if (!entityIds.isEmpty()) {
            for (Account_Account_Relationship__c relation : [
                SELECT Related_Account__c
                FROM Account_Account_Relationship__c
                WHERE Related_Account__c IN :ids
                AND Account__c IN :entityIds
                AND (Roles__c != NULL OR Reciprocal_Role__c != NULL)
            ]) {
                stillUsed.add(relation.Related_Account__c);
            }
        }
        Set<Id> financialAccountIds = financialAccountIdsInEnvelope(envelopeId);
        if (!financialAccountIds.isEmpty()) {
            for (Financial_Account_Role__c role : [
                SELECT Account__c
                FROM Financial_Account_Role__c
                WHERE Account__c IN :ids
                AND Financial_Account__c IN :financialAccountIds
            ]) {
                stillUsed.add(role.Account__c);
            }
        }
        return stillUsed;
    }

    // The Financial Accounts this envelope holds, used to scope the ownership check above.
    private static Set<Id> financialAccountIdsInEnvelope(Id envelopeId) {
        Set<Id> financialAccountIds = new Set<Id>();
        for (Envelope_Content__c content : [
            SELECT Wizard_Financial_Account__c
            FROM Envelope_Content__c
            WHERE Envelope__c = :envelopeId AND Wizard_Financial_Account__c != NULL
        ]) {
            financialAccountIds.add(content.Wizard_Financial_Account__c);
        }
        return financialAccountIds;
    }

    // Drop the related-party relationships the removed records take part in — either as the entity
    // whose parties they are, or as the party itself. Scoped to relationships whose other side is in
    // this envelope, so removing someone here cannot strip a role they hold on an entity that only
    // another envelope uses. All of a person's roles on one entity live in a single record's Roles__c,
    // so this removes one row per (entity, person) pair however many roles it carried.
    //
    // Returns the people left without the role that put them in this envelope: the party side of the
    // relationships actually deleted. Only that direction — where the removed record was itself the
    // party, the counterpart is an entity that stays, and unlinking it would take a member off the
    // outline for holding a party that left. A relationship left in place reports nobody, since the
    // role it carries is untouched.
    private static Set<Id> deleteRelatedPartyLinks(Set<Id> ids, Id envelopeId) {
        // Null means "no envelope context", which the check below reads as "do not narrow".
        Set<Id> scope = null;
        if (envelopeId != null) {
            scope = accountIdsInEnvelope(envelopeId);
        }
        Set<Id> strandedParties = new Set<Id>();
        List<Account_Account_Relationship__c> toDelete = new List<Account_Account_Relationship__c>();
        for (Account_Account_Relationship__c relation : [
            SELECT Id, Account__c, Related_Account__c
            FROM Account_Account_Relationship__c
            WHERE
                RecordType.DeveloperName = :RELATED_PARTY_RECORD_TYPE
                AND (Account__c IN :ids OR Related_Account__c IN :ids)
        ]) {
            // The side that is not being removed. When both sides are being removed the relationship
            // goes either way.
            Id counterpart = ids.contains(relation.Account__c)
                ? relation.Related_Account__c
                : relation.Account__c;
            if (scope == null || counterpart == null || scope.contains(counterpart)) {
                toDelete.add(relation);
                if (ids.contains(relation.Account__c) && relation.Related_Account__c != null) {
                    strandedParties.add(relation.Related_Account__c);
                }
            }
        }
        if (!toDelete.isEmpty()) {
            delete toDelete;
        }
        return strandedParties;
    }

    // The member accounts this envelope holds, used to scope the relationship cleanup above.
    private static Set<Id> accountIdsInEnvelope(Id envelopeId) {
        Set<Id> accountIds = new Set<Id>();
        for (Envelope_Content__c content : [
            SELECT Account__c
            FROM Envelope_Content__c
            WHERE Envelope__c = :envelopeId AND Account__c != NULL
        ]) {
            accountIds.add(content.Account__c);
        }
        return accountIds;
    }

    // Unlink the records from this envelope only. The envelope predicate is what keeps a removal in
    // one envelope from stripping the record out of every other envelope that holds it.
    private static void deleteEnvelopeLinks(Set<Id> ids, Id envelopeId) {
        List<Envelope_Content__c> links = new List<Envelope_Content__c>();
        if (envelopeId == null) {
            links = [
                SELECT Id
                FROM Envelope_Content__c
                WHERE
                    Account__c IN :ids
                    OR Wizard_Financial_Account__c IN :ids
                    OR Service__c IN :ids
            ];
        } else {
            links = [
                SELECT Id
                FROM Envelope_Content__c
                WHERE
                    Envelope__c = :envelopeId
                    AND (Account__c IN :ids
                    OR Wizard_Financial_Account__c IN :ids
                    OR Service__c IN :ids)
            ];
        }
        if (!links.isEmpty()) {
            delete links;
        }
    }

    // The records nothing references any more, and so are safe to delete. A record is still in use
    // when another envelope holds it, when it holds a role on someone's Financial Account, or when
    // something points at it in a relationship carrying an actual role.
    //
    // Only references *into* the record count. A record's own children do not keep it alive, or
    // nothing would ever be deletable: every Financial Account has owner roles, and every entity has
    // its own related parties. Those are removed with the record below. The household-membership
    // relationship is excluded for the same reason — every member has one (see linkMemberToHousehold)
    // and it carries neither Roles__c nor Reciprocal_Role__c.
    private static Set<Id> idsNoLongerInUse(Set<Id> ids) {
        Set<Id> inUse = new Set<Id>();
        for (Envelope_Content__c content : [
            SELECT Account__c, Wizard_Financial_Account__c, Service__c
            FROM Envelope_Content__c
            WHERE
                Account__c IN :ids
                OR Wizard_Financial_Account__c IN :ids
                OR Service__c IN :ids
        ]) {
            inUse.add(content.Account__c);
            inUse.add(content.Wizard_Financial_Account__c);
            inUse.add(content.Service__c);
        }
        // The person side only: a role row belonging to a Financial Account being removed is that
        // account's own owner list, not a reference to it.
        for (Financial_Account_Role__c role : [
            SELECT Account__c
            FROM Financial_Account_Role__c
            WHERE Account__c IN :ids
        ]) {
            inUse.add(role.Account__c);
        }
        // The party side only: rows where the record is the entity are the parties it holds.
        for (Account_Account_Relationship__c relation : [
            SELECT Related_Account__c
            FROM Account_Account_Relationship__c
            WHERE
                Related_Account__c IN :ids
                AND (Roles__c != NULL OR Reciprocal_Role__c != NULL)
        ]) {
            inUse.add(relation.Related_Account__c);
        }
        Set<Id> unused = new Set<Id>();
        for (Id recordId : ids) {
            if (!inUse.contains(recordId)) {
                unused.add(recordId);
            }
        }
        return unused;
    }

    // Delete records nothing references, together with everything saveEntity created for them. Every
    // lookup pointing at Account clears rather than cascades (deleteConstraint SetNull), so without
    // this the rows would survive with null lookups and accumulate as orphans. Financial_Account_Role__c
    // is master-detail and cascades on its own.
    private static void deleteUnusedRecords(Set<Id> ids) {
        List<Required_Documents__c> documents = [
            SELECT Id
            FROM Required_Documents__c
            WHERE Person__c IN :ids OR Business__c IN :ids OR Trust__c IN :ids
                OR Financial_Account__c IN :ids
        ];
        Set<Id> documentIds = new Map<Id, Required_Documents__c>(documents).keySet();

        List<Signee__c> signees = [
            SELECT Id
            FROM Signee__c
            WHERE Account__c IN :ids OR Required_Document__c IN :documentIds
        ];
        if (!signees.isEmpty()) {
            delete signees;
        }

        // Whatever is left pointing at these records: the documents' envelope links, plus any link the
        // steps above left behind (an unscoped removal, or a link in another envelope that turned out
        // not to keep the record alive).
        List<Envelope_Content__c> links = [
            SELECT Id
            FROM Envelope_Content__c
            WHERE
                Account__c IN :ids
                OR Wizard_Financial_Account__c IN :ids
                OR Service__c IN :ids
                OR Required_Document__c IN :documentIds
        ];
        if (!links.isEmpty()) {
            delete links;
        }
        if (!documents.isEmpty()) {
            delete documents;
        }

        // The household-membership relationships, which idsNoLongerInUse deliberately ignored.
        List<Account_Account_Relationship__c> relations = [
            SELECT Id
            FROM Account_Account_Relationship__c
            WHERE Account__c IN :ids OR Related_Account__c IN :ids
        ];
        if (!relations.isEmpty()) {
            delete relations;
        }

        // A record that is already gone — deleted in another session, or named by an outline row the
        // client had gone stale on — still reads as unused above, since nothing can reference what is
        // not there. Deleting it a second time throws ENTITY_IS_DELETED and takes the whole removal
        // down with it, so the ids are narrowed to the ones that still exist. The sweeps above need no
        // such guard: their queries return nothing for a record that has gone.
        List<sObject> recordsToDelete = new List<sObject>();
        for(Id recordId : existingIds(ids)){
            recordsToDelete.add(recordId.getSObjectType().newSObject(recordId));
        }
        if (!recordsToDelete.isEmpty()) {
            delete recordsToDelete;
        }
    }

    // Of the given ids, the ones whose record still exists. The set mixes object types — an outline
    // removal can carry an Account, a Financial_Account__c or a Service__c — so they are grouped and
    // asked for one type at a time. The type name comes from the id's own describe, never from input.
    private static Set<Id> existingIds(Set<Id> ids) {
        Set<Id> alive = new Set<Id>();
        if (ids == null || ids.isEmpty()) {
            return alive;
        }
        Map<Schema.SObjectType, List<Id>> idsByType = new Map<Schema.SObjectType, List<Id>>();
        for (Id recordId : ids) {
            Schema.SObjectType objectType = recordId.getSObjectType();
            if (!idsByType.containsKey(objectType)) {
                idsByType.put(objectType, new List<Id>());
            }
            idsByType.get(objectType).add(recordId);
        }
        for (Schema.SObjectType objectType : idsByType.keySet()) {
            List<Id> ofType = idsByType.get(objectType);
            String query =
                'SELECT Id FROM ' +
                objectType.getDescribe().getName() +
                ' WHERE Id IN :ofType';
            for (sObject row : Database.query(query)) {
                alive.add(row.Id);
            }
        }
        return alive;
    }
    
    public class UserPreferenceWrapper {
        @AuraEnabled public String wizardViewPreference;
        @AuraEnabled public String relationshipToFirm;
        @AuraEnabled public String licenseType;

        public UserPreferenceWrapper(String wizardViewPreference, String relationshipToFirm, String licenseType) {
            this.wizardViewPreference = wizardViewPreference;
            this.relationshipToFirm = relationshipToFirm;
            this.licenseType = licenseType;
        }
    }
    @AuraEnabled(cacheable=false)
    public static HouseholdMembersAndAccountsWrapper getHouseholdMembersAndAccounts(Id householdId, Id envelopeId) {
        if (householdId == null) {
            throw new AuraHandledException('Household ID is required');
        }
        
        try {
            // Financial Accounts and Services linked to this envelope via Envelope_Content. Including
            // these means a record whose Household__c doesn't match the household (or is unset) still
            // loads, so the outline follows the envelope's contents, not only the household roster.
            Set<Id> envelopeFinAccountIds = new Set<Id>();
            Set<Id> envelopeServiceIds = new Set<Id>();
            if (envelopeId != null) {
                for (Envelope_Content__c ec : [
                    SELECT Wizard_Financial_Account__c, Service__c
                    FROM Envelope_Content__c
                    WHERE Envelope__c = :envelopeId
                    AND (Wizard_Financial_Account__c != null OR Service__c != null)
                    WITH USER_MODE
                ]) {
                    if (ec.Wizard_Financial_Account__c != null) {
                        envelopeFinAccountIds.add(ec.Wizard_Financial_Account__c);
                    }
                    if (ec.Service__c != null) {
                        envelopeServiceIds.add(ec.Service__c);
                    }
                }
            }
            
            List<Financial_Account__c> finAccounts = [
                SELECT ID, Name, Registration_Type__c, Rep_Code__c, Custodian__c, Primary_Owner__c, Product_Type__c, DPI__c, BD_or_RIA__c, Managed_Account_Platform__c, Submitted__c
                FROM Financial_Account__c
                WHERE Household__c = :householdId OR Id IN :envelopeFinAccountIds
                WITH USER_MODE
            ];
            
            List<Service__c> services = [
                SELECT Id, Name, Type__c, Submitted__c
                FROM Service__c
                WHERE Household__c = :householdId OR Id IN :envelopeServiceIds
                WITH USER_MODE
            ];
            
            // Every member (person, business, trust) is linked to the household via
            // Account_Account_Relationship__c.
            List<Account_Account_Relationship__c> accountRelationships = [
                SELECT Related_Account__c,
                Related_Account__r.Name,
                Related_Account__r.FirstName,
                Related_Account__r.LastName,
                Related_Account__r.RecordType.DeveloperName,
                Related_Account__r.RecordTypeId,
                Related_Account__r.Type,
                Related_Account__r.Submitted__c,
                Related_Account__r.BillingStreet,
                Related_Account__r.BillingCity,
                Related_Account__r.BillingStateCode,
                Related_Account__r.BillingPostalCode,
                Related_Account__r.PersonEmail,
                Related_Account__r.PersonMobilePhone,
                Related_Account__r.PersonBirthdate,
                Related_Account__r.No_Reportable_Beneficial_Owners__c
                FROM Account_Account_Relationship__c
                WHERE Account__c = :householdId
                AND Related_Account__c != NULL
                WITH USER_MODE
            ];
            
            return transformToHouseholdMembersAndAccounts(
                accountRelationships,
                finAccounts,
                services,
                envelopeId
            );
            
        } catch (QueryException e) {
            throw new AuraHandledException('Error querying household members: ' + e.getMessage());
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving household members: ' + e.getMessage());
        }
    }
    
    
    // Records a submitted member's edits on an Account Servicing approval case instead of the
    // person record. Repeated edits accumulate on the account's open principal-review case; once
    // that case closes, the next edit opens a fresh one with a new original-values snapshot.
    @AuraEnabled
    public static void saveProposedCase(
        Map<String, Object> originalvalues,
        Map<String, Object> proposedValue,
        Id accountId,
        Id envelopeId
    ) {
        if (proposedValue == null || proposedValue.isEmpty() || accountId == null) {
            return;
        }
        
        // Proposed values are validated against the Account source-field rules before they land on
        // the review case — a malformed change request just moves bad data to the approver.
        // Original values are existing record state and are never validated.
        WizardFieldValidator.enforce('Account', proposedValue);
        
        // A member action item raised from the outline is the same record type on the same member,
        // but it carries a Type and owns its own original snapshot. Excluding typed cases keeps this
        // upsert from adopting one and overwriting a request the approver is already reviewing.
        List<Case> cases = [
            SELECT Id
            FROM Case
            WHERE AccountId = :accountId
            AND RecordType.DeveloperName = :PRINCIPAL_REVIEW_RECORD_TYPE
            AND IsClosed = false
            AND Type = null
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        
        Boolean isNewCase = cases.isEmpty();
        Case cse;
        
        if (isNewCase) {
            cse = new Case();
            cse.AccountId = accountId;
            cse.RecordTypeId = principalReviewRecordTypeId();
            cse.Status = 'New';
            cse.Origin = 'Wizard';
            cse.Subject = 'Person Account Requested Changes';
            cse.DoNotCalc__c = true;
            // The household is the envelope's, not the member's: a member Account has no household
            // lookup of its own, matching the member action case in EnvelopeActionCaseController.
            cse.Household__c = EnvelopeHouseholdResolver.resolveHouseholdId(envelopeId);
        } else {
            cse = cases[0];
        }
        
        mapAccountFields(cse, originalvalues, proposedValue, isNewCase);
        
        if (isNewCase) {
            insert cse;
        } else {
            update cse;
        }
    }
    
    // The Case record type every principal-review request lands on. Resolved from the describe
    // rather than configuration so the one developer name is the single source, shared by the
    // proposed-case upsert here and the member action items EnvelopeActionCaseController raises.
    private static final String PRINCIPAL_REVIEW_RECORD_TYPE = 'Account_Servicing_Principal_Review';

    public static Id principalReviewRecordTypeId() {
        return Schema.SObjectType.Case
            .getRecordTypeInfosByDeveloperName()
            .get(PRINCIPAL_REVIEW_RECORD_TYPE)
            .getRecordTypeId();
    }

    // Take the baseline half of a review case's original/proposed pairs from a member's current
    // Account values. Called once, as the case is built, so the approver's comparison point cannot
    // drift while the request is open.
    public static void seedOriginalValues(Case cse, Map<String, Object> accountValues) {
        mapAccountFields(cse, accountValues, null, true);
    }

    // Record a submitted member's edits on an action item's own review case. The counterpart to
    // saveProposedCase for the wizard's member action items: the case already exists and is
    // addressed by its Id, so no case is resolved or opened here, and the original snapshot taken at
    // creation is left untouched.
    //
    // The payload is the whole interview, not the edited subset — a member action opens prefilled
    // with the member's current values, so most of what arrives matches the snapshot. Each field is
    // compared against its own original and only a genuine difference is proposed; a value edited
    // back to what it was clears its proposed field again. That is what keeps the case readable as a
    // change request rather than a copy of the form, and it holds however much the client sends.
    //
    // accountId names the member whose change the case records. Not read yet: it is reserved for
    // the metadata-driven rewrite (Envelope_Field__mdt 'Proposed Changes'), where the member's
    // current Account values become the comparison point in place of the frozen case snapshot.
    // The client already sends it, so the call contract is final ahead of that rewrite.
    @AuraEnabled
    public static void saveProposedCaseFields(
        Id caseId,
        Id accountId,
        Map<String, Object> proposedValues
    ) {
        if (caseId == null || proposedValues == null || proposedValues.isEmpty()) {
            return;
        }

        // Same backstop as saveProposedCase: the values describe a change to an Account, so they are
        // validated against the Account source-field rules before they land on the review case.
        WizardFieldValidator.enforce('Account', proposedValues);

        Map<String, AccountCaseFieldMapping.CaseFieldMapping> mappings =
            new Map<String, AccountCaseFieldMapping.CaseFieldMapping>();
        Set<String> selectFields = new Set<String>{ 'Id' };
        for (String accountField : proposedValues.keySet()) {
            AccountCaseFieldMapping.CaseFieldMapping mapping =
                AccountCaseFieldMapping.ACCOUNT_TO_CASE_FIELD_MAPPING.get(accountField);
            if (mapping == null) {
                continue;
            }
            mappings.put(accountField, mapping);
            selectFields.add(mapping.originalCaseField);
            selectFields.add(mapping.proposedCaseField);
        }
        if (mappings.isEmpty()) {
            return;
        }

        String soql = 'SELECT ' + String.join(new List<String>(selectFields), ', ') +
            ' FROM Case WHERE Id = :caseId LIMIT 1';
        List<SObject> existing = Database.query(soql);
        if (existing.isEmpty()) {
            throw new AuraHandledException('The review case could not be found.');
        }
        SObject current = existing[0];

        Case cse = new Case(Id = caseId);
        Integer changedFields = 0;
        for (String accountField : mappings.keySet()) {
            AccountCaseFieldMapping.CaseFieldMapping mapping = mappings.get(accountField);
            String original = blankToNull(
                (String) current.get(mapping.originalCaseField));
            String proposed = blankToNull(
                asCaseText(proposedValues.get(accountField), mapping.proposedCaseField));
            // Matching the original is not a change, so the proposed field is cleared rather than
            // echoing the baseline back at the approver.
            String desired = sameValue(accountField, proposed, original) ? null : proposed;
            if (sameValue(
                accountField, desired, blankToNull((String) current.get(mapping.proposedCaseField)))
            ) {
                continue;
            }
            cse.put(mapping.proposedCaseField, desired);
            changedFields++;
        }
        // Nothing moved — skip the DML rather than touching the record's audit fields on an autosave
        // tick that only resent values the case already holds.
        if (changedFields == 0) {
            return;
        }

        try {
            update cse;
        } catch (DmlException e) {
            throw new AuraHandledException('Update failed: ' + e.getDmlMessage(0));
        }
    }

    // Cached Account describe, for typing values read back off a review case.
    private static Map<String, Schema.SObjectField> accountFieldsCache;

    private static Map<String, Schema.SObjectField> accountFields() {
        if (accountFieldsCache == null) {
            accountFieldsCache = Account.SObjectType.getDescribe().fields.getMap();
        }
        return accountFieldsCache;
    }

    // A review case stores every answer as Text, but the interview reading them back is the member's
    // own Account form and expects the shapes an Account read returns: a list for a multi-select, a
    // real Date, a Boolean, a number. A raw string reaches those controls as an unusable value — a
    // dual listbox iterates its value, a date input rejects anything but ISO — so each is coerced
    // back against its source field's own type, matching what
    // FieldDetailController.getRecordValuesForType would have returned. A value that will not parse
    // falls back to the stored text rather than failing the whole read.
    private static Object typedAccountValue(String accountField, String text) {
        if (String.isBlank(text)) {
            return null;
        }
        Schema.SObjectField field = accountFields().get(accountField.toLowerCase());
        if (field == null) {
            return text;
        }
        Schema.DisplayType fieldType = field.getDescribe().getType();
        try {
            if (fieldType == Schema.DisplayType.MULTIPICKLIST) {
                List<String> selected = new List<String>();
                // Split tolerates the '; ' the writer joins with and the bare ';' the platform uses.
                for (String part : text.split(';')) {
                    if (String.isNotBlank(part)) {
                        selected.add(part.trim());
                    }
                }
                return selected;
            }
            if (fieldType == Schema.DisplayType.BOOLEAN) {
                return text.equalsIgnoreCase('true');
            }
            if (fieldType == Schema.DisplayType.DATE) {
                // Accepts both the ISO date written now and the 'yyyy-MM-dd 00:00:00' form older
                // records carry.
                return Date.valueOf(text);
            }
            if (fieldType == Schema.DisplayType.DATETIME) {
                return DateTime.valueOf(text);
            }
            // Every numeric type resolves to Decimal so the two sides of a comparison are always the
            // same type and scale never decides the answer.
            if (fieldType == Schema.DisplayType.CURRENCY ||
                fieldType == Schema.DisplayType.DOUBLE ||
                fieldType == Schema.DisplayType.PERCENT ||
                fieldType == Schema.DisplayType.INTEGER ||
                fieldType == Schema.DisplayType.LONG
            ) {
                return Decimal.valueOf(text);
            }
        } catch (Exception e) {
            return text;
        }
        return text;
    }

    private static String blankToNull(String value) {
        return String.isBlank(value) ? null : value;
    }

    // Whether two stored representations of the same field mean the same answer. Compared on the
    // field's own type rather than as raw text, because the two sides are written from different
    // places: the original snapshot stringifies the Account's typed value (a currency reaches it as
    // '500000.00') while the proposal stringifies what the interview sent ('500000'). Comparing those
    // as text would propose an untouched number on every save.
    //
    // Text is compared case-sensitively — Apex's == is case-insensitive for String, which would
    // silently drop an edit that only changes casing.
    private static Boolean sameValue(String accountField, String left, String right) {
        if (left == null || right == null) {
            return left == null && right == null;
        }
        Object leftValue = typedAccountValue(accountField, left);
        Object rightValue = typedAccountValue(accountField, right);
        if (leftValue instanceof Decimal && rightValue instanceof Decimal) {
            return (Decimal) leftValue == (Decimal) rightValue;
        }
        if (leftValue instanceof String && rightValue instanceof String) {
            return ((String) leftValue).equals((String) rightValue);
        }
        return String.valueOf(leftValue) == String.valueOf(rightValue);
    }

    // The values a member action item's interview prefills from, keyed by Case id and then by
    // Account field API name — the form is the member's own Account interview, so it cannot read the
    // Case's own field names.
    //
    // Each field resolves to its proposed value when one has been entered and its original otherwise,
    // so a freshly raised request opens showing the member's current data and a revisited one shows
    // the edits already made. The proposed half stays sparse: only fields actually changed are ever
    // written to it.
    //
    // Uncacheable, like getRecordValuesForType: the record is the source of truth for the interview
    // and a cached read would show a stale value after the edit that changed it.
    @AuraEnabled
    public static Map<Id, Map<String, Object>> getProposedCaseValues(List<Id> caseIds) {
        return readCaseFieldPairs(caseIds, false);
    }

    // The baseline half of the same pairs: what each field held on the member when the request was
    // raised, keyed by Case id and then by Account field API name. The interview compares its
    // current answers against this to mark the fields the request actually changes, which is the
    // same comparison saveProposedCaseFields makes before it writes a proposal — so the marking and
    // the stored change set always agree.
    //
    // Every mapped field the Case can hold is reported, null included: an absent key means the
    // field is not part of the review pairs at all, while a null one means it was blank. The two
    // are not interchangeable — filling a blank field is a change, editing an untracked one is not.
    //
    // Uncacheable for the same reason as getProposedCaseValues: the record is the source of truth.
    @AuraEnabled
    public static Map<Id, Map<String, Object>> getOriginalCaseValues(List<Id> caseIds) {
        return readCaseFieldPairs(caseIds, true);
    }

    // The shared read behind both accessors: one query over the review pairs, returning either the
    // baseline half alone or the resolved prefill value (proposed when entered, original otherwise).
    private static Map<Id, Map<String, Object>> readCaseFieldPairs(
        List<Id> caseIds,
        Boolean baselineOnly
    ) {
        Map<Id, Map<String, Object>> result = new Map<Id, Map<String, Object>>();
        if (caseIds == null || caseIds.isEmpty()) {
            return result;
        }

        Map<String, Schema.SObjectField> caseFields = Case.SObjectType.getDescribe().fields.getMap();
        Set<String> selectFields = new Set<String>{ 'Id' };
        for (AccountCaseFieldMapping.CaseFieldMapping mapping :
            AccountCaseFieldMapping.ACCOUNT_TO_CASE_FIELD_MAPPING.values()
        ) {
            if (caseFields.containsKey(mapping.originalCaseField.toLowerCase())) {
                selectFields.add(mapping.originalCaseField);
            }
            // The proposed half is only ever read to resolve a prefill value.
            if (!baselineOnly && caseFields.containsKey(mapping.proposedCaseField.toLowerCase())) {
                selectFields.add(mapping.proposedCaseField);
            }
        }

        String soql = 'SELECT ' + String.join(new List<String>(selectFields), ', ') +
            ' FROM Case WHERE Id IN :caseIds';
        for (SObject record : Database.query(soql)) {
            Map<String, Object> values = new Map<String, Object>();
            for (String accountField : AccountCaseFieldMapping.ACCOUNT_TO_CASE_FIELD_MAPPING.keySet()) {
                AccountCaseFieldMapping.CaseFieldMapping mapping =
                    AccountCaseFieldMapping.ACCOUNT_TO_CASE_FIELD_MAPPING.get(accountField);
                Boolean holdsOriginal = selectFields.contains(mapping.originalCaseField);
                Object original = holdsOriginal ? record.get(mapping.originalCaseField) : null;
                if (baselineOnly) {
                    if (holdsOriginal) {
                        values.put(
                            accountField,
                            original == null
                                ? null
                                : typedAccountValue(accountField, String.valueOf(original))
                        );
                    }
                    continue;
                }
                Object proposed = selectFields.contains(mapping.proposedCaseField)
                    ? record.get(mapping.proposedCaseField)
                    : null;
                Object value = proposed == null || String.isBlank(String.valueOf(proposed))
                    ? original
                    : proposed;
                if (value != null) {
                    values.put(accountField, typedAccountValue(accountField, String.valueOf(value)));
                }
            }
            result.put((Id) record.get('Id'), values);
        }
        return result;
    }

    private static void mapAccountFields(
        Case cse,
        Map<String, Object> recordOld,
        Map<String, Object> recordNew,
        Boolean isNewCase
    ) {
        for (String accountField : AccountCaseFieldMapping.ACCOUNT_TO_CASE_FIELD_MAPPING.keySet()) {
            AccountCaseFieldMapping.CaseFieldMapping mapping =
                AccountCaseFieldMapping.ACCOUNT_TO_CASE_FIELD_MAPPING.get(accountField);
            
            if (recordNew != null && recordNew.containsKey(accountField)) {
                cse.put(mapping.proposedCaseField, asCaseText(recordNew.get(accountField), mapping.proposedCaseField));
            }
            
            // The original snapshot is written once, when the review case is opened; reuse keeps
            // it as the pre-review baseline the approver compares against.
            if (isNewCase &&
                recordOld != null &&
                recordOld.containsKey(accountField)) {
                    cse.put(mapping.originalCaseField, asCaseText(recordOld.get(accountField), mapping.originalCaseField));
                }
        }
    }
    
    // Form values arrive as deserialized JSON (strings, booleans, lists from multi-selects), but
    // every mapped Case field is Text — coerce to a string and clip to the field's length so one
    // long or multi-select value can't fail the whole save.
    private static String asCaseText(Object value, String caseField) {
        if (value == null) {
            return null;
        }
        String text;
        if (value instanceof List<Object>) {
            List<String> parts = new List<String>();
            for (Object item : (List<Object>) value) {
                parts.add(String.valueOf(item));
            }
            text = String.join(parts, '; ');
        } else if (value instanceof Date) {
            // A Date's default string form is 'yyyy-MM-dd 00:00:00', which reads back as a datetime
            // and is rejected by the interview's date control. Store the ISO date the form uses.
            text = String.valueOf(value).substringBefore(' ');
        } else {
            text = String.valueOf(value);
        }
        Schema.SObjectField field = Schema.SObjectType.Case.fields.getMap().get(caseField.toLowerCase());
        Integer maxLength = field == null ? 0 : field.getDescribe().getLength();
        return (maxLength > 0 && text.length() > maxLength) ? text.abbreviate(maxLength) : text;
    }
    
    /**
* Transforms Account_Account_Relationship__c records into the household members structure.
*
* @param accountRelationships List of Account_Account_Relationship__c records
* @return HouseholdMembersWrapper with categorized members
*/
    private static HouseholdMembersAndAccountsWrapper transformToHouseholdMembersAndAccounts(
        List<Account_Account_Relationship__c> accountRelationships,
        List<Financial_Account__c> finAccounts,
        List<Service__c> services,
        Id envelopeId
    ) {
        List<MemberData> clients = new List<MemberData>();
        List<MemberData> businesses = new List<MemberData>();
        List<MemberData> trusts = new List<MemberData>();
        List<MemberData> retirementPlans = new List<MemberData>();
        List<AccountData> accounts = new List<AccountData>();
        Set<Id> existingRecordIds = new Set<Id>();
        Set<Id> memberAccountIds = new Set<Id>();
        
        if (envelopeId != null) {
            for (Envelope_Content__c ec : [
                SELECT Account__c,
                Wizard_Financial_Account__c,
                Service__c,
                Account__r.Name,
                Account__r.FirstName,
                Account__r.LastName,
                Account__r.RecordType.DeveloperName,
                Account__r.RecordTypeId,
                Account__r.Type,
                Account__r.BillingStreet,
                Account__r.BillingCity,
                Account__r.BillingStateCode,
                Account__r.BillingPostalCode,
                Account__r.PersonEmail,
                Account__r.PersonMobilePhone,
                Account__r.PersonBirthdate
                FROM Envelope_Content__c
                WHERE Envelope__c = :envelopeId
            ]) {
                if (ec.Account__c != null) {
                    existingRecordIds.add(ec.Account__c);
                }
                if (ec.Wizard_Financial_Account__c != null) {
                    existingRecordIds.add(ec.Wizard_Financial_Account__c);
                }
                if (ec.Service__c != null) {
                    existingRecordIds.add(ec.Service__c);
                }
            }
        }
        Set<Id> candidateAccountIds = new Set<Id>();
        for (Account_Account_Relationship__c relation : accountRelationships) {
            if (relation.Related_Account__c != null) {
                candidateAccountIds.add(relation.Related_Account__c);
            }
        }
        Set<Id> candidateFinAccountIds = new Set<Id>();
        for (Financial_Account__c fa : finAccounts) {
            candidateFinAccountIds.add(fa.Id);
        }
        Set<Id> candidateServiceIds = new Set<Id>();
        for (Service__c svc : services) {
            candidateServiceIds.add(svc.Id);
        }
        Set<Id> linkedToAnyEnvelopeIds = new Set<Id>();
        Map<Id, String> pendingEnvelopeNameByAccountId = new Map<Id, String>();
        if (!candidateAccountIds.isEmpty() || !candidateFinAccountIds.isEmpty() || !candidateServiceIds.isEmpty()) {
            for (Envelope_Content__c ec : [
                SELECT Account__c, Wizard_Financial_Account__c, Service__c,
                       Envelope__c, Envelope__r.Name
                FROM Envelope_Content__c
                WHERE Account__c IN :candidateAccountIds
                OR Wizard_Financial_Account__c IN :candidateFinAccountIds
                OR Service__c IN :candidateServiceIds
            ]) {
                if (ec.Account__c != null) {
                    linkedToAnyEnvelopeIds.add(ec.Account__c);
                    if (ec.Envelope__c != envelopeId && !pendingEnvelopeNameByAccountId.containsKey(ec.Account__c)) {
                        pendingEnvelopeNameByAccountId.put(ec.Account__c, ec.Envelope__r.Name);
                    }
                }
                if (ec.Wizard_Financial_Account__c != null) {
                    linkedToAnyEnvelopeIds.add(ec.Wizard_Financial_Account__c);
                }
                if (ec.Service__c != null) {
                    linkedToAnyEnvelopeIds.add(ec.Service__c);
                }
            }
        }

        for (Account_Account_Relationship__c relation : accountRelationships) {
            if (relation.Related_Account__c == null || relation.Related_Account__r == null) {
                continue;
            }
            if (memberAccountIds.contains(relation.Related_Account__c)) {
                continue;
            }
            memberAccountIds.add(relation.Related_Account__c);

            Account relatedAccount = relation.Related_Account__r;
            String recordTypeName = relatedAccount.RecordType?.DeveloperName;
            MemberData member = createMemberDataFromAccount(relatedAccount);
            member.linkedToEnvelope = existingRecordIds.contains(relation.Related_Account__c);
            member.pendingEnvelopeName = pendingEnvelopeNameByAccountId.get(relation.Related_Account__c);
            addMemberByRecordType(
                member,
                recordTypeName,
                clients,
                businesses,
                trusts,
                retirementPlans
            );
        }
        
        // Envelope-linked member accounts not yet on the household roster (e.g. just created
        // via saveEntity before Account_Account_Relationship__c is visible to the caller).
        if (envelopeId != null) {
            for (Envelope_Content__c ec : [
                SELECT Account__c,
                Account__r.Name,
                Account__r.FirstName,
                Account__r.LastName,
                Account__r.RecordType.DeveloperName,
                Account__r.RecordTypeId,
                Account__r.Type,
                Account__r.BillingStreet,
                Account__r.BillingCity,
                Account__r.BillingStateCode,
                Account__r.BillingPostalCode,
                Account__r.PersonEmail,
                Account__r.PersonMobilePhone,
                Account__r.PersonBirthdate,
                Account__r.Submitted__c,
                Account__r.No_Reportable_Beneficial_Owners__c,
                Account__r.RecordType.Name
                FROM Envelope_Content__c
                WHERE Envelope__c = :envelopeId
                AND Account__c != NULL
                AND Account__r.RecordType.Name != 'Household'
            ]) {
                if (memberAccountIds.contains(ec.Account__c)) {
                    continue;
                }
                memberAccountIds.add(ec.Account__c);
                
                String recordTypeName = ec.Account__r.RecordType?.DeveloperName;
                MemberData member = createMemberDataFromAccount(ec.Account__r);
                member.linkedToEnvelope = true;
                addMemberByRecordType(
                    member,
                    recordTypeName,
                    clients,
                    businesses,
                    trusts,
                    retirementPlans
                );
            }
        }
        for(Financial_Account__c finAccount : finAccounts){
            if (!belongsInEnvelope(finAccount.Id, finAccount.Submitted__c, existingRecordIds, linkedToAnyEnvelopeIds)) {
                continue;
            }
            AccountData account = createAccountData(finAccount);
            accounts.add(account);
        }

        List<Service__c> scopedServices = new List<Service__c>();
        for(Service__c ser : services){
            if (!belongsInEnvelope(ser.Id, ser.Submitted__c, existingRecordIds, linkedToAnyEnvelopeIds)) {
                continue;
            }
            scopedServices.add(ser);
        }

        // Flag each client that has their own Required_Documents__c profile — these are
        // primary Individuals, not party-only members. The client uses this to keep them
        // as Individual even when they also play a related-party role on another member.
        Set<Id> clientAccountIds = new Set<Id>();
        for (MemberData c : clients) {
            clientAccountIds.add(c.id);
        }
        if (!clientAccountIds.isEmpty()) {
            Set<Id> idsWithProfile = new Set<Id>();
            for (Required_Documents__c rd : [
                SELECT Person__c
                FROM Required_Documents__c
                WHERE Person__c IN :clientAccountIds
            ]) {
                idsWithProfile.add(rd.Person__c);
            }
            for (MemberData c : clients) {
                c.hasClientProfile = idsWithProfile.contains(c.id);
            }
        }

        HouseholdMembersAndAccountsWrapper wrapper =
            new HouseholdMembersAndAccountsWrapper(clients, businesses, trusts, retirementPlans, accounts, scopedServices);
        wrapper.actionCases = readActionCases(envelopeId);
        return wrapper;
    }

    // The envelope's Account Action Items, so the outline renders them from records like every other
    // group rather than from the envelope-state blob — which is what lets a Case deleted elsewhere
    // disappear on the next load instead of leaving a row that can be neither edited nor removed.
    //
    // Scoped to the envelope's own links, deliberately unlike belongsInEnvelope's "linked OR
    // submitted" rule for the household's own records. An action item is raised against a household
    // record but is not part of the household's settled state: it belongs to the one envelope that
    // raised it, so a submitted case from a previous envelope must not surface on this one.
    //
    // The account/DPI mixed-interview case is excluded — it belongs to a Financial Account's own
    // interview (see saveAccountCaseInfo), not to an outline row of its own. It is identified by its
    // Financial Account being an account/DPI entity of this envelope (an Envelope_Content row links
    // the envelope to Wizard_Financial_Account__c), NOT by its Case Type: a DPI's Case is retyped from
    // its Product Type at submit (Financial_Account_TriggerHandler), so a value like
    // 'Purchase Alternative Investment' would otherwise be mistaken for an account action and rendered
    // as a stray card. The Type != 'Account Opening' filter stays as an additive guard for the
    // un-retyped case; the entity check is what makes the exclusion Type-independent.
    private static List<ActionCaseData> readActionCases(Id envelopeId) {
        List<ActionCaseData> actionCases = new List<ActionCaseData>();
        if (envelopeId == null) {
            return actionCases;
        }
        // The Financial Accounts that are account/DPI entities of this envelope. Their own
        // mixed-interview Cases are shown through the account row, never as action items.
        Set<Id> envelopeAccountFaIds = new Set<Id>();
        for (Envelope_Content__c ec : [
            SELECT Wizard_Financial_Account__c
            FROM Envelope_Content__c
            WHERE Envelope__c = :envelopeId AND Wizard_Financial_Account__c != null
        ]) {
            envelopeAccountFaIds.add(ec.Wizard_Financial_Account__c);
        }
        for (Case c : [
            SELECT Id, Type, Subject, Submitted__c,
                Wizard_Financial_Account__c, Wizard_Financial_Account__r.Name,
                AccountId, Account.Name
            FROM Case
            WHERE Id IN (
                SELECT Case__c FROM Envelope_Content__c WHERE Envelope__c = :envelopeId
            )
            AND Origin = :WIZARD_CASE_ORIGIN
            AND Type != :ACCOUNT_OPENING_CASE_TYPE
            ORDER BY CreatedDate ASC
        ]) {
            // The account/DPI's own interview Case, retyped from its Product Type — not an action item.
            if (c.Wizard_Financial_Account__c != null
                    && envelopeAccountFaIds.contains(c.Wizard_Financial_Account__c)) {
                continue;
            }
            ActionCaseData data = new ActionCaseData();
            data.id = c.Id;
            data.caseType = c.Type;
            data.subject = c.Subject;
            data.financialAccountId = c.Wizard_Financial_Account__c;
            // Dereferenced only when the lookup is set: an Additional Funding case opened before that
            // branch was completed carries no account, and reading through a null lookup throws.
            data.financialAccountName = c.Wizard_Financial_Account__c != null
                ? c.Wizard_Financial_Account__r.Name
                : null;
            // AccountId means different things by case type — the household for an account action,
            // the member itself for a member action — so it is passed through raw and the client
            // reads it only for the types whose parent is a member.
            data.accountId = c.AccountId;
            data.accountName = c.AccountId != null ? c.Account.Name : null;
            data.submitted = c.Submitted__c == true;
            actionCases.add(data);
        }
        return actionCases;
    }

    private static Boolean belongsInEnvelope(Id recordId, Boolean submitted, Set<Id> existingRecordIds, Set<Id> linkedToAnyEnvelopeIds) {
        return existingRecordIds.contains(recordId)
            || submitted == true
            || (!linkedToAnyEnvelopeIds.contains(recordId) && submitted != true);
    }
    
    private static void addMemberByRecordType(
        MemberData member,
        String recordTypeName,
        List<MemberData> clients,
        List<MemberData> businesses,
        List<MemberData> trusts,
        List<MemberData> retirementPlans
    ) {
        if (recordTypeName == 'PersonAccount' || recordTypeName == 'Individual') {
            clients.add(member);
        } else if (
            recordTypeName == 'Business'
        ) {
            businesses.add(member);
        } else if (
            recordTypeName == 'Trust'
        ) {
            trusts.add(member);
        } else if (recordTypeName == 'Retirement_Plan') {
            retirementPlans.add(member);
        } else {
            clients.add(member);
        }
    }
    
    private static MemberData createMemberDataFromAccount(Account accountRecord) {
        MemberData member = new MemberData();
        member.id = accountRecord.Id;
        member.entityId = accountRecord.Id;
        member.FirstName = accountRecord.FirstName;
        member.LastName = accountRecord.LastName;
        member.Name = accountRecord.Name;
        member.PersonEmail = accountRecord.PersonEmail;
        member.PersonMobilePhone = accountRecord.PersonMobilePhone;
        member.PersonBirthdate = accountRecord.PersonBirthdate;
        member.BillingStreet = accountRecord.BillingStreet;
        member.BillingCity = accountRecord.BillingCity;
        member.BillingStateCode = accountRecord.BillingStateCode;
        member.BillingPostalCode = accountRecord.BillingPostalCode;
        member.EntityType = accountRecord.Type;
        member.noReportableBeneficialOwners =
            accountRecord.No_Reportable_Beneficial_Owners__c;
        member.recordTypeId = accountRecord.RecordTypeId;
        member.accountType = accountRecord.Type;
        member.submitted = accountRecord.Submitted__c == true;
        return member;
    }
    
    private static AccountData createAccountData(Financial_Account__c finAccount) {
        AccountData act = new AccountData();
        
        // Core identifiers
        act.Id = finAccount.Id;
        act.Name = finAccount.Name;
        act.registrationType = finAccount.Registration_Type__c;
        act.custodian = finAccount.Custodian__c ;
        act.selectedRepCode = finAccount.Rep_Code__c;
        act.ownerMemberId = finAccount.Primary_Owner__c;
        act.bdProductType = finAccount.Product_Type__c;
        act.bdOrRia = finAccount.BD_or_RIA__c;
        act.managedAccountPlatform = finAccount.Managed_Account_Platform__c;
        act.isDpi = finAccount.DPI__c == true;
        act.submitted = finAccount.Submitted__c == true;
        
        return act;
    }
    
    @AuraEnabled
    public static void submitEnvelope(Id envelopeId){
        List<Account> accToUpdate = new List<Account>();
        List<Financial_Account__c> finAcctToUpdate = new List<Financial_Account__c>();
        List<Case> casesToUpdate = new List<Case>();
        List<Service__c> servicesToUpdate = new List<Service__c>();
        List<Envelope_Content__c> envelopeContentRecords = [SELECT Id, Account__c, Account__r.Submitted__c, Case__c, Case__r.Submitted__c,
                                                            Required_Document__c, 
                                                            Wizard_Financial_Account__c, Wizard_Financial_Account__r.Submitted__c, Service__c, Service__r.Submitted__c,
                                                            Envelope__r.Status__c FROM Envelope_Content__c WHERE Envelope__c =: envelopeId ];
        for(Envelope_Content__c e : envelopeContentRecords){
            if(e.Account__c != null && !e.Account__r.Submitted__c){
                Account newAcc = new Account(Id = e.Account__c, Submitted__c = true);
                accToUpdate.add(newAcc);
            } else if(e.Case__c != null && !e.Case__r.Submitted__c){
                Case newCase = new Case(Id = e.Case__c, Submitted__c = true);
                casesToUpdate.add(newCase);
            } else if(e.Wizard_Financial_Account__c != null){
                Financial_Account__c newFin = new Financial_Account__c(Id = e.Wizard_Financial_Account__c, Submitted__c = true);
                finAcctToUpdate.add(newFin);
            } else if(e.Service__c != null && !e.Service__r.Submitted__c){
                Service__c newService = new Service__c(Id = e.Service__c, Submitted__c = true);
                servicesToUpdate.add(newService);
            }
        }
        Envelope__c e = new Envelope__c(Id = envelopeId, Status__c = 'Complete');
        update e;
        if(!accToUpdate.isEmpty()){
            update accToUpdate;
        }
        if(!finAcctToUpdate.isEmpty()){
            update finAcctToUpdate;
        }
        if(!casesToUpdate.isEmpty()){
            update casesToUpdate;
        }
        if(!servicesToUpdate.isEmpty()){
            update servicesToUpdate;
        }
    }
    
    /**
* Wrapper class containing categorized household members.
*/
    public class HouseholdMembersAndAccountsWrapper {
        @AuraEnabled public List<MemberData> clients { get; set; }
        @AuraEnabled public List<MemberData> businesses { get; set; }
        @AuraEnabled public List<MemberData> trusts { get; set; }
        @AuraEnabled public List<MemberData> retirementPlans { get; set; }
        @AuraEnabled public List<AccountData> accounts { get; set; }
        @AuraEnabled public List<Service__c> services { get; set; }
        @AuraEnabled public List<ActionCaseData> actionCases { get; set; }

        public HouseholdMembersAndAccountsWrapper() {
            this.clients = new List<MemberData>();
            this.businesses = new List<MemberData>();
            this.trusts = new List<MemberData>();
            this.retirementPlans = new List<MemberData>();
            this.accounts = new List<AccountData>();
            this.services = new List<Service__c>();
            this.actionCases = new List<ActionCaseData>();
        }

        public HouseholdMembersAndAccountsWrapper(List<MemberData> clients, List<MemberData> businesses, List<MemberData> trusts, List<MemberData> retirementPlans, List<AccountData> accounts,List<Service__c> services) {
            this.clients = clients != null ? clients : new List<MemberData>();
            this.businesses = businesses != null ? businesses : new List<MemberData>();
            this.trusts = trusts != null ? trusts : new List<MemberData>();
            this.retirementPlans = retirementPlans != null ? retirementPlans : new List<MemberData>();
            this.accounts = accounts != null ? accounts : new List<AccountData>();
            this.services = services != null ? services : new List<Service__c>();
            this.actionCases = new List<ActionCaseData>();
        }
    }

    /**
* An action item — the Case raised from the outline's "+" against a submitted record. Against a
* Financial Account that is an Account Action Item (Third Party Money Movement, Account Closure,
* Additional Funding and the rest); against a household member it is a request to change the
* member's own fields (Edit Individual and its siblings).
* `caseType` is the Case's Type, which the client maps back to the action catalog token that keys
* the interview schema and titles the card. The parent is carried in whichever pair fits the type:
* `financialAccountId` for an account action, `accountId` for a member action.
*/
    public class ActionCaseData {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String caseType { get; set; }
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public Id financialAccountId { get; set; }
        @AuraEnabled public String financialAccountName { get; set; }
        @AuraEnabled public Id accountId { get; set; }
        @AuraEnabled public String accountName { get; set; }
        @AuraEnabled public Boolean submitted { get; set; }
    }
    
    /**
* Data transfer object representing a household member.
* Field names match exactly with envelopeFormMember.js for proper data binding.
*/
    public class MemberData {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String entityId { get; set; }
        @AuraEnabled public String FirstName { get; set; }
        @AuraEnabled public String Lastname { get; set; }
        @AuraEnabled public String Name { get; set; }
        @AuraEnabled public String PersonEmail { get; set; }
        @AuraEnabled public String PersonMobilePhone { get; set; }
        @AuraEnabled public Date PersonBirthdate { get; set; }
        @AuraEnabled public String TaxId { get; set; }
        @AuraEnabled public String BillingStreet { get; set; }
        @AuraEnabled public String BillingCity { get; set; }
        @AuraEnabled public String BillingStateCode { get; set; }
        @AuraEnabled public String BillingPostalCode { get; set; }
        @AuraEnabled public String PersonMailingStreet { get; set; }
        @AuraEnabled public String PersonMailingCity { get; set; }
        @AuraEnabled public String PersonMailingStateCode { get; set; }
        @AuraEnabled public String PersonMailingPostalCode { get; set; }
        @AuraEnabled public String FormationDate { get; set; }
        @AuraEnabled public String EntityType { get; set; }
        // The beneficial-owner affirmation, read back so the requirement stays met after a reload.
        // Apex identifiers cannot contain '__c', so this carries a camelCase name and the shell maps
        // it onto the field's api name when it seeds the interview draft.
        @AuraEnabled public Boolean noReportableBeneficialOwners { get; set; }
        @AuraEnabled public String EntityJurisdiction { get; set; }
        @AuraEnabled public String PrimaryTrustee { get; set; }
        @AuraEnabled public String recordTypeId { get; set; }
        @AuraEnabled public String accountType { get; set; }
        // Whether the member's Account has been submitted to the home office. The caller treats an
        // unsubmitted record as a still-editable draft (isNew) and a submitted one as locked.
        @AuraEnabled public Boolean submitted { get; set; }
        // True when this person has their own Required_Documents__c client profile — a primary
        // Individual added to the envelope, not just a related party on another member.
        @AuraEnabled public Boolean hasClientProfile { get; set; }
        @AuraEnabled public Boolean linkedToEnvelope { get; set; }
        @AuraEnabled public String pendingEnvelopeName { get; set; }
    }
    
    public class AccountData {
        @AuraEnabled public Id Id { get; set; }
        @AuraEnabled public String Name { get; set; }
        @AuraEnabled public String registrationType { get; set; }
        @AuraEnabled public String custodian { get; set; }
        @AuraEnabled public String selectedRepCode { get; set; }
        @AuraEnabled public String ownerMemberId { get; set; }
        @AuraEnabled public String bdProductType { get; set; }
        // Drives which conditional actions the "Add action item" dialog offers for the account:
        // Update Management Style (RIA only) and Update DMS Instructions (DMS platforms only).
        @AuraEnabled public String bdOrRia { get; set; }
        @AuraEnabled public String managedAccountPlatform { get; set; }
        // DPIs are Financial Accounts distinguished only by this flag; both come back in the
        // same list and the caller splits them into their respective groups.
        @AuraEnabled public Boolean isDpi { get; set; }
        // Whether the account has been submitted to the home office. The caller treats an
        // unsubmitted record as a still-editable draft (isNew) and a submitted one as locked.
        @AuraEnabled public Boolean submitted { get; set; }
    }
    
  /*  public class FieldInfo {
        @AuraEnabled public String fieldApiName;
        @AuraEnabled public String fieldLabel;
        @AuraEnabled public Boolean required;
        @AuraEnabled public Boolean keyDecision;
        @AuraEnabled public String requiredWhereStatement;
    }*/
}