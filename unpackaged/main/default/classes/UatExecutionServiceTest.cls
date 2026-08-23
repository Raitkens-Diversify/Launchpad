/**
 * Tests for UatExecutionService + UatScopeService + the seven triggers — the
 * execution-lifecycle engine. These encode the non-negotiables:
 * definition/execution split, scope union dedup, eager slots, claim-in-place,
 * additional-tester independence, unclaimed-only team retargeting, the
 * step-delete cascade ordering, and the status/result rollup matrix.
 */
@IsTest
private class UatExecutionServiceTest {

    @TestSetup
    static void setup() {
        UatTestDataFactory.createTesterUser('uattst1');
        UatTestDataFactory.createTesterUser('uattst2');
        UatTestDataFactory.createTesterUser('uattst3');
    }

    private static User tester1() {
        return [SELECT Id FROM User WHERE LastName = 'UAT uattst1' LIMIT 1];
    }

    private static User tester2() {
        return [SELECT Id FROM User WHERE LastName = 'UAT uattst2' LIMIT 1];
    }

    private static User tester3() {
        return [SELECT Id FROM User WHERE LastName = 'UAT uattst3' LIMIT 1];
    }

    /** Taxonomy + 3 cases + a team; no books/cycles (tests build their own). */
    private static List<Test_Case__c> threeCases() {
        UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
        return new List<Test_Case__c>{
            UatTestDataFactory.makeCase(tax.mod.Id, 2, 1001),
            UatTestDataFactory.makeCase(tax.mod.Id, 2, 1002),
            UatTestDataFactory.makeCase(tax.mod.Id, 2, 1003)
        };
    }

    @IsTest
    static void scopeUnionDeduplicates() {
        List<Test_Case__c> cases = threeCases();
        // Case 0 reachable through two books AND a direct add; case 1 via book A;
        // case 2 via direct add only.
        Test_Book__c bookA = UatTestDataFactory.makeBook('Book A', new List<Id>{ cases[0].Id, cases[1].Id });
        Test_Book__c bookB = UatTestDataFactory.makeBook('Book B', new List<Id>{ cases[0].Id });
        Test_Cycle__c cycle = UatTestDataFactory.makeCycle('Sprint 1', null,
            new List<Id>{ bookA.Id, bookB.Id }, new List<Id>{ cases[0].Id, cases[2].Id });

        Map<Id, Map<Id, UatScopeService.ScopeEntry>> scope =
            UatScopeService.effectiveScope(new Set<Id>{ cycle.Id });
        Map<Id, UatScopeService.ScopeEntry> perCase = scope.get(cycle.Id);

        Assert.areEqual(3, perCase.size(), 'Union of both books + direct adds, de-duplicated.');
        Assert.areEqual(3, perCase.get(cases[0].Id).sources.size(),
            'Every path labeled: Book A, Book B, Added directly.');
        Assert.isTrue(perCase.get(cases[0].Id).sources.contains('Added directly'));
        Assert.areEqual(new List<String>{ 'Book A' }, perCase.get(cases[1].Id).sources);
        Assert.areEqual(new List<String>{ 'Added directly' }, perCase.get(cases[2].Id).sources);
    }

    @IsTest
    static void eagerSlotsMaterializeOncePerCase() {
        List<Test_Case__c> cases = threeCases();
        Test_Book__c bookA = UatTestDataFactory.makeBook('Book A', new List<Id>{ cases[0].Id, cases[1].Id });
        Team__c team = UatTestDataFactory.makeTeam('Alpha', new List<Id>{ tester1().Id });

        Test.startTest();
        Test_Cycle__c cycle = UatTestDataFactory.makeCycle('Sprint 1', team.Id,
            new List<Id>{ bookA.Id }, new List<Id>{ cases[0].Id }); // case 0 also direct
        Test.stopTest();

        List<Test_Execution__c> slots = [
            SELECT Test_Case__c, Assigned_Team__c, Assigned_Tester__c, Testing_Status__c
            FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id
        ];
        Assert.areEqual(2, slots.size(), 'One slot per case in scope — dedup across book+direct.');
        for (Test_Execution__c slot : slots) {
            Assert.isNull(slot.Assigned_Tester__c, 'Slots start unclaimed.');
            Assert.areEqual(team.Id, slot.Assigned_Team__c, 'Team visibility from the cycle.');
            Assert.areEqual('Not Started', slot.Testing_Status__c);
        }
    }

    @IsTest
    static void bookItemInsertFansOutToEveryCycleUsingTheBook() {
        List<Test_Case__c> cases = threeCases();
        Test_Book__c book = UatTestDataFactory.makeBook('Shared Book', new List<Id>{ cases[0].Id });
        Test_Cycle__c cycle1 = UatTestDataFactory.makeCycle('Sprint 1', null, new List<Id>{ book.Id }, null);
        Test_Cycle__c cycle2 = UatTestDataFactory.makeCycle('Sprint 2', null, new List<Id>{ book.Id }, null);

        Test.startTest();
        insert new Test_Book_Item__c(Test_Book__c = book.Id, Test_Case__c = cases[1].Id, Sort_Order__c = 2);
        Test.stopTest();

        Assert.areEqual(1, [
            SELECT COUNT() FROM Test_Execution__c
            WHERE Test_Cycle__c = :cycle1.Id AND Test_Case__c = :cases[1].Id
        ], 'New book case reached cycle 1.');
        Assert.areEqual(1, [
            SELECT COUNT() FROM Test_Execution__c
            WHERE Test_Cycle__c = :cycle2.Id AND Test_Case__c = :cases[1].Id
        ], 'New book case reached cycle 2.');
    }

    @IsTest
    static void scopeShrinkDeletesOnlyPristineSlots() {
        List<Test_Case__c> cases = threeCases();
        Test_Book__c book = UatTestDataFactory.makeBook('Book A', new List<Id>{ cases[0].Id, cases[1].Id });
        Test_Cycle__c cycle = UatTestDataFactory.makeCycle('Sprint 1', null, new List<Id>{ book.Id }, null);

        // Claim case 0's slot — it must survive the detach.
        Test_Execution__c claimed = [
            SELECT Id FROM Test_Execution__c
            WHERE Test_Cycle__c = :cycle.Id AND Test_Case__c = :cases[0].Id
        ];
        UatExecutionService.claim(claimed.Id, tester1().Id);

        Test.startTest();
        delete [SELECT Id FROM Test_Cycle_Book__c WHERE Test_Cycle__c = :cycle.Id];
        Test.stopTest();

        List<Test_Execution__c> remaining = [
            SELECT Test_Case__c FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id
        ];
        Assert.areEqual(1, remaining.size(), 'Pristine unclaimed slot deleted; claimed one kept.');
        Assert.areEqual(cases[0].Id, remaining[0].Test_Case__c, 'The claimed execution is history.');
    }

    @IsTest
    static void claimMutatesInPlaceAndBlocksRaces() {
        List<Test_Case__c> cases = threeCases();
        Test_Cycle__c cycle = UatTestDataFactory.makeCycle('Sprint 1', null, null, new List<Id>{ cases[0].Id });
        Test_Execution__c slot = [
            SELECT Id FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id
        ];

        Test.startTest();
        UatExecutionService.claim(slot.Id, tester1().Id);
        Test.stopTest();

        Assert.areEqual(tester1().Id,
            [SELECT Assigned_Tester__c FROM Test_Execution__c WHERE Id = :slot.Id].Assigned_Tester__c,
            'Claiming sets the tester on the SAME record.');
        Assert.areEqual(1, [SELECT COUNT() FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id],
            'No additional record created by claiming.');

        // Idempotent for the claimer; an error for anyone else.
        UatExecutionService.claim(slot.Id, tester1().Id);
        try {
            UatExecutionService.claim(slot.Id, tester2().Id);
            Assert.fail('Second claimer should be rejected.');
        } catch (UatExecutionService.UatExecutionException e) {
            Assert.isTrue(e.getMessage().contains('claimed'), e.getMessage());
        }
    }

    @IsTest
    static void addingSecondTesterCreatesIndependentExecution() {
        List<Test_Case__c> cases = threeCases();
        Test_Cycle__c cycle = UatTestDataFactory.makeCycle('Sprint 1', null, null, new List<Id>{ cases[0].Id });
        Test_Execution__c slot = [SELECT Id FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id];
        UatExecutionService.claim(slot.Id, tester1().Id);

        Test.startTest();
        Test_Execution__c second =
            UatExecutionService.createIndependentExecution(cycle.Id, cases[0].Id, tester2().Id);
        Test.stopTest();

        Assert.areNotEqual(slot.Id, second.Id, 'A NEW execution — never a relabel of the first.');
        Assert.areEqual(2, [
            SELECT COUNT() FROM Test_Execution__c
            WHERE Test_Cycle__c = :cycle.Id AND Test_Case__c = :cases[0].Id
        ], 'Two testers, two permanently independent executions.');
        Assert.areEqual(tester1().Id,
            [SELECT Assigned_Tester__c FROM Test_Execution__c WHERE Id = :slot.Id].Assigned_Tester__c,
            'The first execution was not touched.');

        // Same identity asked again -> the same record back (find-or-create).
        Test_Execution__c again =
            UatExecutionService.createIndependentExecution(cycle.Id, cases[0].Id, tester2().Id);
        Assert.areEqual(second.Id, again.Id);
    }

    @IsTest
    static void teamChangeRetargetsUnclaimedOnly() {
        List<Test_Case__c> cases = threeCases();
        Team__c alpha = UatTestDataFactory.makeTeam('Alpha', new List<Id>{ tester1().Id });
        Team__c bravo = UatTestDataFactory.makeTeam('Bravo', new List<Id>{ tester2().Id });
        Test_Cycle__c cycle = UatTestDataFactory.makeCycle('Sprint 1', alpha.Id, null,
            new List<Id>{ cases[0].Id, cases[1].Id });

        List<Test_Execution__c> slots = [
            SELECT Id, Test_Case__c FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id ORDER BY Test_Case__c
        ];
        UatExecutionService.claim(slots[0].Id, tester1().Id); // claimed under Alpha

        Test.startTest();
        cycle.Assigned_Team__c = bravo.Id;
        update cycle;
        Test.stopTest();

        Assert.areEqual(alpha.Id,
            [SELECT Assigned_Team__c FROM Test_Execution__c WHERE Id = :slots[0].Id].Assigned_Team__c,
            'Claimed execution keeps the team it was claimed under.');
        Assert.areEqual(bravo.Id,
            [SELECT Assigned_Team__c FROM Test_Execution__c WHERE Id = :slots[1].Id].Assigned_Team__c,
            'Unclaimed slot follows the cycle to the new team.');
    }

    @IsTest
    static void rollupMatrixAndEnsureStepResults() {
        UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
        Test_Case__c tc = UatTestDataFactory.makeCase(tax.mod.Id, 2, 1001); // 2 scripted steps
        UatTestDataFactory.makeExploreStep(tc.Id, 3);                       // + 1 explore (no denominator)
        Test_Cycle__c cycle = UatTestDataFactory.makeCycle('Sprint 1', null, null, new List<Id>{ tc.Id });
        Test_Execution__c slot = [SELECT Id FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id];

        List<Test_Step_Result__c> results = UatExecutionService.ensureStepResults(slot.Id);
        Assert.areEqual(3, results.size(), 'One result row per current step, explore included.');
        Assert.areEqual('Not Started',
            [SELECT Testing_Status__c FROM Test_Execution__c WHERE Id = :slot.Id].Testing_Status__c,
            'Blank seeding does not move status.');

        // Answer one scripted step -> In Progress, no verdict yet.
        Map<Id, Boolean> exploreByStep = new Map<Id, Boolean>();
        for (Test_Step__c s : [SELECT Id, Is_Explore__c FROM Test_Step__c WHERE Test_Case__c = :tc.Id]) {
            exploreByStep.put(s.Id, s.Is_Explore__c);
        }
        Test_Step_Result__c first;
        Test_Step_Result__c second;
        for (Test_Step_Result__c r : results) {
            if (exploreByStep.get(r.Test_Step__c) == true) {
                continue;
            }
            if (first == null) {
                first = r;
            } else {
                second = r;
            }
        }
        first.Result__c = 'Pass';
        update first;
        Test_Execution__c e = [
            SELECT Testing_Status__c, Testing_Result__c, Last_Tested_Date__c
            FROM Test_Execution__c WHERE Id = :slot.Id
        ];
        Assert.areEqual('In Progress', e.Testing_Status__c);
        Assert.isNull(e.Testing_Result__c, 'No verdict until Complete (unless fail/blocked).');
        Assert.areEqual(Date.today(), e.Last_Tested_Date__c);

        // Answer the second with Blocked -> Complete + Blocked verdict.
        second.Result__c = 'Blocked';
        update second;
        e = [SELECT Testing_Status__c, Testing_Result__c FROM Test_Execution__c WHERE Id = :slot.Id];
        Assert.areEqual('Complete', e.Testing_Status__c, 'Explore steps never gate completion.');
        Assert.areEqual('Blocked', e.Testing_Result__c);

        // A Fail anywhere outranks Blocked.
        first.Result__c = 'Fail';
        update first;
        Assert.areEqual('Failed',
            [SELECT Testing_Result__c FROM Test_Execution__c WHERE Id = :slot.Id].Testing_Result__c);

        // All Pass -> Passed.
        first.Result__c = 'Pass';
        second.Result__c = 'Pass';
        update new List<Test_Step_Result__c>{ first, second };
        Assert.areEqual('Passed',
            [SELECT Testing_Result__c FROM Test_Execution__c WHERE Id = :slot.Id].Testing_Result__c);
    }

    @IsTest
    static void stepDeleteCascadesAcrossExecutionsAndRecomputes() {
        UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
        Test_Case__c tc = UatTestDataFactory.makeCase(tax.mod.Id, 2, 1001);
        Test_Cycle__c cycle1 = UatTestDataFactory.makeCycle('Sprint 1', null, null, new List<Id>{ tc.Id });
        Test_Cycle__c cycle2 = UatTestDataFactory.makeCycle('Sprint 2', null, null, new List<Id>{ tc.Id });
        Test_Execution__c e1 = [SELECT Id FROM Test_Execution__c WHERE Test_Cycle__c = :cycle1.Id];
        Test_Execution__c e2 = [SELECT Id FROM Test_Execution__c WHERE Test_Cycle__c = :cycle2.Id];
        UatExecutionService.ensureStepResults(e1.Id);
        UatExecutionService.ensureStepResults(e2.Id);

        List<Test_Step__c> steps = [
            SELECT Id FROM Test_Step__c WHERE Test_Case__c = :tc.Id ORDER BY Step_Number__c
        ];
        // Answer step 1 on execution 1 only -> In Progress (1 of 2).
        Test_Step_Result__c answered = [
            SELECT Id FROM Test_Step_Result__c
            WHERE Test_Execution__c = :e1.Id AND Test_Step__c = :steps[0].Id
        ];
        answered.Result__c = 'Pass';
        update answered;
        Assert.areEqual('In Progress',
            [SELECT Testing_Status__c FROM Test_Execution__c WHERE Id = :e1.Id].Testing_Status__c);

        Test.startTest();
        delete steps[1]; // the unanswered step dies
        Test.stopTest();

        Assert.areEqual(0, [
            SELECT COUNT() FROM Test_Step_Result__c WHERE Test_Step__c = :steps[1].Id
        ], 'No orphaned results anywhere.');
        Assert.areEqual(1, [
            SELECT COUNT() FROM Test_Step_Result__c WHERE Test_Execution__c = :e2.Id
        ], 'Cascade reached the OTHER cycle\'s execution too (03 §9).');
        Assert.areEqual('Complete',
            [SELECT Testing_Status__c FROM Test_Execution__c WHERE Id = :e1.Id].Testing_Status__c,
            'Denominator shrank: the only unanswered step died, so the run completes.');
    }

    @IsTest
    static void identityKeyBlocksDuplicateTriples() {
        List<Test_Case__c> cases = threeCases();
        Test_Cycle__c cycle = UatTestDataFactory.makeCycle('Sprint 1', null, null, new List<Id>{ cases[0].Id });

        // The eager slot already holds (case0, cycle, UNCLAIMED) — a second
        // unclaimed slot for the same pair must be a DB-level failure.
        Database.SaveResult sr = Database.insert(new Test_Execution__c(
            Test_Case__c = cases[0].Id,
            Test_Cycle__c = cycle.Id,
            Testing_Status__c = 'Not Started'
        ), false);
        Assert.isFalse(sr.isSuccess(), 'Duplicate identity triple rejected at the DB.');
        Assert.areEqual(StatusCode.DUPLICATE_VALUE, sr.getErrors()[0].getStatusCode());
    }

    @IsTest
    static void resolveForIdentityFindsOrCreates() {
        List<Test_Case__c> cases = threeCases();
        Test_Cycle__c cycle = UatTestDataFactory.makeCycle('Sprint 1', null, null, new List<Id>{ cases[0].Id });
        Test_Execution__c slot = [SELECT Id FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id];

        // Unclaimed identity resolves to the existing slot, not a new record.
        Test_Execution__c resolved = UatExecutionService.resolveForIdentity(cases[0].Id, cycle.Id, null);
        Assert.areEqual(slot.Id, resolved.Id);

        // A standalone identity (no cycle) creates on first ask, finds on second.
        Test_Execution__c standalone1 = UatExecutionService.resolveForIdentity(cases[1].Id, null, tester1().Id);
        Test_Execution__c standalone2 = UatExecutionService.resolveForIdentity(cases[1].Id, null, tester1().Id);
        Assert.areEqual(standalone1.Id, standalone2.Id);
        Assert.isNull([SELECT Test_Cycle__c FROM Test_Execution__c WHERE Id = :standalone1.Id].Test_Cycle__c,
            'Standalone = null cycle, by design.');
    }

    // ---- Pool seats: capacity, release, stale (open-pool design) -----------------

    private static Test_Execution__c slotFor(Id cycleId, Id caseId) {
        List<Test_Execution__c> slots = [
            SELECT Id, Assigned_Tester__c, Claimed_Date__c, Released__c
            FROM Test_Execution__c
            WHERE Test_Cycle__c = :cycleId AND Test_Case__c = :caseId
            AND Assigned_Tester__c = null
            LIMIT 1
        ];
        return slots.isEmpty() ? null : slots[0];
    }

    private static Integer executionCount(Id cycleId, Id caseId) {
        return [
            SELECT COUNT() FROM Test_Execution__c
            WHERE Test_Cycle__c = :cycleId AND Test_Case__c = :caseId
        ];
    }

    @IsTest
    static void claimSeatRematerializesWhileSeatsRemain() {
        List<Test_Case__c> cases = threeCases();
        Test_Cycle__c cycle = UatTestDataFactory.makeCycle('Sprint 1', null, null, new List<Id>{ cases[0].Id });
        cycle.Max_Testers__c = 2;
        update cycle;

        Test.startTest();
        Test_Execution__c first = UatExecutionService.claimSeat(cycle.Id, cases[0].Id, tester1().Id);
        Test.stopTest();

        Assert.areEqual(tester1().Id,
            [SELECT Assigned_Tester__c FROM Test_Execution__c WHERE Id = :first.Id].Assigned_Tester__c);
        Assert.isNotNull(
            [SELECT Claimed_Date__c FROM Test_Execution__c WHERE Id = :first.Id].Claimed_Date__c,
            'Claim stamps Claimed_Date__c for stale detection.');
        Assert.areEqual(2, executionCount(cycle.Id, cases[0].Id),
            'A seat remained, so a fresh unclaimed slot re-materialized in the same transaction.');
        Assert.isNotNull(slotFor(cycle.Id, cases[0].Id), 'The new record is the open slot.');

        // Second claimant takes the last seat — no further slot.
        UatExecutionService.claimSeat(cycle.Id, cases[0].Id, tester2().Id);
        Assert.areEqual(2, executionCount(cycle.Id, cases[0].Id),
            'Last seat consumed the slot without re-materializing.');

        // Idempotent double-click: the claimer gets their own run back.
        Test_Execution__c again = UatExecutionService.claimSeat(cycle.Id, cases[0].Id, tester1().Id);
        Assert.areEqual(first.Id, again.Id);

        // A third tester finds the pool full.
        try {
            UatExecutionService.claimSeat(cycle.Id, cases[0].Id, tester3().Id);
            Assert.fail('Pool is at capacity — third claimant must be rejected.');
        } catch (UatExecutionService.PoolFullException e) {
            Assert.isTrue(e.getMessage().contains('beat you'), e.getMessage());
        }

        Assert.areEqual(2, [
            SELECT COUNT() FROM Test_Assignment_Event__c
            WHERE Test_Cycle__c = :cycle.Id AND Action__c = 'Claimed'
        ], 'One audit row per successful claim.');
    }

    @IsTest
    static void claimSeatAtDefaultCapacityRejectsSecondTester() {
        List<Test_Case__c> cases = threeCases();
        Test_Cycle__c cycle = UatTestDataFactory.makeCycle('Sprint 1', null, null, new List<Id>{ cases[0].Id });

        UatExecutionService.claimSeat(cycle.Id, cases[0].Id, tester1().Id);
        try {
            UatExecutionService.claimSeat(cycle.Id, cases[0].Id, tester2().Id);
            Assert.fail('Default capacity is 1 — the second claimant loses.');
        } catch (UatExecutionService.PoolFullException e) {
            Assert.isTrue(e.getMessage().contains('beat you'), e.getMessage());
        }
        Assert.areEqual(1, executionCount(cycle.Id, cases[0].Id), 'No slot left behind.');
    }

    /** True parallelism is impossible in Apex tests: the race seam makes the
     *  claim path treat its locked slot as consumed by a concurrent winner,
     *  exercising the one-retry (win on second lock) and the give-up path. */
    @IsTest
    static void claimSeatRaceRetryAndGiveUp() {
        List<Test_Case__c> cases = threeCases();
        Test_Cycle__c cycle = UatTestDataFactory.makeCycle('Sprint 1', null, null,
            new List<Id>{ cases[0].Id, cases[1].Id });

        // One simulated consumption -> the retry finds the (re-materialized)
        // slot and the claim silently succeeds.
        UatExecutionService.simulateConsumedSlots = 1;
        Test_Execution__c won = UatExecutionService.claimSeat(cycle.Id, cases[0].Id, tester1().Id);
        Assert.areEqual(tester1().Id,
            [SELECT Assigned_Tester__c FROM Test_Execution__c WHERE Id = :won.Id].Assigned_Tester__c,
            'Race loser transparently claimed the next slot on retry.');

        // Consumed on both attempts -> a clean pool-full failure, no mutation.
        UatExecutionService.simulateConsumedSlots = 2;
        try {
            UatExecutionService.claimSeat(cycle.Id, cases[1].Id, tester1().Id);
            Assert.fail('Both lock attempts lost the race — must surface pool-full.');
        } catch (UatExecutionService.PoolFullException e) {
            Assert.isTrue(e.getMessage().contains('beat you'), e.getMessage());
        } finally {
            UatExecutionService.simulateConsumedSlots = 0;
        }
        Assert.isNull(
            [SELECT Assigned_Tester__c FROM Test_Execution__c
             WHERE Test_Cycle__c = :cycle.Id AND Test_Case__c = :cases[1].Id LIMIT 1].Assigned_Tester__c,
            'The untouched slot is still unclaimed.');
    }

    @IsTest
    static void claimCapCountsOnlyOpenClaims() {
        List<Test_Case__c> cases = threeCases();
        Test_Cycle__c cycle = UatTestDataFactory.makeCycle('Sprint 1', null, null,
            new List<Id>{ cases[0].Id, cases[1].Id });
        cycle.Claim_Limit_Per_Tester__c = 1;
        update cycle;

        Test_Execution__c first = UatExecutionService.claimSeat(cycle.Id, cases[0].Id, tester1().Id);
        try {
            UatExecutionService.claimSeat(cycle.Id, cases[1].Id, tester1().Id);
            Assert.fail('Second open claim exceeds the per-tester cap.');
        } catch (UatExecutionService.ClaimCapException e) {
            Assert.isTrue(e.getMessage().contains('limit'), e.getMessage());
        }

        // Completing the run frees headroom — the cap throttles hoarding, not throughput.
        first.Testing_Status__c = 'Complete';
        update first;
        Test_Execution__c second = UatExecutionService.claimSeat(cycle.Id, cases[1].Id, tester1().Id);
        Assert.areEqual(tester1().Id,
            [SELECT Assigned_Tester__c FROM Test_Execution__c WHERE Id = :second.Id].Assigned_Tester__c);
    }

    @IsTest
    static void pausedCycleRefusesClaims() {
        List<Test_Case__c> cases = threeCases();
        Test_Cycle__c cycle = UatTestDataFactory.makeCycle('Sprint 1', null, null, new List<Id>{ cases[0].Id });
        cycle.Status__c = 'Claims Paused';
        update cycle;

        try {
            UatExecutionService.claimSeat(cycle.Id, cases[0].Id, tester1().Id);
            Assert.fail('Paused cycles take no new claims.');
        } catch (UatExecutionService.UatExecutionException e) {
            Assert.isTrue(e.getMessage().contains('claims'), e.getMessage());
        }
    }

    @IsTest
    static void releasePristineRevertsTheSameRecord() {
        List<Test_Case__c> cases = threeCases();
        Test_Cycle__c cycle = UatTestDataFactory.makeCycle('Sprint 1', null, null, new List<Id>{ cases[0].Id });
        Test_Execution__c claimed = UatExecutionService.claimSeat(cycle.Id, cases[0].Id, tester1().Id);

        Test.startTest();
        UatExecutionService.releaseSeat(claimed.Id, tester1().Id, 'Out sick this week', 'Released');
        Test.stopTest();

        Test_Execution__c reverted = [
            SELECT Assigned_Tester__c, Claimed_Date__c, Released__c
            FROM Test_Execution__c WHERE Id = :claimed.Id
        ];
        Assert.isNull(reverted.Assigned_Tester__c, 'Pristine release reverts the record to the slot.');
        Assert.isNull(reverted.Claimed_Date__c);
        Assert.isFalse(reverted.Released__c);
        Assert.areEqual(1, executionCount(cycle.Id, cases[0].Id), 'No extra records.');

        Test_Assignment_Event__c event = [
            SELECT Action__c, Tester__c, Actor__c, Reason__c
            FROM Test_Assignment_Event__c
            WHERE Test_Cycle__c = :cycle.Id AND Action__c = 'Released'
        ];
        Assert.areEqual(tester1().Id, event.Tester__c);
        Assert.areEqual('Out sick this week', event.Reason__c);
    }

    @IsTest
    static void releaseNonPristineKeepsHistoryAndResumeReclaims() {
        List<Test_Case__c> cases = threeCases();
        Test_Cycle__c cycle = UatTestDataFactory.makeCycle('Sprint 1', null, null, new List<Id>{ cases[0].Id });
        Test_Execution__c claimed = UatExecutionService.claimSeat(cycle.Id, cases[0].Id, tester1().Id);

        // Record real work so the release must preserve it.
        List<Test_Step_Result__c> results = UatExecutionService.ensureStepResults(claimed.Id);
        results[0].Result__c = 'Pass';
        update results[0];

        Test.startTest();
        UatExecutionService.releaseSeat(claimed.Id, tester1().Id, 'Switching priorities', 'Released');
        Test.stopTest();

        Test_Execution__c kept = [
            SELECT Assigned_Tester__c, Released__c FROM Test_Execution__c WHERE Id = :claimed.Id
        ];
        Assert.areEqual(tester1().Id, kept.Assigned_Tester__c,
            'Non-pristine release keeps the run with the tester stamped — never merged away.');
        Assert.isTrue(kept.Released__c);
        Assert.areEqual(2, executionCount(cycle.Id, cases[0].Id),
            'A fresh unclaimed slot reopened the seat.');

        // Re-claiming resumes the tester's OWN partial run and retires the slot.
        Test_Execution__c resumed = UatExecutionService.claimSeat(cycle.Id, cases[0].Id, tester1().Id);
        Assert.areEqual(claimed.Id, resumed.Id, 'Resume, not a fresh record.');
        Assert.isFalse(
            [SELECT Released__c FROM Test_Execution__c WHERE Id = :claimed.Id].Released__c);
        Assert.areEqual(1, executionCount(cycle.Id, cases[0].Id),
            'The surplus slot was deleted when the resume refilled the last seat.');
        Assert.areEqual(1, [
            SELECT COUNT() FROM Test_Step_Result__c
            WHERE Test_Execution__c = :claimed.Id AND Result__c = 'Pass'
        ], 'Their partial work survived the round trip.');
    }

    @IsTest
    static void reassignFreesOldSeatAndHandsIndependentRun() {
        List<Test_Case__c> cases = threeCases();
        Test_Cycle__c cycle = UatTestDataFactory.makeCycle('Sprint 1', null, null, new List<Id>{ cases[0].Id });
        Test_Execution__c claimed = UatExecutionService.claimSeat(cycle.Id, cases[0].Id, tester1().Id);
        List<Test_Step_Result__c> results = UatExecutionService.ensureStepResults(claimed.Id);
        results[0].Result__c = 'Fail';
        update results[0];

        Test.startTest();
        Test_Execution__c fresh = UatExecutionService.reassignSeat(
            claimed.Id, tester2().Id, tester3().Id, 'Tester left the project');
        Test.stopTest();

        Assert.areNotEqual(claimed.Id, fresh.Id, 'The new tester gets their OWN execution.');
        Assert.areEqual(tester2().Id,
            [SELECT Assigned_Tester__c FROM Test_Execution__c WHERE Id = :fresh.Id].Assigned_Tester__c);
        Assert.isTrue(
            [SELECT Released__c FROM Test_Execution__c WHERE Id = :claimed.Id].Released__c,
            'The old run is history, its recorded results untouched.');
        Assert.isNull(slotFor(cycle.Id, cases[0].Id),
            'Net seats unchanged (1 of 1) — no unclaimed slot reopened.');

        Set<String> actions = new Set<String>();
        for (Test_Assignment_Event__c e : [
            SELECT Action__c FROM Test_Assignment_Event__c WHERE Test_Cycle__c = :cycle.Id
        ]) {
            actions.add(e.Action__c);
        }
        Assert.isTrue(actions.contains('Force Unassigned'), 'Old seat audited: ' + actions);
        Assert.isTrue(actions.contains('Reassigned'), 'New seat audited: ' + actions);
    }

    @IsTest
    static void reconcileSeatsFollowsCapacityEdits() {
        List<Test_Case__c> cases = threeCases();
        Test_Cycle__c cycle = UatTestDataFactory.makeCycle('Sprint 1', null, null, new List<Id>{ cases[0].Id });
        UatExecutionService.claimSeat(cycle.Id, cases[0].Id, tester1().Id);
        Assert.areEqual(1, executionCount(cycle.Id, cases[0].Id), 'Capacity 1: seat full, no slot.');

        // Raise capacity -> the missing slot opens.
        cycle.Max_Testers__c = 2;
        update cycle;
        UatExecutionService.reconcileSeats(new Set<Id>{ cycle.Id });
        Assert.areEqual(2, executionCount(cycle.Id, cases[0].Id), 'Raised capacity opened a slot.');

        // Lower it back -> the surplus pristine slot retires.
        cycle.Max_Testers__c = 1;
        update cycle;
        UatExecutionService.reconcileSeats(new Set<Id>{ cycle.Id });
        Assert.areEqual(1, executionCount(cycle.Id, cases[0].Id), 'Lowered capacity retired the slot.');
    }

    @IsTest
    static void staleClaimsAutoReleaseAfterCycleWindow() {
        List<Test_Case__c> cases = threeCases();
        Test_Cycle__c cycle = UatTestDataFactory.makeCycle('Sprint 1', null, null,
            new List<Id>{ cases[0].Id, cases[1].Id });
        cycle.Stale_Claim_Days__c = 7;
        update cycle;

        // Claim both; start one (In Progress must survive the sweep).
        Test_Execution__c idle = UatExecutionService.claimSeat(cycle.Id, cases[0].Id, tester1().Id);
        Test_Execution__c started = UatExecutionService.claimSeat(cycle.Id, cases[1].Id, tester2().Id);
        started.Testing_Status__c = 'In Progress';
        update started;

        Test.startTest();
        UatExecutionService.nowOverride = System.now().addDays(8);
        Integer released = UatExecutionService.releaseStaleClaims(tester3().Id);
        UatExecutionService.nowOverride = null;
        Test.stopTest();

        Assert.areEqual(1, released, 'Only the never-started claim is stale.');
        Assert.isNull(
            [SELECT Assigned_Tester__c FROM Test_Execution__c WHERE Id = :idle.Id].Assigned_Tester__c,
            'The stale seat went back to the pool (pristine revert).');
        Assert.areEqual(tester2().Id,
            [SELECT Assigned_Tester__c FROM Test_Execution__c WHERE Id = :started.Id].Assigned_Tester__c,
            'In-progress work is never auto-released.');
        Test_Assignment_Event__c event = [
            SELECT Tester__c, Actor__c, Reason__c FROM Test_Assignment_Event__c
            WHERE Action__c = 'Auto Released'
        ];
        Assert.areEqual(tester1().Id, event.Tester__c);
        Assert.isTrue(event.Reason__c.contains('7 days'), event.Reason__c);
    }
}