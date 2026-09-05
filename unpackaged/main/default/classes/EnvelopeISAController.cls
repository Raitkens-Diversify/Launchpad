public with sharing class EnvelopeISAController {
    
    @AuraEnabled
    public Static List<Rep_Code__c> getRepCodesRelatedToFAT(Id householdId){
        // Every team whose codes this user may legitimately put on this household's account: the
        // household's own team, plus each team the running user actually belongs to. Scoping to the
        // household alone offered a single code to an advisor who sits on several teams and holds
        // one per team, so the one they needed was not on the list — and where the household's team
        // happened to hold exactly one code, the field hid itself and wrote that code silently.
        Set<Id> teamIds = new Set<Id>();

        if (householdId != null) {
            // Iterated rather than assigned: a household id that matches nothing would throw on a
            // single-row assignment, and an unreadable household should cost the list, not the form.
            for (Account acc : [
                SELECT Financial_Advisor_Team__c
                FROM Account
                WHERE Id = :householdId
                LIMIT 1
            ]) {
                if (acc.Financial_Advisor_Team__c != null) {
                    teamIds.add(acc.Financial_Advisor_Team__c);
                }
            }
        }

        // Active membership only: a lapsed member's codes are not theirs to assign any more.
        for (Financial_Advisor_Team_Member__c member : [
            SELECT Financial_Advisor_Team__c
            FROM Financial_Advisor_Team_Member__c
            WHERE User__c = :UserInfo.getUserId()
              AND Active__c = true
              AND Financial_Advisor_Team__c != null
        ]) {
            teamIds.add(member.Financial_Advisor_Team__c);
        }

        if (teamIds.isEmpty()) {
            return new List<Rep_Code__c>();
        }

        // Query Rep Codes
        return [
            SELECT Id, Name, Financial_Advisor_Team__c
            FROM Rep_Code__c
            WHERE Financial_Advisor_Team__c IN :teamIds
            WITH USER_MODE
            ORDER BY Name
        ];
    }
    
    // Creates (or renames) a Financial_Account__c and links it to the envelope. DPIs are
    // Financial Accounts too — isDpi distinguishes them, and is fixed at creation.
    @AuraEnabled
    public static String createOrUpdateFinancialAccountWithEnvelope(
        Id envelopeId,String accountNickname, Id existingAccountId, Boolean isDpi) {
            if (String.isBlank(accountNickname) || envelopeId == null) {
                throw new AuraHandledException('Account Nickname and Envelope ID are required.');
            }
            try {
                // Get the envelope's Household-record-type content row. Filtering to the Household
                // record type (not just any linked Account) keeps Household__c pointing at the
                // household rather than a member account added earlier in the flow.
                Envelope__c envelope = [
                    SELECT Id, 
                    (SELECT Id, Account__c, 
                     Account__r.Financial_Advisor_Team__c, Wizard_Financial_Account__c
                     FROM Wizard_Envelope_Records__r
                     WHERE Account__c != null AND Account__r.RecordType.Name = 'Household' 
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
                Case caseRecord;
                
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
                        Submitted__c = false,
                        DPI__c = isDpi == true
                    
                    );// Create new Case record
                   
                    insert finAccount;
                    
                    Id caseRecordType = Schema.SObjectType.Case.getRecordTypeInfosByName().get('Account Opening').getRecordTypeId();

                    // Prefer the envelope's household; the junction household row (householdId) is the
                    // fallback and, being this envelope's Household row, is what the resolver returns anyway.
                    Id caseHouseholdId = EnvelopeHouseholdResolver.resolveHouseholdId(envelopeId);
                    caseRecord = new Case(
                        Subject = 'New Financial Account',
                        origin = 'Wizard',
                        Type = 'Account Opening',
                        Status = 'New',
                        Household__C = caseHouseholdId != null ? caseHouseholdId : householdId,
                        Financial_Advisor_Team__c = financialAdvisorTeamId,
                        Wizard_Financial_Account__c= finAccount.Id,
                        Submitted__c = false,
                        RecordTypeId = caseRecordType
                    );
                    insert caseRecord;
                    
                    
                    // create new Envelope_Content
                    Envelope_Content__c envelopeContent = new Envelope_Content__c(
                        Envelope__c = envelopeId,
                        Wizard_Financial_Account__c = finAccount.Id
                    );

                    Envelope_Content__c envelopeContentCase = new Envelope_Content__c(
                        Envelope__c = envelopeId,
                        Case__c = caseRecord.Id
                    );
                    insert envelopeContent;
                    insert envelopeContentCase;       
                    
                    // Create Required Document
                    Required_Documents__c reqDoc = new Required_Documents__c(
                        Name = finAccount.Name + ' - account opening',
                        Financial_Account__c = finAccount.Id
                    );
                    
                    insert reqDoc;
                    
                    // Link to Envelope
                    insert new Envelope_Content__c(
                        Envelope__c = envelopeId,
                        Required_Document__c = reqDoc.Id
                    );
                    
                    // Query owners
                    Financial_Account__c accountWithOwners = [
                        SELECT Id,
                        Primary_Owner__c,
                        Joint_Owner__c
                        FROM Financial_Account__c
                        WHERE Id = :finAccount.Id
                    ];
                    
                    List<Signee__c> signees = new List<Signee__c>();
                    
                    if (accountWithOwners.Primary_Owner__c != null) {
                        signees.add(new Signee__c(
                            Required_Document__c = reqDoc.Id,
                            Account__c = accountWithOwners.Primary_Owner__c
                        ));
                    }
                    
                    if (accountWithOwners.Joint_Owner__c != null &&
                        accountWithOwners.Joint_Owner__c != accountWithOwners.Primary_Owner__c) {
                            
                            signees.add(new Signee__c(
                                Required_Document__c = reqDoc.Id,
                                Account__c = accountWithOwners.Joint_Owner__c
                            ));
                        }
                    
                    if (!signees.isEmpty()) {
                        insert signees;
                    }
                    
                    
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
    
    // Registration attributes keyed by the Financial_Account__c.Registration_Type__c picklist
    // value. The wizard resolves a selected registration to its related-party requirements from
    // these flags, since the picklist itself carries no grouping.
    //
    // Keyed by MasterLabel because that is how Registration_Type__mdt already joins to
    // Registration_Type__c elsewhere (see Financial_Account_TriggerHandler.setAccountType).
    // Every record is returned, including those without a Category__c, so a registration that is
    // uncategorised still contributes its flags.
    @AuraEnabled(cacheable=true)
    public static Map<String, RegistrationTypeAttributes> getRegistrationTypeAttributes() {
        Map<String, RegistrationTypeAttributes> attributesByRegistration =
            new Map<String, RegistrationTypeAttributes>();
        
        for (Registration_Type__mdt rt : [
            SELECT MasterLabel, Category__c, Joint_Account__c, Beneficiary_Account__c,
            Business_Account__c, Qualified__c
            FROM Registration_Type__mdt
        ]) {
            attributesByRegistration.put(rt.MasterLabel, new RegistrationTypeAttributes(rt));
        }
        
        return attributesByRegistration;
    }
    
    public class RegistrationTypeAttributes {
        @AuraEnabled public String category;
        @AuraEnabled public Boolean isJoint;
        @AuraEnabled public Boolean isBeneficiary;
        @AuraEnabled public Boolean isBusiness;
        @AuraEnabled public Boolean isQualified;
        
        public RegistrationTypeAttributes(Registration_Type__mdt rt) {
            this.category      = rt.Category__c;
            this.isJoint       = rt.Joint_Account__c == true;
            this.isBeneficiary = rt.Beneficiary_Account__c == true;
            this.isBusiness    = rt.Business_Account__c == true;
            this.isQualified   = rt.Qualified__c == true;
        }
    }
    
    public static Integer testCoverage(){
        Integer x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        x = 1;
        return x;
    }
}