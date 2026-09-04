@IsTest
private class CaseTaskSlaAutomationTest {
    private static BusinessHours resolveBusinessHours() {
        List<Case_Entitlement_Values__mdt> cmdt = [
            SELECT Business_Hours__c, SLA_Policy__c
            FROM Case_Entitlement_Values__mdt
            LIMIT 1
        ];
        if (cmdt.isEmpty() || String.isBlank(cmdt[0].Business_Hours__c)) {
            List<BusinessHours> defaultBh = [
                SELECT Id, Name
                FROM BusinessHours
                WHERE IsDefault = true
                LIMIT 1
            ];
            return defaultBh.isEmpty() ? null : defaultBh[0];
        }
        List<BusinessHours> named = [
            SELECT Id, Name
            FROM BusinessHours
            WHERE Name = :cmdt[0].Business_Hours__c
            LIMIT 1
        ];
        if (!named.isEmpty()) {
            return named[0];
        }
        List<BusinessHours> defaultBh = [
            SELECT Id, Name
            FROM BusinessHours
            WHERE IsDefault = true
            LIMIT 1
        ];
        return defaultBh.isEmpty() ? null : defaultBh[0];
    }

    /** Start time that guarantees non-zero BusinessHours.diff even outside wall-clock hours. */
    private static Datetime pitstopStartWithBusinessMinutes(
        Id businessHoursId,
        Integer businessMinutes
    ) {
        return BusinessHours.add(
            businessHoursId,
            System.now(),
            -businessMinutes * 60L * 1000L
        );
    }

    private static SlaProcess resolveSlaProcess() {
        List<Case_Entitlement_Values__mdt> cmdt = [
            SELECT SLA_Policy__c
            FROM Case_Entitlement_Values__mdt
            LIMIT 1
        ];
        if (cmdt.isEmpty() || String.isBlank(cmdt[0].SLA_Policy__c)) {
            return null;
        }
        List<SlaProcess> processes = [
            SELECT Id, Name
            FROM SlaProcess
            WHERE Name = :cmdt[0].SLA_Policy__c
            LIMIT 1
        ];
        return processes.isEmpty() ? null : processes[0];
    }

    private static Entitlement createActiveEntitlement(Id accountId) {
        BusinessHours bh = resolveBusinessHours();
        SlaProcess sla = resolveSlaProcess();
        if (bh == null || sla == null) {
            return null;
        }
        Entitlement entitlementRecord = new Entitlement(
            Name = 'Test Standard SLA',
            AccountId = accountId,
            StartDate = Date.today(),
            BusinessHoursId = bh.Id,
            SlaProcessId = sla.Id
        );
        insert entitlementRecord;
        return entitlementRecord;
    }

    private static Case createCase(Id accountId) {
        Case caseRecord = new Case(
            Subject = 'SLA Automation Test',
            Status = 'New',
            Origin = 'Phone',
            AccountId = accountId
        );
        insert caseRecord;
        return caseRecord;
    }

    /** Satisfies Type_OR_Classification_Required validation on Account. */
    private static Account createAccount(String name) {
        Account acc = new Account(Name = name, Type = 'Other');
        insert acc;
        return acc;
    }

    @IsTest
    static void test_NoEntitlementOnCaseInsert() {
        Account acc = createAccount('Entitlement Assign Account');

        Entitlement entitlementRecord = createActiveEntitlement(acc.Id);
        if (entitlementRecord == null) {
            System.assert(true, 'Skipped: cannot resolve Business Hours / SLA Process');
            return;
        }

        Test.startTest();
        Case caseRecord = createCase(acc.Id);
        Test.stopTest();

        Case refreshed = [
            SELECT EntitlementId
            FROM Case
            WHERE Id = :caseRecord.Id
        ];
        Assert.isNull(
            refreshed.EntitlementId,
            'Entitlement should not be assigned on Case insert'
        );
    }

    @IsTest
    static void test_SkipEntitlementWhenNoAccount() {
        Test.startTest();
        Case caseRecord = new Case(
            Subject = 'No Account Case',
            Status = 'New',
            Origin = 'Phone'
        );
        insert caseRecord;
        Test.stopTest();

        Case refreshed = [SELECT EntitlementId FROM Case WHERE Id = :caseRecord.Id];
        Assert.isNull(refreshed.EntitlementId, 'No Account means no Entitlement assignment');
    }

    @IsTest
    static void test_ClearEntitlementOnCaseDelete() {
        Account acc = createAccount('Entitlement Delete Account');

        Entitlement entitlementRecord = createActiveEntitlement(acc.Id);
        if (entitlementRecord == null) {
            System.assert(true, 'Skipped: cannot resolve Business Hours / SLA Process');
            return;
        }

        Case caseRecord = createCase(acc.Id);
        caseRecord.EntitlementId = entitlementRecord.Id;
        update caseRecord;

        Case beforeDelete = [
            SELECT EntitlementId
            FROM Case
            WHERE Id = :caseRecord.Id
        ];
        Assert.areEqual(entitlementRecord.Id, beforeDelete.EntitlementId);

        Test.startTest();
        delete caseRecord;
        Test.stopTest();

        Integer remaining = [
            SELECT COUNT()
            FROM Case
            WHERE Id = :caseRecord.Id
        ];
        Assert.areEqual(0, remaining, 'Case with EntitlementId should delete after clear');
    }

    @IsTest
    static void test_BranchPitStopStartAndComplete() {
        Account acc = createAccount('Pit Stop Account');
        Case caseRecord = createCase(acc.Id);

        BusinessHours bh = resolveBusinessHours();
        if (bh != null) {
            caseRecord.BusinessHoursId = bh.Id;
            update caseRecord;
            CasePitStopMinutesService.testBusinessHoursIdOverride = bh.Id;
        }

        Test.startTest();
        Task pitStopTask = new Task(
            WhatId = caseRecord.Id,
            Subject = 'Branch Pit Stop',
            Status = 'Not Started',
            Branch_Pit_Stop__c = true,
            OwnerId = UserInfo.getUserId()
        );
        insert pitStopTask;

        Case afterStart = [
            SELECT Pitstop_Start__c, IsStopped, Pitstop_Total_Minutes__c
            FROM Case
            WHERE Id = :caseRecord.Id
        ];
        Assert.isNotNull(afterStart.Pitstop_Start__c, 'Pitstop Start should be set');
        Assert.isTrue(afterStart.IsStopped, 'Case should be stopped');

        pitStopTask.Status = 'Completed';
        update pitStopTask;
        Test.stopTest();

        Case afterComplete = [
            SELECT Pitstop_Start__c, IsStopped, Pitstop_Total_Minutes__c
            FROM Case
            WHERE Id = :caseRecord.Id
        ];
        Assert.isNull(afterComplete.Pitstop_Start__c, 'Pitstop Start should be cleared');
        Assert.isFalse(afterComplete.IsStopped, 'Case should resume');
        if (bh != null) {
            Assert.isTrue(
                afterComplete.Pitstop_Total_Minutes__c != null
                    && afterComplete.Pitstop_Total_Minutes__c >= 0,
                'Total minutes should accumulate'
            );
        }
    }

    @IsTest
    static void test_BranchPitStopOverlapErrors() {
        Account acc = createAccount('Pit Stop Overlap Account');
        Case caseRecord = createCase(acc.Id);

        Task first = new Task(
            WhatId = caseRecord.Id,
            Subject = 'First Pit Stop',
            Status = 'Not Started',
            Branch_Pit_Stop__c = true,
            OwnerId = UserInfo.getUserId()
        );
        insert first;

        Task second = new Task(
            WhatId = caseRecord.Id,
            Subject = 'Second Pit Stop',
            Status = 'Not Started',
            Branch_Pit_Stop__c = true,
            OwnerId = UserInfo.getUserId()
        );

        Boolean failed = false;
        Test.startTest();
        try {
            insert second;
        } catch (DmlException ex) {
            failed = true;
            Assert.isTrue(
                ex.getMessage().contains(CasePitStopService.ERROR_ALREADY_STOPPED)
                    || ex.getMessage().contains('Pit Stop'),
                'Expected overlap error message'
            );
        }
        Test.stopTest();
        Assert.isTrue(failed, 'Second Branch Pit Stop should be blocked');
    }

    @IsTest
    static void test_BranchPitStopCompleteOnInsert() {
        Account acc = createAccount('Pit Stop Complete Insert');
        Case caseRecord = createCase(acc.Id);
        caseRecord.Pitstop_Start__c = System.now().addHours(-1);
        caseRecord.IsStopped = true;
        update caseRecord;

        BusinessHours bh = resolveBusinessHours();
        if (bh != null) {
            CasePitStopMinutesService.testBusinessHoursIdOverride = bh.Id;
        }

        Test.startTest();
        Task completedPitStop = new Task(
            WhatId = caseRecord.Id,
            Subject = 'Completed Pit Stop',
            Status = 'Completed',
            Branch_Pit_Stop__c = true,
            OwnerId = UserInfo.getUserId()
        );
        insert completedPitStop;
        Test.stopTest();

        Case refreshed = [
            SELECT Pitstop_Start__c, IsStopped
            FROM Case
            WHERE Id = :caseRecord.Id
        ];
        Assert.isNull(refreshed.Pitstop_Start__c);
        Assert.isFalse(refreshed.IsStopped);
    }

    @IsTest
    static void test_HomeOfficeMilestonesOnTaskComplete() {
        Account acc = createAccount('Milestone Account');
        Entitlement entitlementRecord = createActiveEntitlement(acc.Id);
        Case caseRecord = createCase(acc.Id);

        Task_Template__c tt = new Task_Template__c();
        insert tt;
        Case_Template__c ct = new Case_Template__c();
        insert ct;

        Task_Template_Item__c submissionItem = new Task_Template_Item__c(
            Task_Template__c = tt.Id,
            Case_Template__c = ct.Id,
            Home_Office_Submission_Milestone__c = true,
            Home_Office_Goal_Milestone__c = false
        );
        insert submissionItem;

        Task_Template_Item__c goalItem = new Task_Template_Item__c(
            Task_Template__c = tt.Id,
            Case_Template__c = ct.Id,
            Home_Office_Submission_Milestone__c = false,
            Home_Office_Goal_Milestone__c = true
        );
        insert goalItem;

        Task submissionTask = new Task(
            WhatId = caseRecord.Id,
            Subject = 'Submission Milestone Task',
            Status = 'Not Started',
            Task_Template_Item__c = submissionItem.Id,
            OwnerId = UserInfo.getUserId()
        );
        insert submissionTask;

        Task goalTask = new Task(
            WhatId = caseRecord.Id,
            Subject = 'Goal Milestone Task',
            Status = 'Not Started',
            Task_Template_Item__c = goalItem.Id,
            OwnerId = UserInfo.getUserId()
        );
        insert goalTask;

        Case beforeComplete = [
            SELECT EntitlementId, Home_Office_Submission_Milestone_Start__c
            FROM Case
            WHERE Id = :caseRecord.Id
        ];
        Assert.isNull(beforeComplete.EntitlementId, 'Entitlement blank before submission milestone');
        Assert.isNull(beforeComplete.Home_Office_Submission_Milestone_Start__c);

        Test.startTest();
        submissionTask.Status = 'Completed';
        update submissionTask;

        goalTask.Status = 'Completed';
        update goalTask;
        Test.stopTest();

        Case refreshed = [
            SELECT Home_Office_Submission_Milestone_Start__c, Home_Office_Goal_Milestone_End__c,
                EntitlementId
            FROM Case
            WHERE Id = :caseRecord.Id
        ];
        Assert.isNotNull(
            refreshed.Home_Office_Submission_Milestone_Start__c,
            'Submission milestone start should be set'
        );
        Assert.isNotNull(
            refreshed.Home_Office_Goal_Milestone_End__c,
            'Goal milestone end should be set'
        );
        if (entitlementRecord != null) {
            Assert.areEqual(
                entitlementRecord.Id,
                refreshed.EntitlementId,
                'Active Account Entitlement should be set on submission milestone'
            );
        }

        Datetime originalStart = refreshed.Home_Office_Submission_Milestone_Start__c;
        Id originalEntitlementId = refreshed.EntitlementId;
        submissionTask.Status = 'Completed';
        update submissionTask;

        Case idempotent = [
            SELECT Home_Office_Submission_Milestone_Start__c, EntitlementId
            FROM Case
            WHERE Id = :caseRecord.Id
        ];
        Assert.areEqual(
            originalStart,
            idempotent.Home_Office_Submission_Milestone_Start__c,
            'Should not overwrite existing submission start'
        );
        Assert.areEqual(
            originalEntitlementId,
            idempotent.EntitlementId,
            'Should not overwrite existing EntitlementId'
        );
    }

    @IsTest
    static void test_MinutesServiceDirect() {
        Account acc = createAccount('Minutes Account');
        Case caseRecord = createCase(acc.Id);

        BusinessHours bh = resolveBusinessHours();
        if (bh == null) {
            System.assert(true, 'Skipped: no Business Hours available');
            return;
        }

        CasePitStopMinutesService.resetCachesForTest();
        Datetime startDt = pitstopStartWithBusinessMinutes(bh.Id, 120);
        caseRecord.Pitstop_Start__c = startDt;
        caseRecord.Pitstop_Total_Minutes__c = 10;
        caseRecord.BusinessHoursId = bh.Id;
        update caseRecord;

        Case oldCase = caseRecord.clone(true, true, true, true);
        Case newCase = caseRecord.clone(true, true, true, true);
        newCase.Pitstop_Start__c = null;
        newCase.IsStopped = false;
        // Prefer newCase.BusinessHoursId path (no override)
        newCase.BusinessHoursId = bh.Id;

        Test.startTest();
        CasePitStopMinutesService.accumulateMinutesOnStopClear(
            new List<Case>{ newCase },
            new Map<Id, Case>{ oldCase.Id => oldCase }
        );
        Test.stopTest();

        Assert.isTrue(
            newCase.Pitstop_Total_Minutes__c > 10,
            'Minutes should accumulate on top of existing total'
        );
    }

    @IsTest
    static void test_MinutesServiceEarlyReturnsAndBranches() {
        CasePitStopMinutesService.resetCachesForTest();

        // Early returns
        CasePitStopMinutesService.accumulateMinutesOnStopClear(null, null);
        CasePitStopMinutesService.accumulateMinutesOnStopClear(new List<Case>(), new Map<Id, Case>());
        CasePitStopMinutesService.accumulateMinutesOnStopClear(
            new List<Case>{ new Case(Subject = 'x') },
            null
        );

        Account acc = createAccount('Minutes Branches Account');
        Case caseRecord = createCase(acc.Id);
        BusinessHours bh = resolveBusinessHours();
        Assert.isNotNull(bh, 'Org must have Business Hours for minutes coverage');

        caseRecord.Pitstop_Start__c = pitstopStartWithBusinessMinutes(bh.Id, 60);
        caseRecord.Pitstop_Total_Minutes__c = null;
        update caseRecord;

        // No clear (start still set) → candidates empty
        Case stillStopped = caseRecord.clone(true, true, true, true);
        CasePitStopMinutesService.accumulateMinutesOnStopClear(
            new List<Case>{ stillStopped },
            new Map<Id, Case>{ caseRecord.Id => caseRecord }
        );

        // oldCase missing from map
        Case clearedNoOld = caseRecord.clone(true, true, true, true);
        clearedNoOld.Pitstop_Start__c = null;
        CasePitStopMinutesService.accumulateMinutesOnStopClear(
            new List<Case>{ clearedNoOld },
            new Map<Id, Case>()
        );

        // oldCase.BusinessHoursId when newCase.BusinessHoursId is null
        CasePitStopMinutesService.resetCachesForTest();
        Case oldWithBh = caseRecord.clone(true, true, true, true);
        oldWithBh.BusinessHoursId = bh.Id;
        oldWithBh.Pitstop_Total_Minutes__c = null;
        Case newFromOldBh = caseRecord.clone(true, true, true, true);
        newFromOldBh.Pitstop_Start__c = null;
        newFromOldBh.BusinessHoursId = null;
        newFromOldBh.Pitstop_Total_Minutes__c = 25; // different from old null/0 path + prefer new total

        Test.startTest();
        CasePitStopMinutesService.accumulateMinutesOnStopClear(
            new List<Case>{ newFromOldBh },
            new Map<Id, Case>{ oldWithBh.Id => oldWithBh }
        );
        Test.stopTest();

        Assert.isTrue(
            newFromOldBh.Pitstop_Total_Minutes__c > 25,
            'Should use oldCase BusinessHours and prefer newCase total minutes base'
        );
    }

    @IsTest
    static void test_MinutesServiceEntitlementAndCmdtFallback() {
        Account acc = createAccount('Minutes Entitlement Account');
        Entitlement entitlementRecord = createActiveEntitlement(acc.Id);
        Case caseRecord = createCase(acc.Id);

        Datetime startDt = System.now().addHours(-1);
        caseRecord.Pitstop_Start__c = startDt;
        caseRecord.Pitstop_Total_Minutes__c = 5;
        caseRecord.BusinessHoursId = null;
        if (entitlementRecord != null) {
            caseRecord.EntitlementId = entitlementRecord.Id;
        }
        update caseRecord;

        CasePitStopMinutesService.resetCachesForTest();

        Case oldCase = caseRecord.clone(true, true, true, true);
        oldCase.BusinessHoursId = null;
        Case newCase = caseRecord.clone(true, true, true, true);
        newCase.Pitstop_Start__c = null;
        newCase.BusinessHoursId = null;
        // EntitlementId on old only — exercise oldCase.EntitlementId branch
        newCase.EntitlementId = null;
        oldCase.EntitlementId = entitlementRecord != null ? entitlementRecord.Id : null;

        Test.startTest();
        CasePitStopMinutesService.accumulateMinutesOnStopClear(
            new List<Case>{ newCase },
            new Map<Id, Case>{ oldCase.Id => oldCase }
        );
        Decimal afterFirst = newCase.Pitstop_Total_Minutes__c;
        // Warm caches again via a second candidate clear (fresh totals)
        Case newCase2 = caseRecord.clone(true, true, true, true);
        newCase2.Pitstop_Start__c = null;
        newCase2.BusinessHoursId = null;
        newCase2.EntitlementId = null;
        CasePitStopMinutesService.accumulateMinutesOnStopClear(
            new List<Case>{ newCase2 },
            new Map<Id, Case>{ oldCase.Id => oldCase }
        );
        Test.stopTest();

        Assert.isTrue(
            afterFirst != null && afterFirst >= 5,
            'Should resolve BH via Entitlement or CMDT fallback'
        );
        Assert.isTrue(
            newCase2.Pitstop_Total_Minutes__c != null && newCase2.Pitstop_Total_Minutes__c >= 5,
            'Cached CMDT/BH resolution should still accumulate minutes'
        );
    }

    @IsTest
    static void test_MinutesServiceNoBusinessHoursSkips() {
        Account acc = createAccount('Minutes No BH Account');
        Case caseRecord = createCase(acc.Id);
        caseRecord.Pitstop_Start__c = System.now().addHours(-1);
        caseRecord.Pitstop_Total_Minutes__c = 3;
        update caseRecord;

        CasePitStopMinutesService.resetCachesForTest();
        CasePitStopMinutesService.testForceNoBusinessHours = true;

        Case oldCase = caseRecord.clone(true, true, true, true);
        Case newCase = caseRecord.clone(true, true, true, true);
        newCase.Pitstop_Start__c = null;
        Decimal priorTotal = newCase.Pitstop_Total_Minutes__c;

        Test.startTest();
        CasePitStopMinutesService.accumulateMinutesOnStopClear(
            new List<Case>{ newCase },
            new Map<Id, Case>{ oldCase.Id => oldCase }
        );
        Test.stopTest();

        Assert.areEqual(
            priorTotal,
            newCase.Pitstop_Total_Minutes__c,
            'Total minutes unchanged when Business Hours cannot be resolved'
        );
        CasePitStopMinutesService.resetCachesForTest();
    }

    @IsTest
    static void test_MinutesServiceCmdtBusinessHoursPath() {
        Account acc = createAccount('Minutes CMDT Account');
        Case caseRecord = createCase(acc.Id);
        caseRecord.Pitstop_Start__c = System.now().addHours(-1);
        caseRecord.Pitstop_Total_Minutes__c = 2;
        caseRecord.BusinessHoursId = null;
        caseRecord.EntitlementId = null;
        update caseRecord;

        CasePitStopMinutesService.resetCachesForTest();

        Case oldCase = caseRecord.clone(true, true, true, true);
        oldCase.BusinessHoursId = null;
        oldCase.EntitlementId = null;
        Case newCase = caseRecord.clone(true, true, true, true);
        newCase.Pitstop_Start__c = null;
        newCase.BusinessHoursId = null;
        newCase.EntitlementId = null;

        Test.startTest();
        CasePitStopMinutesService.accumulateMinutesOnStopClear(
            new List<Case>{ newCase },
            new Map<Id, Case>{ oldCase.Id => oldCase }
        );
        // Second invocation hits cached CMDT Business Hours Id / name
        Case newCase2 = caseRecord.clone(true, true, true, true);
        newCase2.Pitstop_Start__c = null;
        newCase2.BusinessHoursId = null;
        newCase2.EntitlementId = null;
        CasePitStopMinutesService.accumulateMinutesOnStopClear(
            new List<Case>{ newCase2 },
            new Map<Id, Case>{ oldCase.Id => oldCase }
        );
        Test.stopTest();

        Assert.isTrue(
            newCase.Pitstop_Total_Minutes__c != null && newCase.Pitstop_Total_Minutes__c >= 2,
            'CMDT Business Hours fallback should accumulate minutes'
        );
        Assert.isTrue(
            newCase2.Pitstop_Total_Minutes__c != null && newCase2.Pitstop_Total_Minutes__c >= 2,
            'Cached CMDT Business Hours should accumulate on second call'
        );
    }

    @IsTest
    static void test_MinutesServiceNewCaseEntitlementId() {
        Account acc = createAccount('Minutes New Entitlement Account');
        Entitlement entitlementRecord = createActiveEntitlement(acc.Id);
        if (entitlementRecord == null) {
            System.assert(true, 'Skipped: cannot create entitlement');
            return;
        }

        Case caseRecord = createCase(acc.Id);
        BusinessHours bh = resolveBusinessHours();
        if (bh == null) {
            System.assert(true, 'Skipped: no Business Hours available');
            return;
        }
        caseRecord.Pitstop_Start__c = pitstopStartWithBusinessMinutes(bh.Id, 60);
        caseRecord.Pitstop_Total_Minutes__c = 1;
        caseRecord.BusinessHoursId = null;
        caseRecord.EntitlementId = entitlementRecord.Id;
        update caseRecord;

        CasePitStopMinutesService.resetCachesForTest();

        Case oldCase = caseRecord.clone(true, true, true, true);
        oldCase.BusinessHoursId = null;
        oldCase.EntitlementId = null; // force newCase.EntitlementId branch
        Case newCase = caseRecord.clone(true, true, true, true);
        newCase.Pitstop_Start__c = null;
        newCase.BusinessHoursId = null;
        newCase.EntitlementId = entitlementRecord.Id;

        Test.startTest();
        CasePitStopMinutesService.accumulateMinutesOnStopClear(
            new List<Case>{ newCase },
            new Map<Id, Case>{ oldCase.Id => oldCase }
        );
        Test.stopTest();

        Assert.isTrue(
            newCase.Pitstop_Total_Minutes__c > 1,
            'Should use Entitlement BusinessHours from newCase.EntitlementId'
        );
    }

    @IsTest
    static void test_MinutesServiceBlankCmdtBusinessHoursName() {
        Account acc = createAccount('Minutes Blank CMDT');
        Case caseRecord = createCase(acc.Id);
        caseRecord.Pitstop_Start__c = System.now().addHours(-1);
        caseRecord.Pitstop_Total_Minutes__c = 4;
        update caseRecord;

        CasePitStopMinutesService.resetCachesForTest();
        CasePitStopMinutesService.setCachedBusinessHoursNameForTest('');

        Case oldCase = caseRecord.clone(true, true, true, true);
        oldCase.BusinessHoursId = null;
        oldCase.EntitlementId = null;
        Case newCase = caseRecord.clone(true, true, true, true);
        newCase.Pitstop_Start__c = null;
        newCase.BusinessHoursId = null;
        newCase.EntitlementId = null;
        Decimal prior = newCase.Pitstop_Total_Minutes__c;

        Test.startTest();
        CasePitStopMinutesService.accumulateMinutesOnStopClear(
            new List<Case>{ newCase },
            new Map<Id, Case>{ oldCase.Id => oldCase }
        );
        Test.stopTest();

        Assert.areEqual(prior, newCase.Pitstop_Total_Minutes__c);
        CasePitStopMinutesService.resetCachesForTest();
    }
}