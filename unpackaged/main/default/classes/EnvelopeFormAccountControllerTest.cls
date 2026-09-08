/**
 * EnvelopeFormAccountController — the wizard's "add account" create path and its helpers.
 *
 * The create path is what the Household Outline's inline "Enter account nickname" input calls.
 * What is pinned here is that the nickname the advisor types lands on Account_Nickname__c as well
 * as Name: Name is rebuilt by the Financial Account trigger once an owner / registration type is
 * captured, so before 2026-09-08 the nickname was gone the moment the interview was filled in.
 */
@IsTest
private class EnvelopeFormAccountControllerTest {

    // Accounts in this org carry a validation rule that bare inserts trip; Type + Classification
    // is the combination the other wizard test classes use to get past it.
    private static Account insertHousehold(Id teamId) {
        Account household = new Account(
            Name = 'Nickname Household',
            Type = 'Other',
            Classification__c = 'Vendor;',
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Household').getRecordTypeId(),
            Financial_Advisor_Team__c = teamId
        );
        insert household;
        return household;
    }

    @TestSetup
    static void setup() {
        // The team trigger's after-insert updates the team, and its before-update path reads the
        // 'Default Team' record unguarded — so that record has to exist before any other team.
        insert new Financial_Advisor_Team__c(Name = 'Default Team');
        Financial_Advisor_Team__c team = new Financial_Advisor_Team__c(Name = 'Nickname Team');
        insert team;
        insert new Rep_Code__c(Name = 'NK1', Financial_Advisor_Team__c = team.Id);

        Account household = insertHousehold(team.Id);

        Envelope__c envelope = new Envelope__c(Name = 'Nickname Envelope');
        insert envelope;
        insert new Envelope_Content__c(Envelope__c = envelope.Id, Account__c = household.Id);
    }

    @IsTest
    static void createSavesNicknameAndLinksTheEnvelope() {
        Envelope__c envelope = [SELECT Id FROM Envelope__c WHERE Name = 'Nickname Envelope' LIMIT 1];
        Account household = [SELECT Id, Financial_Advisor_Team__c FROM Account WHERE Name = 'Nickname Household' LIMIT 1];

        Test.startTest();
        String accountId = EnvelopeFormAccountController.createOrUpdateFinancialAccountWithEnvelope(
            envelope.Id, 'Louie Wade - Individual', null);
        Test.stopTest();

        Financial_Account__c created = [
            SELECT Name, Account_Nickname__c, Household__c, Financial_Advisor_Team__c, Submitted__c
            FROM Financial_Account__c
            WHERE Id = :accountId
        ];
        System.assertEquals('Louie Wade - Individual', created.Account_Nickname__c,
                            'The typed nickname is kept on its own field.');
        System.assertEquals('Louie Wade - Individual', created.Name, 'Name is seeded from the nickname.');
        System.assertEquals(household.Id, created.Household__c);
        System.assertEquals(household.Financial_Advisor_Team__c, created.Financial_Advisor_Team__c);
        System.assertEquals(false, created.Submitted__c);
        System.assertEquals(1, [
            SELECT COUNT() FROM Envelope_Content__c
            WHERE Envelope__c = :envelope.Id AND Wizard_Financial_Account__c = :accountId
        ], 'The new account is linked to the envelope.');
    }

    @IsTest
    static void updateRewritesNicknameOnTheExistingAccount() {
        Envelope__c envelope = [SELECT Id FROM Envelope__c WHERE Name = 'Nickname Envelope' LIMIT 1];
        Financial_Account__c existing = new Financial_Account__c(Name = 'Old', Account_Nickname__c = 'Old');
        insert existing;

        Test.startTest();
        String accountId = EnvelopeFormAccountController.createOrUpdateFinancialAccountWithEnvelope(
            envelope.Id, 'Renamed', existing.Id);
        Test.stopTest();

        System.assertEquals(existing.Id, accountId, 'The existing id is returned.');
        Financial_Account__c updated = [SELECT Name, Account_Nickname__c FROM Financial_Account__c WHERE Id = :existing.Id];
        System.assertEquals('Renamed', updated.Account_Nickname__c);
        System.assertEquals('Renamed', updated.Name);
        System.assertEquals(0, [
            SELECT COUNT() FROM Envelope_Content__c
            WHERE Envelope__c = :envelope.Id AND Wizard_Financial_Account__c = :existing.Id
        ], 'An update creates no envelope link.');
    }

    @IsTest
    static void createRejectsBlankNickname() {
        Envelope__c envelope = [SELECT Id FROM Envelope__c WHERE Name = 'Nickname Envelope' LIMIT 1];
        Boolean threw = false;
        try {
            EnvelopeFormAccountController.createOrUpdateFinancialAccountWithEnvelope(envelope.Id, '  ', null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'A blank nickname is rejected before any DML.');
    }

    @IsTest
    static void createRejectsEnvelopeWithoutHousehold() {
        Envelope__c bare = new Envelope__c(Name = 'Bare Envelope');
        insert bare;
        Boolean threw = false;
        try {
            EnvelopeFormAccountController.createOrUpdateFinancialAccountWithEnvelope(bare.Id, 'Anything', null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'An envelope with no household link cannot take an account.');
        System.assertEquals(0, [SELECT COUNT() FROM Financial_Account__c WHERE Account_Nickname__c = 'Anything']);
    }

    @IsTest
    static void repCodesFollowTheHouseholdsTeam() {
        Account household = [SELECT Id FROM Account WHERE Name = 'Nickname Household' LIMIT 1];

        List<Rep_Code__c> codes = EnvelopeFormAccountController.getRepCodesRelatedToFAT(household.Id);
        System.assertEquals(1, codes.size());
        System.assertEquals('NK1', codes[0].Name);

        System.assertEquals(0, EnvelopeFormAccountController.getRepCodesRelatedToFAT(null).size(),
                            'No household, no rep codes.');

        Account teamless = new Account(Name = 'Teamless', Type = 'Other', Classification__c = 'Vendor;');
        insert teamless;
        System.assertEquals(0, EnvelopeFormAccountController.getRepCodesRelatedToFAT(teamless.Id).size(),
                            'A household without a team has no rep codes.');
    }

    @IsTest
    static void accountTypesGroupByCategory() {
        Map<String, List<String>> types = EnvelopeFormAccountController.getAccountTypesFromMetadata();
        // Registration_Type__mdt is real org metadata; every category listed carries at least one type.
        for (String category : types.keySet()) {
            System.assert(!types.get(category).isEmpty(), 'Category ' + category + ' lists no types.');
        }
    }

    @IsTest
    static void createMemberRejectsMissingOrUnknownRecordType() {
        Envelope__c envelope = [SELECT Id FROM Envelope__c WHERE Name = 'Nickname Envelope' LIMIT 1];

        Boolean threwEmpty = false;
        try {
            EnvelopeFormAccountController.createMember(new Map<String, Object>(), envelope.Id);
        } catch (AuraHandledException e) {
            threwEmpty = true;
        }
        System.assert(threwEmpty, 'No data is rejected.');

        Boolean threwUnknown = false;
        try {
            EnvelopeFormAccountController.createMember(
                new Map<String, Object>{ 'RecordType' => 'spaceship', 'Name' => 'X' }, envelope.Id);
        } catch (AuraHandledException e) {
            threwUnknown = true;
        }
        System.assert(threwUnknown, 'An unmapped record type is rejected.');
    }

    @IsTest
    static void createMemberInsertsAClientLinkedToTheEnvelope() {
        Envelope__c envelope = [SELECT Id FROM Envelope__c WHERE Name = 'Nickname Envelope' LIMIT 1];
        Account household = [SELECT Id, Financial_Advisor_Team__c FROM Account WHERE Name = 'Nickname Household' LIMIT 1];

        Map<String, Object> acc = new Map<String, Object>{
            'RecordType' => 'client',
            'FirstName' => 'Louie',
            'LastName' => 'Wade',
            'Type' => 'Other',
            'Classification__c' => 'Vendor;'
        };

        Test.startTest();
        Id memberId = EnvelopeFormAccountController.createMember(acc, envelope.Id);
        Test.stopTest();

        Account member = [SELECT LastName, Financial_Advisor_Team__c FROM Account WHERE Id = :memberId];
        System.assertEquals('Wade', member.LastName);
        System.assertEquals(household.Financial_Advisor_Team__c, member.Financial_Advisor_Team__c,
                            'A client inherits the household\'s advisor team.');
        System.assertEquals(1, [
            SELECT COUNT() FROM Envelope_Content__c WHERE Envelope__c = :envelope.Id AND Account__c = :memberId
        ], 'The member is linked to the envelope.');
        // Not asserted: the household AccountContactRelation. This class has per-org variants
        // (launchpad's createMember does not create one), and this test is deployed to all of them.
    }
}