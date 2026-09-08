/**
 * The wizard's "add account" path keeps the typed nickname (2026-09-08).
 *
 * The Household Outline's inline "Enter account nickname" input calls
 * EnvelopeFormAccountController.createOrUpdateFinancialAccountWithEnvelope. What is pinned here is
 * that the nickname lands on Account_Nickname__c as well as Name: Name is rebuilt by the Financial
 * Account trigger once a registration type is captured, so before the field existed the nickname
 * was gone the moment the interview was filled in.
 *
 * Deliberately a separate class: EnvelopeFormAccountControllerTest is the team's general coverage
 * for the controller (Manoj / Rachel, 2026-09-05) and is left untouched.
 */
@IsTest
private class EnvelopeFormAccountNicknameTest {

    @TestSetup
    static void setup() {
        // The team trigger's after-insert updates the team, and its before-update path reads the
        // 'Default Team' record unguarded — so that record has to exist before any other team.
        insert new Financial_Advisor_Team__c(Name = 'Default Team');
        Financial_Advisor_Team__c team = new Financial_Advisor_Team__c(Name = 'Nickname Team');
        insert team;

        // Accounts in this org carry a validation rule that bare inserts trip; Type + Classification
        // is the combination the other wizard test classes use to get past it.
        Account household = new Account(
            Name = 'Nickname Household',
            Type = 'Other',
            Classification__c = 'Vendor;',
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Household').getRecordTypeId(),
            Financial_Advisor_Team__c = team.Id
        );
        insert household;

        Envelope__c envelope = new Envelope__c(Name = 'Nickname Envelope');
        insert envelope;
        insert new Envelope_Content__c(Envelope__c = envelope.Id, Account__c = household.Id);
    }

    @IsTest
    static void createSavesNicknameBesideName() {
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
}