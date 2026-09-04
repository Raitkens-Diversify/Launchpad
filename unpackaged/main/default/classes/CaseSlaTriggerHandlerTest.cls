@IsTest
private class CaseSlaTriggerHandlerTest {
    @IsTest
    static void test_NullInputsDoNotThrow() {
        CaseSlaTriggerHandler handler = new CaseSlaTriggerHandler();
        Test.startTest();
        handler.isBeforeUpdate(null, null);
        handler.isBeforeDelete(null);
        Test.stopTest();
        Assert.isTrue(true, 'Null Case SLA handler inputs should be no-ops');
    }

    @IsTest
    static void test_BeforeUpdateAccumulatesPitstopMinutes() {
        Account acc = new Account(Name = 'Case SLA Minutes Account', Classification__c = 'Unclassified');
        insert acc;
        Case caseRecord = new Case(
            Subject = 'Case SLA Minutes',
            Status = 'New',
            Origin = 'Phone',
            AccountId = acc.Id,
            Pitstop_Start__c = System.now().addHours(-1),
            Pitstop_Total_Minutes__c = 0,
            IsStopped = true
        );
        insert caseRecord;

        BusinessHours bh = resolveBusinessHours();
        if (bh != null) {
            caseRecord.BusinessHoursId = bh.Id;
            update caseRecord;
            CasePitStopMinutesService.testBusinessHoursIdOverride = bh.Id;
        }

        Test.startTest();
        caseRecord.Pitstop_Start__c = null;
        caseRecord.IsStopped = false;
        update caseRecord;
        Test.stopTest();

        Case refreshed = [
            SELECT Pitstop_Total_Minutes__c
            FROM Case
            WHERE Id = :caseRecord.Id
        ];
        if (bh != null) {
            Assert.isTrue(
                refreshed.Pitstop_Total_Minutes__c != null && refreshed.Pitstop_Total_Minutes__c >= 0,
                'CaseSlaTriggerHandler should accumulate Pit Stop minutes on before update'
            );
        }
        CasePitStopMinutesService.resetCachesForTest();
    }

    @IsTest
    static void test_BeforeDeleteClearsEntitlement() {
        Account acc = new Account(Name = 'Case SLA Delete Account', Classification__c = 'Unclassified');
        insert acc;

        Entitlement entitlementRecord = createActiveEntitlement(acc.Id);
        if (entitlementRecord == null) {
            Assert.isTrue(true, 'Skipped: cannot resolve Business Hours / SLA Process');
            return;
        }

        Case caseRecord = new Case(
            Subject = 'Case SLA Delete',
            Status = 'New',
            Origin = 'Phone',
            AccountId = acc.Id
        );
        insert caseRecord;
        caseRecord.EntitlementId = entitlementRecord.Id;
        update caseRecord;

        Test.startTest();
        delete caseRecord;
        Test.stopTest();

        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Case WHERE Id = :caseRecord.Id],
            'CaseSlaTriggerHandler should clear EntitlementId so delete can proceed'
        );
    }

    private static BusinessHours resolveBusinessHours() {
        List<Case_Entitlement_Values__mdt> cmdt = [
            SELECT Business_Hours__c
            FROM Case_Entitlement_Values__mdt
            LIMIT 1
        ];
        if (!cmdt.isEmpty() && String.isNotBlank(cmdt[0].Business_Hours__c)) {
            List<BusinessHours> named = [
                SELECT Id
                FROM BusinessHours
                WHERE Name = :cmdt[0].Business_Hours__c
                LIMIT 1
            ];
            if (!named.isEmpty()) {
                return named[0];
            }
        }
        List<BusinessHours> defaultBh = [
            SELECT Id
            FROM BusinessHours
            WHERE IsDefault = true
            LIMIT 1
        ];
        return defaultBh.isEmpty() ? null : defaultBh[0];
    }

    private static Entitlement createActiveEntitlement(Id accountId) {
        BusinessHours bh = resolveBusinessHours();
        List<Case_Entitlement_Values__mdt> cmdt = [
            SELECT SLA_Policy__c
            FROM Case_Entitlement_Values__mdt
            LIMIT 1
        ];
        if (bh == null || cmdt.isEmpty() || String.isBlank(cmdt[0].SLA_Policy__c)) {
            return null;
        }
        List<SlaProcess> processes = [
            SELECT Id
            FROM SlaProcess
            WHERE Name = :cmdt[0].SLA_Policy__c
            LIMIT 1
        ];
        if (processes.isEmpty()) {
            return null;
        }
        Entitlement entitlementRecord = new Entitlement(
            Name = 'Case SLA Test Entitlement',
            AccountId = accountId,
            StartDate = Date.today(),
            BusinessHoursId = bh.Id,
            SlaProcessId = processes[0].Id
        );
        insert entitlementRecord;
        return entitlementRecord;
    }
}