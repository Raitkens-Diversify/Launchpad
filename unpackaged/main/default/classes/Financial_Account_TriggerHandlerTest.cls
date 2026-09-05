@IsTest
private class Financial_Account_TriggerHandlerTest {

    // Builds the pieces updateRelatedCase joins on: an envelope, a wizard Financial Account, its
    // 'Account Opening' wizard Case, and the two Envelope_Content rows that link both to the SAME
    // envelope (the match updateRelatedCase requires before it will touch the Case).
    private static Financial_Account__c setupDpi(String productType, Boolean isDpi) {
        Envelope__c envelope = new Envelope__c(Status__c = 'In Progress');
        insert envelope;

        Financial_Account__c fa = new Financial_Account__c(
            Name = 'Wizard FA',
            Submitted__c = false,
            DPI__c = isDpi,
            Product_Type__c = productType
        );
        insert fa;

        Case wizardCase = new Case(
            Subject = 'New Financial Account',
            Origin = 'Wizard',
            Type = 'Account Opening',
            Status = 'New',
            Wizard_Financial_Account__c = fa.Id,
            Submitted__c = false
        );
        insert wizardCase;

        insert new List<Envelope_Content__c>{
            new Envelope_Content__c(Envelope__c = envelope.Id, Wizard_Financial_Account__c = fa.Id),
            new Envelope_Content__c(Envelope__c = envelope.Id, Case__c = wizardCase.Id)
        };

        return fa;
    }

    private static String caseTypeFor(Id faId) {
        return [
            SELECT Type FROM Case WHERE Wizard_Financial_Account__c = :faId LIMIT 1
        ].Type;
    }

    @IsTest
    static void dpiGetsDirectCustodianOnInsert() {
        Financial_Account__c fa = new Financial_Account__c(Name = 'DPI FA', DPI__c = true);

        Test.startTest();
        insert fa;
        Test.stopTest();

        Assert.areEqual('DIRECT',
            [SELECT Custodian__c FROM Financial_Account__c WHERE Id = :fa.Id].Custodian__c,
            'A DPI should be stamped with the DIRECT custodian on creation.');
    }

    @IsTest
    static void nonDpiDoesNotGetDirectCustodianOnInsert() {
        Financial_Account__c fa = new Financial_Account__c(Name = 'Non-DPI FA', DPI__c = false);

        Test.startTest();
        insert fa;
        Test.stopTest();

        Assert.areEqual(null,
            [SELECT Custodian__c FROM Financial_Account__c WHERE Id = :fa.Id].Custodian__c,
            'A non-DPI account should not have its custodian defaulted.');
    }

    @IsTest
    static void dpiVariableAnnuityCaseIsRetypedOnSubmit() {
        Financial_Account__c fa = setupDpi('Variable Annuity', true);

        Test.startTest();
        fa.Submitted__c = true;
        update fa;
        Test.stopTest();

        Assert.areEqual('Purchase a Variable Annuity', caseTypeFor(fa.Id),
            'A submitted DPI with Product Type Variable Annuity should retype its Case.');
    }

    @IsTest
    static void dpiAlternativeInvestmentCaseIsRetypedOnSubmit() {
        Financial_Account__c fa = setupDpi('Alternative Investment', true);

        Test.startTest();
        fa.Submitted__c = true;
        update fa;
        Test.stopTest();

        Assert.areEqual('Purchase Alternative Investment', caseTypeFor(fa.Id),
            'A submitted DPI with Product Type Alternative Investment should retype its Case.');
    }

    @IsTest
    static void nonDpiVariableAnnuityCaseKeepsAccountOpening() {
        Financial_Account__c fa = setupDpi('Variable Annuity', false);

        Test.startTest();
        fa.Submitted__c = true;
        update fa;
        Test.stopTest();

        Assert.areEqual('Account Opening', caseTypeFor(fa.Id),
            'The retype is DPI-only; a regular account keeps the type it opened with.');
    }

    @IsTest
    static void dpiUnmappedProductTypeKeepsAccountOpening() {
        Financial_Account__c fa = setupDpi('Mutual Fund', true);

        Test.startTest();
        fa.Submitted__c = true;
        update fa;
        Test.stopTest();

        Assert.areEqual('Account Opening', caseTypeFor(fa.Id),
            'A product type with no mapping leaves the Case type untouched.');
    }

    // ---------------------------------------------------------
    // setOwnerOnWizardFinancialAccount / createShareRecord
    // ---------------------------------------------------------

    // Financial_Advisor_Team_Member__c inserts fire a DLRS rollup trigger that touches the parent
    // Financial_Advisor_Team__c (BeforeUpdate), which runs Financial_Advisor_Team_TriggerHandler.
    // updateRepCode — a method that unconditionally queries
    // '[SELECT Id FROM Financial_Advisor_Team__c WHERE Name = \'Default Team\']' as a single-row
    // assignment. That record is real, permanent reference data in this org (confirmed via
    // `sf data query`), but Apex tests are isolated from existing org data (SeeAllData=false, as
    // required), so the query sees nothing and throws "List has no rows for assignment to SObject"
    // unless the test itself creates a Financial_Advisor_Team__c named 'Default Team'.
    private static void ensureDefaultTeamExistsForTest() {
        if ([SELECT COUNT() FROM Financial_Advisor_Team__c WHERE Name = 'Default Team'] == 0) {
            insert new Financial_Advisor_Team__c(Name = 'Default Team');
        }
    }

    @IsTest
    static void ownerIsSetFromActiveFinancialAdvisorTeamMemberOnInsert() {
        ensureDefaultTeamExistsForTest();
        Financial_Advisor_Team__c fat = new Financial_Advisor_Team__c(Name = 'Owner Test FAT');
        insert fat;
        Id currentUserId = UserInfo.getUserId();
        insert new Financial_Advisor_Team_Member__c(
            Financial_Advisor_Team__c = fat.Id,
            Role__c = 'Financial Advisor',
            Active__c = true,
            User__c = currentUserId
        );

        Test.startTest();
        Financial_Account__c fa = new Financial_Account__c(
            Name = 'Owner Test FA', Financial_Advisor_Team__c = fat.Id
        );
        insert fa;
        Test.stopTest();

        Assert.areEqual(currentUserId,
            [SELECT OwnerId FROM Financial_Account__c WHERE Id = :fa.Id].OwnerId,
            'The Financial Account owner is set to the team\'s active Financial Advisor.');
    }

    // Financial_Advisor_Team_TriggerHandler.createPublicGroup auto-creates a Group named after the
    // team on insert and overwrites Public_Group_Id__c with it unconditionally (line ~157), so a
    // value set explicitly at insert time is discarded — the real group must be read back after
    // insert rather than pre-created here.
    @IsTest
    static void createShareRecordSharesWithTeamsPublicGroupOnInsert() {
        Financial_Advisor_Team__c fat = new Financial_Advisor_Team__c(Name = 'Share Test FAT');
        insert fat;
        Id autoGroupId = [
            SELECT Public_Group_Id__c FROM Financial_Advisor_Team__c WHERE Id = :fat.Id
        ].Public_Group_Id__c;

        Test.startTest();
        Financial_Account__c fa = new Financial_Account__c(
            Name = 'Share Test FA', Financial_Advisor_Team__c = fat.Id
        );
        insert fa;
        Test.stopTest();

        Assert.areEqual(1,
            [SELECT COUNT() FROM Financial_Account__Share
                WHERE ParentId = :fa.Id AND UserOrGroupId = :autoGroupId AND RowCause = 'Manual'],
            'Inserting with a Financial Advisor Team shares the record with its (auto-created) ' +
            'public group. Note: the Financial Account also always carries an Owner row and any ' +
            'org-configured sharing-rule rows, so this asserts on the Manual row for this specific ' +
            'group rather than the total share count.');
    }

    @IsTest
    static void createShareRecordRevokesOldTeamsShareWhenTeamChangesOnUpdate() {
        Financial_Advisor_Team__c oldFat = new Financial_Advisor_Team__c(Name = 'Old FAT');
        Financial_Advisor_Team__c newFat = new Financial_Advisor_Team__c(Name = 'New FAT');
        insert new List<Financial_Advisor_Team__c>{ oldFat, newFat };
        Map<Id, Financial_Advisor_Team__c> refreshed = new Map<Id, Financial_Advisor_Team__c>([
            SELECT Public_Group_Id__c FROM Financial_Advisor_Team__c
            WHERE Id IN :new List<Id>{ oldFat.Id, newFat.Id }
        ]);
        Id oldGroupId = refreshed.get(oldFat.Id).Public_Group_Id__c;
        Id newGroupId = refreshed.get(newFat.Id).Public_Group_Id__c;

        Financial_Account__c fa = new Financial_Account__c(
            Name = 'Revoke Test FA', Financial_Advisor_Team__c = oldFat.Id
        );
        insert fa;

        Test.startTest();
        fa.Financial_Advisor_Team__c = newFat.Id;
        update fa;
        Test.stopTest();

        Assert.areEqual(0,
            [SELECT COUNT() FROM Financial_Account__Share
                WHERE ParentId = :fa.Id AND UserOrGroupId = :oldGroupId],
            'The old team\'s share is revoked when the Financial Advisor Team changes.');
        Assert.areEqual(1,
            [SELECT COUNT() FROM Financial_Account__Share
                WHERE ParentId = :fa.Id AND UserOrGroupId = :newGroupId AND RowCause = 'Manual'],
            'The new team\'s share is added.');
    }

    // ---------------------------------------------------------
    // setDMSOnHousehold
    // ---------------------------------------------------------

    @IsTest
    static void dmsManagedAccountFlagsHouseholdOnInsert() {
        Account household = new Account(Name = 'DMS Household', Type = 'Prospect');
        insert household;

        Test.startTest();
        Financial_Account__c fa = new Financial_Account__c(
            Name = 'DMS Household FA', Household__c = household.Id, Managed_Account_Platform__c = 'DMS'
        );
        insert fa;
        Test.stopTest();

        Assert.isTrue(
            [SELECT Has_FAs_that_are_DMS__c FROM Account WHERE Id = :household.Id].Has_FAs_that_are_DMS__c,
            'A DMS Financial Account flags its household on insert.');
    }

    @IsTest
    static void dmsManagedAccountFlagsHouseholdOnUpdate() {
        Account household = new Account(Name = 'DMS Household Update', Type = 'Prospect');
        insert household;
        Financial_Account__c fa = new Financial_Account__c(
            Name = 'AMS FA', Household__c = household.Id, Managed_Account_Platform__c = 'AMS'
        );
        insert fa;

        Test.startTest();
        fa.Managed_Account_Platform__c = 'DMS (Wrap)';
        update fa;
        Test.stopTest();

        Assert.isTrue(
            [SELECT Has_FAs_that_are_DMS__c FROM Account WHERE Id = :household.Id].Has_FAs_that_are_DMS__c,
            'Switching an existing Financial Account onto a DMS platform flags its household.');
    }

    // ---------------------------------------------------------
    // setReportAcctNumber_Before / setReportAcctNumber_AfterInsert
    // ---------------------------------------------------------

    // setReportAcctNumber_Before runs only from isBeforeUpdate (there is no equivalent call from
    // isBeforeInsert), so an inserted-only record never gets Account_Number_for_Report__c computed —
    // the update itself is what exercises it, regardless of which field changes.
    @IsTest
    static void reportAccountNumberStripsHyphensAndTakesPrefixBeforeUnderscore() {
        Financial_Account__c fa = new Financial_Account__c(
            Name = 'Report Number FA', Account_Number__c = '123-456_789'
        );
        insert fa;

        Test.startTest();
        update fa;
        Test.stopTest();

        Assert.areEqual('123456',
            [SELECT Account_Number_for_Report__c FROM Financial_Account__c WHERE Id = :fa.Id]
                .Account_Number_for_Report__c,
            'Hyphens are stripped and only the part before the underscore is kept.');
    }

    @IsTest
    static void reportAccountNumberKeepsWholeNumberWithoutUnderscore() {
        Financial_Account__c fa = new Financial_Account__c(
            Name = 'Report Number FA 2', Account_Number__c = '987-654'
        );
        insert fa;

        Test.startTest();
        update fa;
        Test.stopTest();

        Assert.areEqual('987654',
            [SELECT Account_Number_for_Report__c FROM Financial_Account__c WHERE Id = :fa.Id]
                .Account_Number_for_Report__c);
    }

    // NOTE (production bug found while extending this test, 2026-09-04): a BD account without
    // Brokerage/Account_Number__c is meant to get an 'NX...' report number from
    // Financial_Account_TriggerHandler.setReportAcctNumber_AfterInsert, called from isAfterInsert.
    // That method mutates fields directly on the records from Trigger.newMap.values() — an AFTER
    // INSERT context, where Trigger.new records are read-only — so the assignment
    // 'f.Account_Number_for_Report__c = ...' throws System.FinalException: Record is read-only,
    // which surfaces as a DmlException on the insert itself (CANNOT_INSERT_UPDATE_ACTIVATE_ENTITY).
    // Confirmed via `sf apex run`: ANY insert with BD_or_RIA__c = 'BD' AND (Brokerage__c = false OR
    // Account_Number__c = null) fails outright. Left undeployed/untested here per instructions (no
    // production-code change); reported as a bug: Financial_Account_TriggerHandler.cls line 222.

    // ---------------------------------------------------------
    // setHousehold / setFinancialAccountName / setFinancialAccountNameOnUpdate / setMaestroAccountType
    // ---------------------------------------------------------

    private static Id personAccountRecordTypeId() {
        return Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName().get('PersonAccount').getRecordTypeId();
    }

    @IsTest
    static void nameIsBuiltFromPrimaryOwnerWhenBlankOnInsert() {
        Account owner = new Account(
            FirstName = 'Casey', LastName = 'Newby',
            RecordTypeId = personAccountRecordTypeId(), Type = 'Prospect'
        );
        insert owner;

        Test.startTest();
        Financial_Account__c fa = new Financial_Account__c(
            Primary_Owner__c = owner.Id, Registration_Type__c = 'Individual', Account_Number__c = '4321'
        );
        insert fa;
        Test.stopTest();

        Assert.areEqual('Casey Newby - Individual - 4321',
            [SELECT Name FROM Financial_Account__c WHERE Id = :fa.Id].Name,
            'A blank Name is built from the primary owner, registration type and account number.');
    }

    @IsTest
    static void nameIsRebuiltWhenRegistrationTypeChangesOnUpdate() {
        Account owner = new Account(
            FirstName = 'Jamie', LastName = 'Update',
            RecordTypeId = personAccountRecordTypeId(), Type = 'Prospect'
        );
        insert owner;
        Financial_Account__c fa = new Financial_Account__c(
            Name = 'Keep This Name', Primary_Owner__c = owner.Id, Registration_Type__c = 'Individual'
        );
        insert fa;

        Test.startTest();
        fa.Registration_Type__c = 'Joint Tenant';
        update fa;
        Test.stopTest();

        Assert.areEqual('Jamie Update - Joint Tenant',
            [SELECT Name FROM Financial_Account__c WHERE Id = :fa.Id].Name,
            'Changing the registration type rebuilds the name from the primary owner.');
    }

    private static Id householdRecordTypeId() {
        return Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName().get('Household').getRecordTypeId();
    }

    @IsTest
    static void householdIsResolvedFromPrimaryOwnersAccountContactRelationOnInsert() {
        Account household = new Account(
            Name = 'Resolved Household', RecordTypeId = householdRecordTypeId(), Type = 'Prospect'
        );
        insert household;
        Account owner = new Account(
            FirstName = 'Robin', LastName = 'Linked',
            RecordTypeId = personAccountRecordTypeId(), Type = 'Prospect'
        );
        insert owner;
        Id ownerContactId = [SELECT PersonContactId FROM Account WHERE Id = :owner.Id].PersonContactId;
        insert new AccountContactRelation(AccountId = household.Id, ContactId = ownerContactId);

        Test.startTest();
        Financial_Account__c fa = new Financial_Account__c(
            Name = 'Household Resolve FA', Primary_Owner__c = owner.Id
        );
        insert fa;
        Test.stopTest();

        Assert.areEqual(household.Id,
            [SELECT Household__c FROM Financial_Account__c WHERE Id = :fa.Id].Household__c,
            'Household__c is resolved from the primary owner\'s AccountContactRelation when left blank.');
    }

    @IsTest
    static void maestroAccountTypeIsSetFromRegistrationTypeMetadataOnInsert() {
        List<Registration_Type__mdt> types = [
            SELECT MasterLabel, BD_Account_Type__c
            FROM Registration_Type__mdt
            WHERE BD_Account_Type__c != null
            LIMIT 1
        ];
        if (types.isEmpty()) {
            return; // No configured Registration_Type__mdt row in this org to drive the mapping.
        }
        Registration_Type__mdt anyType = types[0];

        Test.startTest();
        // Brokerage__c = true and a non-null Account_Number__c keep this insert off the
        // always-broken setReportAcctNumber_AfterInsert path (see the note above
        // reportAccountNumberStripsHyphensAndTakesPrefixBeforeUnderscore's block) while still using
        // BD_or_RIA__c = 'BD' to drive the Maestro Account Type mapping under test here.
        Financial_Account__c fa = new Financial_Account__c(
            Name = 'Maestro FA', BD_or_RIA__c = 'BD', Registration_Type__c = anyType.MasterLabel,
            Brokerage__c = true, Account_Number__c = '999999'
        );
        insert fa;
        Test.stopTest();

        Assert.areEqual(anyType.BD_Account_Type__c,
            [SELECT Maestro_Account_Type__c FROM Financial_Account__c WHERE Id = :fa.Id].Maestro_Account_Type__c,
            'The Maestro Account Type is looked up from Registration_Type__mdt by label and BD/RIA.');
    }
}