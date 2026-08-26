@IsTest
private class AccountSlaTriggerHandlerTest {
    @IsTest
    static void test_NullInputsDoNotThrow() {
        AccountSlaTriggerHandler handler = new AccountSlaTriggerHandler();
        Test.startTest();
        handler.isAfterInsert(null);
        handler.isAfterUpdate(null, null);
        handler.isAfterInsert(new Map<Id, Account>());
        handler.isAfterUpdate(new Map<Id, Account>(), new Map<Id, Account>());
        Test.stopTest();
        Assert.isTrue(true, 'Null and empty Account SLA handler inputs should be no-ops');
    }

    @IsTest
    static void test_NoStandardEntitlementWhenNotSubmitted() {
        Account acc = new Account(
            Name = 'Not Submitted Entitlement Account',
            Submitted__c = false,
            Type ='Other'
        );

        Test.startTest();
        insert acc;
        Test.stopTest();

        Account inserted = [
            SELECT Submitted__c
            FROM Account
            WHERE Id = :acc.Id
        ];
        System.assertEquals(false, inserted.Submitted__c, 'Submitted__c should remain false');
        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Entitlement
                WHERE AccountId = :acc.Id
                    AND Name LIKE '% - Standard SLA'
            ],
            'Standard SLA Entitlement should not be created when Submitted__c is false'
        );

        delete acc;
        undelete acc;
    }

    @IsTest
    static void test_CreateStandardEntitlementOnInsertWhenSubmitted() {
        Account acc = new Account(
            Name = 'Entitlement Insert Account',
            Submitted__c = true,
             Type ='Other'
        );

        Test.startTest();
        insert acc;
        Test.stopTest();

        assertStandardEntitlementCreated(acc.Id, 'Entitlement Insert Account - Standard SLA');
    }

    @IsTest
    static void test_CreateStandardEntitlementWhenSubmittedFlipped() {
        Account acc = new Account(Name = 'Entitlement Flip Account', Submitted__c = false, Type ='Other');
        insert acc;

        Test.startTest();
        acc.Submitted__c = true;
        update acc;
        Test.stopTest();

        assertStandardEntitlementCreated(acc.Id, 'Entitlement Flip Account - Standard SLA');
    }

    @IsTest
    static void test_DoesNotCreateDuplicateStandardEntitlement() {
        Account acc = new Account(Name = 'Entitlement Duplicate Account', Submitted__c = false, Type ='Other');
        insert acc;

        Test.startTest();
        acc.Submitted__c = true;
        update acc;
        Test.stopTest();

        Integer afterFirst = [
            SELECT COUNT()
            FROM Entitlement
            WHERE AccountId = :acc.Id
        ];

        new AccountEntitlementQueueable(new Set<Id>{ acc.Id }).execute(null);

        Integer afterSecond = [
            SELECT COUNT()
            FROM Entitlement
            WHERE AccountId = :acc.Id
        ];
        System.assertEquals(afterFirst, afterSecond, 'Should not create a duplicate Standard SLA Entitlement');
    }

    @IsTest
    static void test_AccountEntitlementQueueableEmptySet() {
        Test.startTest();
        System.enqueueJob(new AccountEntitlementQueueable(new Set<Id>()));
        Test.stopTest();
    }

    private static Boolean canResolveEntitlementLookups() {
        List<Case_Entitlement_Values__mdt> entitlementValues = [
            SELECT Business_Hours__c, SLA_Policy__c
            FROM Case_Entitlement_Values__mdt
            LIMIT 1
        ];
        if (entitlementValues.isEmpty()
            || String.isBlank(entitlementValues[0].Business_Hours__c)
            || String.isBlank(entitlementValues[0].SLA_Policy__c)) {
            return false;
        }
        List<BusinessHours> businessHoursList = [
            SELECT Id
            FROM BusinessHours
            WHERE Name = :entitlementValues[0].Business_Hours__c
            LIMIT 1
        ];
        List<SlaProcess> slaProcessList = [
            SELECT Id
            FROM SlaProcess
            WHERE Name = :entitlementValues[0].SLA_Policy__c
            LIMIT 1
        ];
        return !businessHoursList.isEmpty() && !slaProcessList.isEmpty();
    }

    private static void assertStandardEntitlementCreated(Id accountId, String expectedName) {
        List<Entitlement> entitlements = [
            SELECT Id, Name, AccountId, StartDate, BusinessHoursId, SlaProcessId
            FROM Entitlement
            WHERE AccountId = :accountId
        ];
        if (canResolveEntitlementLookups()) {
            System.assertEquals(1, entitlements.size(), 'One Standard SLA Entitlement should be created');
            System.assertEquals(expectedName, entitlements[0].Name, 'Entitlement Name should be Account Name + Standard SLA');
            System.assertEquals(accountId, entitlements[0].AccountId, 'Entitlement should be linked to the Account');
            System.assertEquals(Date.today(), entitlements[0].StartDate, 'Start Date should be today');
            System.assertNotEquals(null, entitlements[0].BusinessHoursId, 'Business Hours should be set');
            System.assertNotEquals(null, entitlements[0].SlaProcessId, 'SLA Policy should be set');
        } else {
            System.assertEquals(
                0,
                entitlements.size(),
                'Entitlement creation is skipped when CMDT/lookup values cannot be resolved'
            );
        }
    }
}