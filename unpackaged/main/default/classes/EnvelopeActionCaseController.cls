public with sharing class EnvelopeActionCaseController {
    
    // What distinguishes one action item type from another at create time, for both the account and
    // the member catalogs. Everything else — the record it services, its household, the contact, the
    // advisor team, the origin and the record type — is shared, so it lives in the base builders.
    // The trade-instruction and management-style flags apply only to account actions.
    //
    // Values seeded here are only defaults. An account action's answers arrive later through
    // updateActionCaseFields, which writes whatever the metadata configures, so a field configured on
    // the type's Envelope_Field__mdt rows overwrites the seed as soon as the user answers it.
    private class ActionCaseSpec {
        String caseType;
        String subject;
        String description;
        // Whether the subject reads '<subject> for <account name>' rather than the subject alone.
        Boolean subjectNamesAccount = false;
        Boolean needsPrincipalReview = false;
        // A trade-instruction case is the container an Order_Ticket__c hangs off
        // (TradeInstructionController links Order_Ticket__c.Case__c to it), and is DMS by definition.
        Boolean opensTradeInstructions = false;
        Boolean recordsPreviousManagementStyle = false;

        ActionCaseSpec(String caseType, String subject, String description) {
            this.caseType = caseType;
            this.subject = subject;
            this.description = description;
        }
    }

    // The action types the wizard's "+" raises on a submitted Financial Account, keyed by the
    // Envelope_Field__mdt Type__c the client routes on. Adding a type the Type__c picklist already
    // carries is an entry here plus its metadata rows — no new create method.
    private static final Map<String, ActionCaseSpec> ACTION_CASE_SPECS = buildActionCaseSpecs();

    private static Map<String, ActionCaseSpec> buildActionCaseSpecs() {
        Map<String, ActionCaseSpec> specs = new Map<String, ActionCaseSpec>();

        specs.put('Additional Funding', new ActionCaseSpec(
            'Additional Funding',
            'Additional Funding',
            'This Financial Account was recently serviced (Additional Funding).'
        ));

        // The closure reason and its dependent fields are interview answers, not create-time input,
        // so they reach the Case through the metadata-driven update. Any resulting change to the
        // owner's own Account record is the back end's to make.
        specs.put('Account Closure', new ActionCaseSpec(
            'Account Closure',
            'Account Closure',
            'Please review all documentation and ensure that all necessary changes are made for this'+ ' Account Closure.'
        ));

        // The Case Type deliberately differs from the metadata type this is keyed by: the org keys on
        // 'Update DMS Instructions' (the Case and Order Ticket record pages,
        // Order_Ticket__c.Type_of_Request__c), while the interview is configured under 'Manage DMS
        // Instructions'. The client keeps the same split in ACCOUNT_TYPE_TO_CASE_TYPE.
        ActionCaseSpec dmsInstructions = new ActionCaseSpec(
            'Update DMS Instructions',
            'Update Trade Instructions',
            'Update Trade Instructions.'
        );
        dmsInstructions.subjectNamesAccount = true;
        dmsInstructions.opensTradeInstructions = true;
        specs.put('Manage DMS Instructions', dmsInstructions);

        ActionCaseSpec managementStyle = new ActionCaseSpec(
            'Change Management Style',
            'Change Management Style',
            'Change Management Style to DMS, with trade instructions.'
        );
        managementStyle.subjectNamesAccount = true;
        managementStyle.opensTradeInstructions = true;
        managementStyle.recordsPreviousManagementStyle = true;
        specs.put('Change Management Style', managementStyle);

        // The caseType is the Case.Type picklist value (singular); the spec is keyed by the
        // Envelope_Field__mdt Type__c / client sourceId, which is the plural 'Purchase Alternative
        // Investments'. The two vocabularies deliberately differ — the same split the DMS actions
        // carry — so the Case stores the singular Type while the interview schema resolves from the
        // plural. See ACCOUNT_TYPE_TO_CASE_TYPE in envelopeFormSchema.
        ActionCaseSpec purchaseAlts = new ActionCaseSpec(
            'Purchase Alternative Investment',
            'Purchase Alternative Investments',
            'Purchase Alternative Investments'
        );
        specs.put('Purchase Alternative Investments', purchaseAlts);

        return specs;
    }

    // The action types the wizard's "+" raises on a submitted household member, keyed by the catalog
    // token the client routes on. A submitted member is locked, so a change to it is recorded as a
    // request on this Case rather than written to the Account; the approver compares the original
    // snapshot taken here against the proposed values the interview writes later.
    //
    // Keyed by the catalog token rather than an Envelope_Field__mdt Type__c, because a member action
    // reuses the member's own interview schema instead of configuring one of its own.
    private static final Map<String, ActionCaseSpec> MEMBER_ACTION_CASE_SPECS =
        buildMemberActionCaseSpecs();

    private static Map<String, ActionCaseSpec> buildMemberActionCaseSpecs() {
        Map<String, ActionCaseSpec> specs = new Map<String, ActionCaseSpec>();
        specs.put('editIndividual', buildMemberActionCaseSpec(
            'Edit Individual',
            'Requested changes to this Individual, raised from the envelope wizard.'
        ));
        specs.put('editBusiness', buildMemberActionCaseSpec(
            'Edit Business',
            'Requested changes to this Business, raised from the envelope wizard.'
        ));
        specs.put('editTrust', buildMemberActionCaseSpec(
            'Edit Trust',
            'Requested changes to this Trust, raised from the envelope wizard.'
        ));
        specs.put('editRetirementPlan', buildMemberActionCaseSpec(
            'Edit Retirement Plan',
            'Requested changes to this Retirement Plan, raised from the envelope wizard.'
        ));
        return specs;
    }

    // Every member action shares the same shape: the Case Type doubles as the subject, the subject
    // names the member, and the request always needs a principal's review.
    private static ActionCaseSpec buildMemberActionCaseSpec(String caseType, String description) {
        ActionCaseSpec spec = new ActionCaseSpec(caseType, caseType, description);
        spec.subjectNamesAccount = true;
        spec.needsPrincipalReview = true;
        return spec;
    }

    // Opens the Case behind a member action item: a request to change a submitted member's Account
    // fields. Create only — the interview's answers are written by
    // WizardEnvelopeStateService.saveProposedCaseFields, which addresses this Case by its Id.
    //
    // Eligibility is enforced on the client, in the outline's "+" dialog, as it is for account
    // actions. An unrecognized token is a wiring error rather than a user action, so it throws
    // instead of returning empty — a silent empty id leaves the client holding an item with no record.
    @AuraEnabled
    public static String saveMemberActionCase(String accountId, String envelopeId, String sourceId) {
        if (String.isBlank(sourceId)) {
            throw new AuraHandledException('Action type is missing');
        }
        if (String.isBlank(accountId)) {
            throw new AuraHandledException('Member is missing');
        }
        ActionCaseSpec spec = MEMBER_ACTION_CASE_SPECS.get(sourceId);
        if (spec == null) {
            throw new AuraHandledException('Unsupported member action type: ' + sourceId);
        }

        SObject memberAccount = loadMemberAccount(accountId);
        Case newCase = buildBaseMemberActionCase(memberAccount, envelopeId);
        newCase.Type = spec.caseType;
        newCase.Subject = spec.subjectNamesAccount
            ? spec.subject + ' for ' + (String) memberAccount.get('Name')
            : spec.subject;
        newCase.Description = spec.description;
        if (spec.needsPrincipalReview) {
            newCase.Needs_Principal_Review__c = true;
        }

        // The baseline the approver compares against, frozen at the moment the request is raised.
        // Later edits only ever move the proposed half of each pair.
        WizardEnvelopeStateService.seedOriginalValues(newCase, mappedAccountValues(memberAccount));

        insert newCase;
        linkToEnvelope(newCase.Id, envelopeId);
        return newCase.Id;
    }

    // Whether the org's Account carries a field. The describe map is fetched once per transaction;
    // every member-snapshot decision goes through it, so what is queried and what is read back can
    // never disagree.
    private static Map<String, Schema.SObjectField> accountFieldsCache;

    private static Boolean accountHasField(String apiName) {
        if (accountFieldsCache == null) {
            accountFieldsCache = Account.SObjectType.getDescribe().fields.getMap();
        }
        return accountFieldsCache.containsKey(apiName.toLowerCase());
    }

    // The mapped Account fields this org actually has. A mapping entry for a field the org does not
    // carry is skipped rather than failing the query.
    private static Set<String> memberSnapshotFields() {
        Set<String> fields = new Set<String>();
        for (String apiName : AccountCaseFieldMapping.ACCOUNT_TO_CASE_FIELD_MAPPING.keySet()) {
            if (accountHasField(apiName)) {
                fields.add(apiName);
            }
        }
        return fields;
    }

    // The member's Account, carrying every field the original snapshot covers.
    private static SObject loadMemberAccount(String accountId) {
        Set<String> selectFields = new Set<String>{ 'Id' };
        for (String apiName : new List<String>{
            'Name', 'PersonContactId', 'Financial_Advisor_Team__c'
        }) {
            if (accountHasField(apiName)) {
                selectFields.add(apiName);
            }
        }
        selectFields.addAll(memberSnapshotFields());
        String soql = 'SELECT ' + String.join(new List<String>(selectFields), ', ') +
            ' FROM Account WHERE Id = :accountId LIMIT 1';
        List<SObject> records = Database.query(soql);
        if (records.isEmpty()) {
            throw new AuraHandledException('The member record could not be found.');
        }
        return records[0];
    }

    // The member's current values for the mapped fields only, in the shape the original snapshot
    // expects: keyed by Account field API name. Read straight off the record for the fields the query
    // selected, so a field the member has left empty is snapshotted as an empty original rather than
    // being silently omitted — the snapshot is the baseline a later edit is diffed against, and a
    // missing baseline would read as a change.
    private static Map<String, Object> mappedAccountValues(SObject memberAccount) {
        Map<String, Object> values = new Map<String, Object>();
        for (String apiName : memberSnapshotFields()) {
            values.put(apiName, memberAccount.get(apiName));
        }
        return values;
    }

    // The attribution a member action case carries. AccountId is the member itself — unlike an
    // account action case, where it is the household — so anything reading these cases back must
    // branch on the Case Type rather than assume what AccountId points at.
    private static Case buildBaseMemberActionCase(SObject memberAccount, String envelopeId) {
        Case newCase = new Case(
            AccountId = (Id) memberAccount.get('Id'),
            Origin = 'Wizard',
            RecordTypeId = WizardEnvelopeStateService.principalReviewRecordTypeId(),
            Status = 'New',
            DoNotCalc__c = true
        );
        // Person accounts expose a contact; business and trust members do not.
        if (accountHasField('PersonContactId')) {
            newCase.ContactId = (Id) memberAccount.get('PersonContactId');
        }
        if (accountHasField('Financial_Advisor_Team__c')) {
            newCase.Financial_Advisor_Team__c =
                (Id) memberAccount.get('Financial_Advisor_Team__c');
        }
        // The household is the envelope's, not the member's: a member Account has no household
        // lookup of its own, it is related to one through Account_Account_Relationship__c.
        newCase.Household__c = EnvelopeHouseholdResolver.resolveHouseholdId(envelopeId);
        return newCase;
    }

    // Opens the Case behind an Account Action Item, or updates one that already exists.
    //
    // The wizard's interview is metadata-driven and answers arrive keyed by real Case field API
    // names, so an update is handled generically up front and never reaches the create routing: a
    // payload carrying an `Id` is an update. Creates route through the spec table by the action's
    // Envelope_Field__mdt Type__c.
    //
    // Eligibility — which actions an account may raise, and only one of each — is enforced on the
    // client, in the outline's "+" dialog. An unrecognized type returns empty rather than throwing.
    @AuraEnabled
    public static String saveAccountActionCase(String financialAccountId, Map<String, Object> formData, String envelopeId, String sourceId) {
        if (String.isBlank(sourceId)) {
            throw new AuraHandledException('Action type is missing');
        }
        if (formData != null && formData.get('Id') != null) {
            return updateActionCaseFields(formData);
        }
        ActionCaseSpec spec = ACTION_CASE_SPECS.get(sourceId);
        if (spec == null) {
            return '';
        }
        return createActionCase(financialAccountId, envelopeId, spec);
    }

    // Apply an action item's interview answers to its Case. The payload is keyed by real Case field
    // API names (the wizard's Envelope_Field__mdt schema drives the form), so the assignment is
    // generic and every action type shares it — no per-type field mapping to keep in step with the
    // metadata. Keys that are not Case fields (the interview's composite draft keys) are ignored.
    private static String updateActionCaseFields(Map<String, Object> formData) {
        Id caseId = (Id) formData.get('Id');

        // Server-side backstop for the schema's configured format and bounds rules; the client
        // filters format-invalid values out of autosave payloads before they get here.
        WizardFieldValidator.enforce('Case', formData);

        Map<String, Schema.SObjectField> fieldMap =
            Case.SObjectType.getDescribe().fields.getMap();

        Case caseRecord = new Case(Id = caseId);
        List<String> failedKeys = new List<String>();
        Integer assignedFields = 0;
        for (String key : formData.keySet()) {
            if (key == 'Id' || !fieldMap.containsKey(key)) {
                continue;
            }
            try {
                caseRecord.put(key, WizardEnvelopeStateService.coerceFieldValue(
                    fieldMap.get(key), formData.get(key)));
                assignedFields++;
            } catch (Exception e) {
                System.debug('Error setting field ' + key + ': ' + e.getMessage());
                failedKeys.add(key);
            }
        }
        if (!failedKeys.isEmpty()) {
            throw new AuraHandledException(
                'These fields could not be saved: ' + String.join(failedKeys, ', '));
        }
        // An id-only payload has nothing to write; updating anyway would touch the record's audit
        // fields on every autosave tick that changed only non-record keys.
        if (assignedFields == 0) {
            return caseId;
        }
        try {
            update caseRecord;
        } catch (DmlException e) {
            throw new AuraHandledException('Update failed: ' + e.getDmlMessage(0));
        }
        return caseId;
    }

    // Open the Case behind an action item. The attribution is shared so the case is reachable from
    // the account it services and appears on the envelope that raised it; only the spec's own values
    // distinguish one type from another.
    private static String createActionCase(String financialAccountId, String envelopeId, ActionCaseSpec spec) {
        Financial_Account__c finAcc = loadActionAccount(financialAccountId);

        Case newCase = buildBaseActionCase(finAcc, envelopeId);
        newCase.Type = spec.caseType;
        newCase.Subject = spec.subjectNamesAccount
            ? spec.subject + ' for ' + finAcc.Name
            : spec.subject;
        newCase.Description = spec.description;
        if (spec.needsPrincipalReview) {
            newCase.Needs_Principal_Review__c = true;
        }
        if (spec.opensTradeInstructions) {
            newCase.Order_Tickets__c = true;
            newCase.Management_Style__c = 'DMS';
        }
        if (spec.recordsPreviousManagementStyle) {
            newCase.Previous_Management_Style__c = finAcc.Managed_Account_Platform__c;
        }

        insert newCase;
        linkToEnvelope(newCase.Id, envelopeId);
        return newCase.Id;
    }

    private static Financial_Account__c loadActionAccount(String financialAccountId) {
        return [
            SELECT Id, Name, Household__c, Primary_Owner__r.PersonContactId,
                Financial_Advisor_Team__c, Managed_Account_Platform__c
            FROM Financial_Account__c
            WHERE Id = :financialAccountId
            LIMIT 1
        ];
    }

    // The attribution every account-servicing case raised by the wizard shares. The household is the
    // envelope's; the servicing account's own household is the fallback for the rare envelope with no
    // resolvable household, so this never regresses to a null household.
    private static Case buildBaseActionCase(Financial_Account__c finAcc, String envelopeId) {
        Id householdId = EnvelopeHouseholdResolver.resolveHouseholdId(envelopeId);
        return new Case(
            Wizard_Financial_Account__c = finAcc.Id,
            Household__c = householdId != null ? householdId : finAcc.Household__c,
            AccountId = finAcc.Household__c,
            ContactId = finAcc.Primary_Owner__r.PersonContactId,
            Financial_Advisor_Team__c = finAcc.Financial_Advisor_Team__c,
            Origin = 'Wizard',
            RecordTypeId = resolveServicingRecordType(),
            Status = 'New'
        );
    }

    // The record type is configuration; without it the case would land in the wrong process.
    private static String resolveServicingRecordType() {
        Wizard_Flow_Values__mdt wizardValues = [
            SELECT Case_Account_Servicing_Record_Type__c
            FROM Wizard_Flow_Values__mdt
            LIMIT 1
        ];
        if (wizardValues.Case_Account_Servicing_Record_Type__c == null) {
            throw new AuraHandledException(
                'Wizard Flow Values is missing the account-servicing Case record type.'
            );
        }
        return wizardValues.Case_Account_Servicing_Record_Type__c;
    }

    // An action item belongs to the one envelope that raised it; this link is what scopes it back
    // onto the outline when the envelope is reopened.
    private static void linkToEnvelope(Id caseId, String envelopeId) {
        if (String.isNotBlank(envelopeId)) {
            insert new Envelope_Content__c(Envelope__c = envelopeId, Case__c = caseId);
        }
    }
    
    @AuraEnabled
    public static String createManagedPlatformCase(String financialAccountId, Map<String, Object> formData, String envelopeId) {
        try {
            // Get Financial Account and related data
            Financial_Account__c finAcc = [
                SELECT Id, Name, Household__c, Primary_Owner__r.PersonContactId, 
                Financial_Advisor_Team__c, Managed_Account_Platform__c
                FROM Financial_Account__c 
                WHERE Id = :financialAccountId 
                LIMIT 1
            ];
            
            // Get Wizard Flow Values for RecordTypeId
            Wizard_Flow_Values__mdt wizardValues = [
                SELECT Case_Account_Servicing_Record_Type__c 
                FROM Wizard_Flow_Values__mdt 
                LIMIT 1
            ];
            
            String newPlatform = (String)formData.get('managedAccountPlatform');
            
            // Create Case
            Case newCase = new Case();
            if(formData.get('Id') != null){
                newCase.Id = (Id)formData.get('Id');
            }
            Id householdId = EnvelopeHouseholdResolver.resolveHouseholdId(envelopeId);
            newCase.Wizard_Financial_Account__c = finAcc.Id;
            newCase.Household__c = householdId != null ? householdId : finAcc.Household__c;
            newCase.ContactId = finAcc.Primary_Owner__r.PersonContactId;
            newCase.Financial_Advisor_Team__c = finAcc.Financial_Advisor_Team__c;
            newCase.Origin = 'Wizard';
            newCase.RecordTypeId = wizardValues.Case_Account_Servicing_Record_Type__c;
            newCase.Status = 'New';
            newCase.Subject = 'Change Management Style';
            newCase.Type = 'Change Management Style';
            newCase.Description = 'Change Management Style to ' + newPlatform + '.';
            newCase.Management_Style__c = newPlatform;
            newCase.Previous_Management_Style__c = finAcc.Managed_Account_Platform__c;
            
            // Handle DMS-specific fields
            if (newPlatform == 'DMS' || newPlatform == 'DMS (Wrap)') {
                newCase.Order_Tickets__c = true;
                newCase.Incomplete_Record__c = false;
                
                // Bond Ladder fields
                if (formData.containsKey('bondLadder') && (Boolean)formData.get('bondLadder')) {
                    newCase.Bond_Ladder__c = true;
                    newCase.Cash_Withdrawal_Selection__c = (String)formData.get('blCashWithdrawalSelection');
                    newCase.Cash_Withdrawal_Amount__c = (Decimal)formData.get('blAmount');
                    newCase.DMS_Addendum_Frequency__c = (String)formData.get('blFrequency');
                    newCase.DMS_Addendum_Freq_Other__c = (String)formData.get('blOtherFrequency');
                    newCase.DMS_Frequency_Start_Date__c = Date.valueOf(String.valueOf(formData.get('blStartDate')));
                    newCase.Permission_to_Liquidate__c = (Boolean)formData.get('blLiquidatePermission');
                    newCase.Permission_to_Reinvest__c = (Boolean)formData.get('blReinvestPermission');
                    newCase.Special_Instructions__c = (String)formData.get('blCustomization');
                }
                
                // STCM fields
                if (formData.containsKey('stcm') && (Boolean)formData.get('stcm')) {
                    newCase.STCM__c = true;
                    newCase.Cash_Withdrawal_Selection__c = (String)formData.get('stcmCashWithdrawalSelection');
                    newCase.DMS_Addendum_Frequency__c = (String)formData.get('stcmFrequency');
                    newCase.DMS_Addendum_Freq_Other__c = (String)formData.get('stcmOtherFrequency');
                    newCase.DMS_Frequency_Start_Date__c =  Date.valueOf(String.valueOf(formData.get('stcmStartDate')));
                    newCase.Permission_to_Liquidate__c = (Boolean)formData.get('stcmLiquidatePermission');
                    newCase.Permission_to_Reinvest__c = (Boolean)formData.get('stcmReinvestPermission');
                    newCase.Special_Instructions__c = (String)formData.get('stcmCustomization');
                    newCase.STCM_Strategy_Term__c = (String)formData.get('stcmStrategyTerm');
                }
            }
            
            upsert newCase;
            
            // Create Envelope_Content__c record
            if (String.isNotBlank(envelopeId) && formData.get('Id') == null) {
                Envelope_Content__c envelopeContent = new Envelope_Content__c();
                envelopeContent.Envelope__c = envelopeId;
                envelopeContent.Case__c = newCase.Id;
                insert envelopeContent;
            }
            
            // Update Financial Account with new platform
            finAcc.Managed_Account_Platform__c = newPlatform;
            update finAcc;
            
            return newCase.Id;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error creating case: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static String createAccountClosureCase(String financialAccountId, Map<String, Object> formData, String envelopeId) {
        try {
            // Get Financial Account and related data
            Financial_Account__c finAcc = [
                SELECT Id, Name, Household__c, Primary_Owner__c, Primary_Owner__r.PersonContactId,
                Financial_Advisor_Team__c
                FROM Financial_Account__c 
                WHERE Id = :financialAccountId 
                LIMIT 1
            ];
            
            // Get Wizard Flow Values for RecordTypeId
            Wizard_Flow_Values__mdt wizardValues = [
                SELECT Case_Account_Servicing_Record_Type__c 
                FROM Wizard_Flow_Values__mdt 
                LIMIT 1
            ];
            
            String closureReason = (String)formData.get('accountClosureReason');
            
            // Create Case
            Case newCase = new Case();
            if(formData.get('Id') != null){
                newCase.Id = (Id)formData.get('Id');
            }
            Id householdId = EnvelopeHouseholdResolver.resolveHouseholdId(envelopeId);
            newCase.Wizard_Financial_Account__c = finAcc.Id;
            newCase.Household__c = householdId != null ? householdId : finAcc.Household__c;
            newCase.AccountId = finAcc.Household__c;
            newCase.ContactId = finAcc.Primary_Owner__r.PersonContactId;
            newCase.Financial_Advisor_Team__c = finAcc.Financial_Advisor_Team__c;
            newCase.Origin = 'Wizard';
            newCase.RecordTypeId = wizardValues.Case_Account_Servicing_Record_Type__c;
            newCase.Status = 'New';
            newCase.Subject = 'Account Closure - ' + closureReason;
            newCase.Type = 'Account Closure';
            newCase.Description = 'Please review all documentation and ensure that all necessary changes are made for this Account Closure.';
            newCase.Account_Closure_Reason__c = closureReason;
            
            // Add conditional fields based on closure reason
            if (closureReason == 'Client Terminated Services') {
                newCase.Account_Closure_End_Date__c = parseFormDate(formData.get('endDate'), 'End Date');
            } else if (closureReason == 'Terminated Services') {
                newCase.Account_Closure_Additional_Information__c = (String)formData.get('additionalInformation');
            } else if (closureReason == 'Other') {
                newCase.Account_Closure_Explanation__c = (String)formData.get('explanation');
            } else if (closureReason == 'Death') {
                Date dateOfDeath = parseFormDate(formData.get('dateOfDeath'), 'Date of Death');
                if (dateOfDeath > Date.today()) {
                    throw new AuraHandledException('Date of Death cannot be in the future.');
                }
                newCase.Date_of_Death__c = dateOfDeath;
                
                // Update Primary Owner Account with Date of Death
                if (finAcc.Primary_Owner__c != null && dateOfDeath != null) {
                    Account primaryOwner = [
                        SELECT Id, LastName, Date_of_Death__c 
                        FROM Account 
                        WHERE Id = :finAcc.Primary_Owner__c 
                        LIMIT 1
                    ];
                    
                    primaryOwner.Date_of_Death__c = dateOfDeath;
                    primaryOwner.LastName = primaryOwner.LastName + ' (DECEASED)';
                    update primaryOwner;
                }
            }
            
            insert newCase;
            
            // Create Envelope_Content__c record
            if (String.isNotBlank(envelopeId) && formData.get('Id') == null) {
                Envelope_Content__c envelopeContent = new Envelope_Content__c();
                envelopeContent.Envelope__c = envelopeId;
                envelopeContent.Case__c = newCase.Id;
                insert envelopeContent;
            }
            
            // Handle file uploads if present
            if (formData.containsKey('uploadedFiles') && formData.get('uploadedFiles') != null) {
                List<Object> files = (List<Object>) formData.get('uploadedFiles');
                
                if (!files.isEmpty()) {
                    List<ContentDocumentLink> cdLinks = new List<ContentDocumentLink>();
                    
                    for (Object fileObj : files) {
                        
                        Map<Object, Object> file = (Map<Object, Object>) fileObj;
                        
                        String documentId = (String) file.get('documentId');
                        
                        ContentDocumentLink cdl = new ContentDocumentLink();
                        cdl.ContentDocumentId = documentId;
                        cdl.LinkedEntityId = newCase.Id;
                        cdl.ShareType = 'V';
                        
                        cdLinks.add(cdl);
                    }
                    
                    insert cdLinks;
                }
            }
            return newCase.Id;
            
        } catch (AuraHandledException e) {
            // Already a user-facing message (date validation); re-wrapping would read as
            // "Script-thrown exception".
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error creating account closure case: ' + e.getMessage());
        }
    }
    

    @AuraEnabled
    public static void deleteAccountActionCase(String caseId){
        delete new case(Id = caseId);        
    }
    // The date fields on the closure form are required, but the raw Date.valueOf calls used to turn
    // a missing or malformed value into an unhandled exception; name the field in the error instead.
    private static Date parseFormDate(Object raw, String label) {
        if (raw == null || String.isBlank(String.valueOf(raw))) {
            throw new AuraHandledException(label + ' is required.');
        }
        try {
            return Date.valueOf(String.valueOf(raw));
        } catch (Exception e) {
            throw new AuraHandledException(label + ' is not a valid date.');
        }
    }
}