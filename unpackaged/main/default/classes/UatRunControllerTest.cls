/**
 * Tests for UatRunController — the tester surface: queue/pool visibility
 * rules, claim-and-start, pool claims and releases, step-result saves rolling
 * up live, save-and-exit floor, submit, evidence plumbing, and the
 * audience-scoped exploratory log.
 */
@IsTest
private class UatRunControllerTest {

    @TestSetup
    static void setup() {
        UatTestDataFactory.createTesterUser('uattst1');
        UatTestDataFactory.createTesterUser('uattst2');
        UatTestDataFactory.createTesterUser('uatout');  // UAT_Tester, not on any team
        UatTestDataFactory.createUser('uatnone', null); // no UAT access at all
        UatTestDataFactory.createAdminUser('uatadm');   // UAT_Console moderation override
    }

    private static User byLastName(String lastName) {
        return [SELECT Id FROM User WHERE LastName = :lastName LIMIT 1];
    }

    /** Team of tester1+tester2, one 2-step case in a cycle. */
    private static Test_Cycle__c standardFixture() {
        UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
        Test_Case__c tc = UatTestDataFactory.makeCase(tax.mod.Id, 2, 1001);
        Team__c team = UatTestDataFactory.makeTeam('Alpha', new List<Id>{
            byLastName('UAT uattst1').Id, byLastName('UAT uattst2').Id
        });
        return UatTestDataFactory.makeCycle('Sprint 1', team.Id, null, new List<Id>{ tc.Id });
    }

    @IsTest
    static void queueAndPoolVisibilityRules() {
        Test_Cycle__c cycle = standardFixture();

        // Queue = strictly my claimed work; the claimable seat lives in the
        // pool. The cycle group still shows for the always-present
        // Exploratory card.
        System.runAs(byLastName('UAT uattst1')) {
            UatRunController.QueueDTO queue = UatRunController.getQueue();
            Assert.areEqual(1, queue.cycleGroups.size(), 'Cycle group visible to team member.');
            Assert.areEqual(0, queue.cycleGroups[0].cards.size(),
                'Unclaimed seats are pool cards now, not queue cards.');
            Assert.isNull(queue.standalone, 'No standalone group when empty.');

            List<UatRunController.PoolGroupDTO> pool = UatRunController.getPool();
            Assert.areEqual(1, pool.size(), 'Team member sees the pool group.');
            Assert.areEqual(1, pool[0].cards.size());
            Assert.areEqual(1, pool[0].cards[0].seatsMax, 'Default capacity is 1.');
            Assert.areEqual(0, pool[0].cards[0].seatsTaken);
        }

        // A tester on no team sees neither this cycle's queue group nor its pool.
        System.runAs(byLastName('UAT uatout')) {
            Assert.areEqual(0, UatRunController.getQueue().cycleGroups.size(),
                'Outsider sees no cycles.');
            Assert.areEqual(0, UatRunController.getPool().size(),
                'Team-scoped pool hidden from outsiders.');
        }

        // Once tester1 claims, the card is in THEIR queue and out of the pool.
        Test_Execution__c slot = [SELECT Id FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id];
        System.runAs(byLastName('UAT uattst1')) {
            UatRunController.claimAndStart(slot.Id);
            UatRunController.QueueDTO queue = UatRunController.getQueue();
            Assert.areEqual(1, queue.cycleGroups[0].cards.size(), 'Claimed run is mine.');
            Assert.areEqual('Start', queue.cycleGroups[0].cards[0].actionLabel,
                'Nothing answered yet — the claimed run starts from the queue.');
        }
        System.runAs(byLastName('UAT uattst2')) {
            Assert.areEqual(0, UatRunController.getQueue().cycleGroups[0].cards.size(),
                'Someone else\'s claim is not in my queue.');
            Assert.areEqual(0, UatRunController.getPool().size(),
                'Seat consumed — nothing claimable remains.');
        }
    }

    /** Multi-seat pools (Max_Testers__c = 2): claiming re-materializes the
     *  next open slot, which must NOT re-appear for the claimer — any
     *  unreleased run of mine (Complete included) hides the case from MY
     *  pool while other testers still see it. Releasing restores it. */
    @IsTest
    static void poolHidesCasesIAlreadyHold() {
        UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
        Test_Case__c tc = UatTestDataFactory.makeCase(tax.mod.Id, 2, 1001);
        Team__c team = UatTestDataFactory.makeTeam('Alpha', new List<Id>{
            byLastName('UAT uattst1').Id, byLastName('UAT uattst2').Id
        });
        Test_Cycle__c cycle = UatTestDataFactory.makeCycle('Sprint 1', team.Id, null,
            new List<Id>{ tc.Id }, 2);

        Id myExecId;
        System.runAs(byLastName('UAT uattst1')) {
            myExecId = UatRunController.claimCase(cycle.Id, tc.Id);
            Assert.areEqual(0, UatRunController.getPool().size(),
                'The re-materialized seat on a case I hold is hidden from my pool (no empty group).');
        }
        System.runAs(byLastName('UAT uattst2')) {
            List<UatRunController.PoolGroupDTO> pool = UatRunController.getPool();
            Assert.areEqual(1, pool.size(), 'The other tester still sees the open seat.');
            Assert.areEqual(1, pool[0].cards.size());
            Assert.areEqual(1, pool[0].cards[0].seatsTaken, 'Seat chip reads 1 of 2 claimed.');
        }

        update new Test_Execution__c(Id = myExecId, Testing_Status__c = 'Complete');
        System.runAs(byLastName('UAT uattst1')) {
            Assert.areEqual(0, UatRunController.getPool().size(),
                'A Complete-but-unreleased run still hides the case — I already ran it.');

            UatRunController.releaseClaim(JSON.serialize(new Map<String, Object>{
                'executionId' => myExecId, 'reason' => 'Picked it by mistake'
            }));
            Assert.areEqual(1, UatRunController.getPool().size(),
                'Releasing restores the case to my pool for a deliberate resume.');
        }
    }

    /** Claim-all must skip cases I already hold instead of re-claiming them
     *  (claimSeat is idempotent, so before the skip each no-op inflated
     *  tally.claimed). */
    @IsTest
    static void claimAllSkipsCasesIAlreadyHold() {
        UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
        Test_Case__c first = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1001);
        Test_Case__c second = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1002);
        Team__c team = UatTestDataFactory.makeTeam('Alpha', new List<Id>{
            byLastName('UAT uattst1').Id
        });
        Test_Cycle__c cycle = UatTestDataFactory.makeCycle('Sprint 1', team.Id, null,
            new List<Id>{ first.Id, second.Id }, 2);

        System.runAs(byLastName('UAT uattst1')) {
            UatRunController.claimCase(cycle.Id, first.Id);

            Test.startTest();
            UatRunController.BulkClaimResultDTO tally = UatRunController.claimAllAvailable(cycle.Id);
            Test.stopTest();

            Assert.areEqual(1, tally.claimed,
                'Only the case I did not already hold is claimed.');
            Assert.areEqual(2, [
                SELECT COUNT() FROM Test_Execution__c
                WHERE Test_Cycle__c = :cycle.Id
                AND Assigned_Tester__c = :UserInfo.getUserId() AND Released__c = false
            ], 'One run per case, no duplicates.');
        }
    }

    /** The runner surfaces the case's pre-conditions and per-step titles. */
    @IsTest
    static void runnerCarriesPreConditionsAndStepTitles() {
        UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
        Test_Case__c tc = UatTestDataFactory.makeCase(tax.mod.Id, 2, 1001);
        update new Test_Case__c(Id = tc.Id, Pre_Conditions__c = 'Log in as an advisor.');
        Test_Step__c first = [
            SELECT Id FROM Test_Step__c WHERE Test_Case__c = :tc.Id
            ORDER BY Step_Number__c LIMIT 1
        ];
        update new Test_Step__c(Id = first.Id, Step_Title__c = 'Open household');
        Team__c team = UatTestDataFactory.makeTeam('Alpha', new List<Id>{
            byLastName('UAT uattst1').Id
        });
        Test_Cycle__c cycle = UatTestDataFactory.makeCycle('Sprint 1', team.Id, null,
            new List<Id>{ tc.Id });

        System.runAs(byLastName('UAT uattst1')) {
            Id execId = UatRunController.claimCase(cycle.Id, tc.Id);
            Test.startTest();
            UatRunController.RunnerDTO runner = UatRunController.startExecution(execId);
            Test.stopTest();
            Assert.areEqual('Log in as an advisor.', runner.preConditions,
                'Runner carries the case pre-conditions.');
            Assert.areEqual('Open household', runner.steps[0].stepTitle,
                'Per-step title rides the step DTO.');
            Assert.isNull(runner.steps[1].stepTitle, 'Untitled steps stay null.');
        }
    }

    @IsTest
    static void queueCardsCarryStepProgress() {
        UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
        Test_Case__c scripted = UatTestDataFactory.makeCase(tax.mod.Id, 3, 1001);
        UatTestDataFactory.makeExploreStep(scripted.Id, 4);
        Test_Case__c stepless = UatTestDataFactory.makeCase(tax.mod.Id, 0, 1002);
        Team__c team = UatTestDataFactory.makeTeam('Alpha', new List<Id>{ byLastName('UAT uattst1').Id });
        Test_Cycle__c cycle = UatTestDataFactory.makeCycle('Sprint 1', team.Id, null,
            new List<Id>{ scripted.Id, stepless.Id });

        System.runAs(byLastName('UAT uattst1')) {
            Id execScripted = UatRunController.claimCase(cycle.Id, scripted.Id);
            UatRunController.claimCase(cycle.Id, stepless.Id);
            UatRunController.RunnerDTO runner = UatRunController.startExecution(execScripted);
            Assert.areEqual(4, runner.steps.size(), '3 scripted + 1 explore.');
            // Answer two scripted steps AND the explore row — the explore
            // answer must not inflate the step math on either side.
            UatRunController.saveStepResult(JSON.serialize(new Map<String, Object>{
                'resultId' => runner.steps[0].resultId, 'result' => 'Pass'
            }));
            UatRunController.saveStepResult(JSON.serialize(new Map<String, Object>{
                'resultId' => runner.steps[1].resultId, 'result' => 'Pass'
            }));
            UatRunController.saveStepResult(JSON.serialize(new Map<String, Object>{
                'resultId' => runner.steps[3].resultId, 'result' => 'Pass',
                'exploreNotes' => 'Poked around'
            }));

            Test.startTest();
            UatRunController.QueueDTO queue = UatRunController.getQueue();
            Test.stopTest();

            Assert.areEqual(2, queue.cycleGroups[0].cards.size());
            UatRunController.QueueCardDTO cardScripted;
            UatRunController.QueueCardDTO cardStepless;
            for (UatRunController.QueueCardDTO card : queue.cycleGroups[0].cards) {
                if (card.caseId == scripted.Id) {
                    cardScripted = card;
                } else {
                    cardStepless = card;
                }
            }
            Assert.areEqual(3, cardScripted.stepsTotal,
                'Denominator = scripted steps only; the explore step is excluded.');
            Assert.areEqual(2, cardScripted.stepsAnswered,
                'Numerator = answered scripted results; the explore answer is excluded.');
            Assert.areEqual(0, cardScripted.stepsFailed, 'All answers Pass — 0, not null.');
            Assert.areEqual(0, cardScripted.stepsBlocked);
            Assert.areEqual(0, cardStepless.stepsTotal, 'Stepless case reports 0, not null.');
            Assert.areEqual(0, cardStepless.stepsAnswered);
            Assert.areEqual(0, cardStepless.stepsFailed);
            Assert.areEqual(0, cardStepless.stepsBlocked);
        }
    }

    @IsTest
    static void queueCardsBreakDownFailedAndBlockedSteps() {
        UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
        Test_Case__c tc = UatTestDataFactory.makeCase(tax.mod.Id, 3, 1001);
        UatTestDataFactory.makeExploreStep(tc.Id, 4);
        Team__c team = UatTestDataFactory.makeTeam('Alpha', new List<Id>{ byLastName('UAT uattst1').Id });
        Test_Cycle__c cycle = UatTestDataFactory.makeCycle('Sprint 1', team.Id, null, new List<Id>{ tc.Id });

        System.runAs(byLastName('UAT uattst1')) {
            Id execId = UatRunController.claimCase(cycle.Id, tc.Id);
            UatRunController.RunnerDTO runner = UatRunController.startExecution(execId);
            UatRunController.saveStepResult(JSON.serialize(new Map<String, Object>{
                'resultId' => runner.steps[0].resultId, 'result' => 'Pass'
            }));
            UatRunController.saveStepResult(JSON.serialize(new Map<String, Object>{
                'resultId' => runner.steps[1].resultId, 'result' => 'Fail'
            }));
            UatRunController.saveStepResult(JSON.serialize(new Map<String, Object>{
                'resultId' => runner.steps[2].resultId, 'result' => 'Blocked'
            }));
            // The explore answer must not leak into any of the three counts.
            UatRunController.saveStepResult(JSON.serialize(new Map<String, Object>{
                'resultId' => runner.steps[3].resultId, 'result' => 'Fail',
                'exploreNotes' => 'Explore fail must not count'
            }));

            Test.startTest();
            UatRunController.QueueDTO queue = UatRunController.getQueue();
            Test.stopTest();

            UatRunController.QueueCardDTO card = queue.cycleGroups[0].cards[0];
            Assert.areEqual(3, card.stepsAnswered, 'Sum across verdicts, explore excluded.');
            Assert.areEqual(1, card.stepsFailed);
            Assert.areEqual(1, card.stepsBlocked);
        }
    }

    @IsTest
    static void queueCardsExposeSystemAndLastUpdated() {
        Test_Cycle__c cycle = standardFixture();
        Test_Execution__c slot = [SELECT Id FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id];
        System.runAs(byLastName('UAT uattst1')) {
            UatRunController.claimAndStart(slot.Id);

            Test.startTest();
            UatRunController.QueueDTO queue = UatRunController.getQueue();
            Test.stopTest();

            UatRunController.QueueCardDTO card = queue.cycleGroups[0].cards[0];
            Assert.areEqual('Helios System', card.systemName,
                'Functional area resolves through Module › Group › System.');
            Assert.isNotNull(card.lastUpdated, 'LastModifiedDate exposed for the recency label.');
        }
    }

    @IsTest
    static void queueSummaryCountsMatchBuckets() {
        UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
        Test_Case__c untouched = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1001);
        Test_Case__c started = UatTestDataFactory.makeCase(tax.mod.Id, 2, 1002);
        Test_Case__c finished = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1003);
        Test_Case__c stuck = UatTestDataFactory.makeCase(tax.mod.Id, 2, 1004);
        Team__c team = UatTestDataFactory.makeTeam('Alpha', new List<Id>{ byLastName('UAT uattst1').Id });
        Test_Cycle__c cycle = UatTestDataFactory.makeCycle('Sprint Mix', team.Id, null,
            new List<Id>{ untouched.Id, started.Id, finished.Id, stuck.Id });

        // Stamp the four bucket states directly — the flows that produce
        // them are covered by runnerFlowClaimAnswerSubmit and
        // dashboardCompleteBlockedBucketsAsBlocked; walking the runner four
        // times here blew the setup SOQL limit before Test.startTest().
        Id me = byLastName('UAT uattst1').Id;
        List<Test_Execution__c> slots = [
            SELECT Id, Test_Case__c FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id
        ];
        for (Test_Execution__c e : slots) {
            e.Assigned_Tester__c = me;
            e.Claimed_Date__c = Datetime.now();
            if (e.Test_Case__c == started.Id) {
                e.Testing_Status__c = 'In Progress';
            } else if (e.Test_Case__c == finished.Id) {
                e.Testing_Status__c = 'Complete';
                e.Testing_Result__c = 'Passed';
            } else if (e.Test_Case__c == stuck.Id) {
                e.Testing_Status__c = 'Complete';
                e.Testing_Result__c = 'Blocked';
            } // untouched stays Not Started
        }
        update slots;

        System.runAs(byLastName('UAT uattst1')) {
            Test.startTest();
            UatRunController.QueueDTO queue = UatRunController.getQueue();
            UatRunController.DashboardDTO dash = UatRunController.getDashboard(null);
            Test.stopTest();

            Assert.areEqual(4, queue.summary.total);
            Assert.areEqual(1, queue.summary.notStarted);
            Assert.areEqual(1, queue.summary.inProgress);
            Assert.areEqual(1, queue.summary.completed,
                'Only the clean Complete counts as completed.');
            Assert.areEqual(1, queue.summary.blocked,
                'Complete with a Blocked verdict files under blocked, not completed.');

            // The dashboard consumes the same tally — one source of truth.
            Assert.areEqual(queue.summary.total, dash.queueSummary.total);
            Assert.areEqual(queue.summary.blocked, dash.queueSummary.blocked);
            Assert.areEqual(queue.summary.completed, dash.queueSummary.completed);
        }
    }

    /**
     * A Complete run whose verdict is Failed is DONE — the failure is the
     * finding, not a reason to keep the run open. Untested until a tester read
     * a half-answered run's "1 failed step" as the blocker and filed the
     * status as a bug (2026-08-13); the real defect was the runner letting a
     * step be saved with notes and no verdict.
     */
    @IsTest
    static void completeWithFailedVerdictCountsAsCompleted() {
        UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
        Test_Case__c tc = UatTestDataFactory.makeCase(tax.mod.Id, 2, 1001);
        Team__c team = UatTestDataFactory.makeTeam('Alpha', new List<Id>{ byLastName('UAT uattst1').Id });
        Test_Cycle__c cycle = UatTestDataFactory.makeCycle('Sprint Fail', team.Id, null,
            new List<Id>{ tc.Id });

        Id me = byLastName('UAT uattst1').Id;
        Test_Execution__c slot = [
            SELECT Id FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id LIMIT 1
        ];
        slot.Assigned_Tester__c = me;
        slot.Claimed_Date__c = Datetime.now();
        slot.Testing_Status__c = 'Complete';
        slot.Testing_Result__c = 'Failed';
        update slot;

        System.runAs(byLastName('UAT uattst1')) {
            Test.startTest();
            UatRunController.QueueDTO queue = UatRunController.getQueue();
            Test.stopTest();

            Assert.areEqual(1, queue.summary.completed,
                'A Failed verdict does not stop a fully answered run from being completed.');
            Assert.areEqual(0, queue.summary.inProgress);
            Assert.areEqual(0, queue.summary.blocked);
        }
    }

    /**
     * Open Pool's preview. The load-bearing assertion is the negative one: the
     * read must not create Test_Step_Result__c rows, because the tester has
     * not claimed the seat. startExecution's ensureStepResults is exactly what
     * getCasePreview omits — if the two ever converge, browsing the pool starts
     * writing against seats nobody holds.
     */
    @IsTest
    static void casePreviewReadsACaseWithoutClaimingOrWriting() {
        UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
        Test_Case__c tc = UatTestDataFactory.makeCase(tax.mod.Id, 2, 1001);
        UatTestDataFactory.makeExploreStep(tc.Id, 3);
        update new Test_Case__c(
            Id = tc.Id,
            Description__c = 'Covers relating a professional to a household.',
            Pre_Conditions__c = 'A staged household exists.'
        );
        Team__c team = UatTestDataFactory.makeTeam('Alpha', new List<Id>{
            byLastName('UAT uattst1').Id
        });
        Test_Cycle__c cycle = UatTestDataFactory.makeCycle('Sprint Preview', team.Id, null,
            new List<Id>{ tc.Id });
        Test_Execution__c slot = [
            SELECT Id, Assigned_Tester__c FROM Test_Execution__c
            WHERE Test_Cycle__c = :cycle.Id LIMIT 1
        ];
        Assert.areEqual(null, slot.Assigned_Tester__c, 'Fixture must be an unclaimed seat.');

        System.runAs(byLastName('UAT uattst1')) {
            Test.startTest();
            UatRunController.RunnerDTO dto = UatRunController.getCasePreview(slot.Id);
            Test.stopTest();

            Assert.areEqual('Covers relating a professional to a household.', dto.description,
                'The preview carries the full description, not the pool card\'s blurb.');
            Assert.areEqual('A staged household exists.', dto.preConditions);
            Assert.areEqual(3, dto.steps.size(), '2 scripted + 1 exploratory.');
            Assert.areEqual('Do thing 1', dto.steps[0].description);
            Assert.areEqual('Thing 1 happens', dto.steps[0].expected);
            Assert.isTrue(dto.steps[2].isExplore);
            Assert.areEqual(null, dto.steps[0].resultId,
                'A previewed step has no result row to point at.');
            Assert.areEqual(null, dto.steps[0].result);
        }

        Assert.areEqual(0, [
            SELECT COUNT() FROM Test_Step_Result__c WHERE Test_Execution__c = :slot.Id
        ], 'Previewing must never materialize step results for an unclaimed seat.');
        Assert.areEqual(null, [
            SELECT Assigned_Tester__c FROM Test_Execution__c WHERE Id = :slot.Id
        ].Assigned_Tester__c, 'Previewing must never claim the seat.');
    }

    @IsTest
    static void casePreviewRejectsATesterOutsideTheAudience() {
        Test_Cycle__c cycle = standardFixture(); // team = tester1 + tester2
        Test_Execution__c slot = [
            SELECT Id FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id LIMIT 1
        ];

        System.runAs(byLastName('UAT uatout')) { // UAT_Tester, on no team
            Test.startTest();
            try {
                UatRunController.getCasePreview(slot.Id);
                Assert.fail('An out-of-audience tester must not be able to read the case.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('isn\'t assigned to you'),
                    'Unexpected message: ' + e.getMessage());
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void teamlessCycleOpensPoolToEveryTester() {
        UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
        Test_Case__c tc = UatTestDataFactory.makeCase(tax.mod.Id, 2, 1001);
        UatTestDataFactory.makeCycle('Open Sprint', null, null, new List<Id>{ tc.Id });

        // No team on the cycle = the whole tester pool is the audience —
        // including a tester on no team at all.
        System.runAs(byLastName('UAT uatout')) {
            List<UatRunController.PoolGroupDTO> pool = UatRunController.getPool();
            Assert.areEqual(1, pool.size(), 'Teamless cycle is open to the whole pool.');
            Id claimedId = UatRunController.claimCase(pool[0].cards[0].cycleId, pool[0].cards[0].caseId);
            Assert.areEqual(byLastName('UAT uatout').Id, [
                SELECT Assigned_Tester__c FROM Test_Execution__c WHERE Id = :claimedId
            ].Assigned_Tester__c);
        }
    }

    @IsTest
    static void claimCaseLostRaceSurfacesCleanly() {
        Test_Cycle__c cycle = standardFixture();
        Test_Case__c tc = [SELECT Id FROM Test_Case__c LIMIT 1];

        System.runAs(byLastName('UAT uattst1')) {
            UatRunController.claimCase(cycle.Id, tc.Id);
        }
        // Capacity 1: the second tester's claim fails with the exact prose the
        // pool toasts, and no stray records appear.
        System.runAs(byLastName('UAT uattst2')) {
            try {
                UatRunController.claimCase(cycle.Id, tc.Id);
                Assert.fail('Second claimant must lose the last seat.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('beat you'), e.getMessage());
            }
        }
        Assert.areEqual(1, [SELECT COUNT() FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id]);
    }

    @IsTest
    static void ineligibleClaimsAreRejected() {
        Test_Cycle__c cycle = standardFixture();
        Test_Case__c tc = [SELECT Id FROM Test_Case__c LIMIT 1];

        // A tester outside the cycle's team fails the audience gate.
        System.runAs(byLastName('UAT uatout')) {
            try {
                UatRunController.claimCase(cycle.Id, tc.Id);
                Assert.fail('Outside the cycle\'s team — claim must be rejected.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('another team'), e.getMessage());
            }
        }
        // A user without UAT_Tester has no access at all.
        System.runAs(byLastName('UAT uatnone')) {
            try {
                UatRunController.claimCase(cycle.Id, tc.Id);
                Assert.fail('No UAT access — claim must be rejected.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('access'), e.getMessage());
            }
        }
        Assert.isNull([
            SELECT Assigned_Tester__c FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id
        ].Assigned_Tester__c, 'The seat is untouched.');
    }

    @IsTest
    static void releaseClaimRequiresReasonAndOwnership() {
        Test_Cycle__c cycle = standardFixture();
        Test_Execution__c slot = [SELECT Id FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id];
        System.runAs(byLastName('UAT uattst1')) {
            UatRunController.claimAndStart(slot.Id);
        }

        // No reason -> rejected.
        System.runAs(byLastName('UAT uattst1')) {
            try {
                UatRunController.releaseClaim(JSON.serialize(new Map<String, Object>{
                    'executionId' => slot.Id
                }));
                Assert.fail('A release without a reason must be rejected.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('reason'), e.getMessage());
            }
        }
        // Someone else's run -> rejected.
        System.runAs(byLastName('UAT uattst2')) {
            try {
                UatRunController.releaseClaim(JSON.serialize(new Map<String, Object>{
                    'executionId' => slot.Id, 'reason' => 'not mine'
                }));
                Assert.fail('Only the claimant releases their own run.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('yours'), e.getMessage());
            }
        }
        // The claimant with a reason -> seat back in the pool, audited.
        System.runAs(byLastName('UAT uattst1')) {
            Test.startTest();
            UatRunController.releaseClaim(JSON.serialize(new Map<String, Object>{
                'executionId' => slot.Id, 'reason' => 'Pulled onto a prod issue'
            }));
            Test.stopTest();
            Assert.areEqual(0, UatRunController.getQueue().cycleGroups[0].cards.size(),
                'Released run leaves my queue.');
            Assert.areEqual(1, UatRunController.getPool()[0].cards.size(),
                'The seat is claimable again.');
        }
        List<Test_Assignment_Event__c> released = [
            SELECT Reason__c FROM Test_Assignment_Event__c WHERE Action__c = 'Released'
        ];
        Assert.areEqual(1, released.size());
        Assert.areEqual('Pulled onto a prod issue', released[0].Reason__c);
    }

    @IsTest
    static void bulkClaimReportsTally() {
        UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
        Test_Case__c case1 = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1001);
        Test_Case__c case2 = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1002);
        Test_Case__c case3 = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1003);
        Team__c team = UatTestDataFactory.makeTeam('Alpha', new List<Id>{
            byLastName('UAT uattst1').Id, byLastName('UAT uattst2').Id
        });
        Test_Cycle__c cycle = UatTestDataFactory.makeCycle('Sprint 1', team.Id, null,
            new List<Id>{ case1.Id, case2.Id, case3.Id });
        cycle.Claim_Limit_Per_Tester__c = 2;
        update cycle;

        // Another tester got one first.
        System.runAs(byLastName('UAT uattst2')) {
            UatRunController.claimCase(cycle.Id, case1.Id);
        }

        System.runAs(byLastName('UAT uattst1')) {
            Test.startTest();
            UatRunController.BulkClaimResultDTO tally = UatRunController.claimAllAvailable(cycle.Id);
            Test.stopTest();
            Assert.areEqual(2, tally.claimed, 'Both open seats claimed.');
            Assert.areEqual(0, tally.takenByOthers,
                'The taken seat had no slot left, so it never entered the sweep.');
            Assert.isFalse(tally.capReached, 'Cap of 2 exactly fits the two claims.');
        }
        Assert.areEqual(2, [
            SELECT COUNT() FROM Test_Execution__c
            WHERE Test_Cycle__c = :cycle.Id
            AND Assigned_Tester__c = :byLastName('UAT uattst1').Id
        ]);
    }

    @IsTest
    static void findingsAreAudienceScoped() {
        Test_Cycle__c cycle = standardFixture();
        System.runAs(byLastName('UAT uattst1')) {
            UatRunController.saveFinding(JSON.serialize(new Map<String, Object>{
                'cycleId' => cycle.Id,
                'title' => 'Dashboard panel renders blank',
                'type' => 'Question',
                'whatTesting' => 'Poking the dashboard',
                'whatHappened' => 'Blank panel'
            }));
        }
        // A tester outside the cycle's audience can no longer read or write
        // its findings (open-pool design §8 tightening).
        System.runAs(byLastName('UAT uatout')) {
            try {
                UatRunController.getFindings(cycle.Id);
                Assert.fail('Findings are audience-scoped now.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('another team'), e.getMessage());
            }
        }
    }

    @IsTest
    static void closedCyclesLeaveTheQueue() {
        Test_Cycle__c cycle = standardFixture();

        System.runAs(byLastName('UAT uattst1')) {
            Assert.areEqual(1, UatRunController.getQueue().cycleGroups.size(),
                'Active cycle visible before closing.');
        }

        cycle.Status__c = 'Closed';
        update cycle;
        System.runAs(byLastName('UAT uattst1')) {
            UatRunController.QueueDTO queue = UatRunController.getQueue();
            Assert.areEqual(0, queue.cycleGroups.size(),
                'Closed cycle gone entirely — cards and the exploratory group.');
        }

        // Reversible: reopening puts everything back.
        cycle.Status__c = 'Active';
        update cycle;
        System.runAs(byLastName('UAT uattst1')) {
            Assert.areEqual(1, UatRunController.getQueue().cycleGroups.size(),
                'Reopened cycle returns to the queue.');
        }
    }

    @IsTest
    static void runnerFlowClaimAnswerSubmit() {
        Test_Cycle__c cycle = standardFixture();
        Test_Execution__c slot = [SELECT Id FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id];
        Test_Case__c tc = [SELECT Id FROM Test_Case__c LIMIT 1];
        tc.Title__c = 'Merge duplicate clients';
        update tc;

        System.runAs(byLastName('UAT uattst1')) {
            Test.startTest();
            UatRunController.RunnerDTO runner = UatRunController.claimAndStart(slot.Id);
            Assert.areEqual(2, runner.steps.size(), 'Result rows pre-created per step.');
            Assert.isNotNull(runner.steps[0].resultId);
            Assert.isTrue(runner.pathLabel.contains('Sprint 1'), runner.pathLabel);

            // Header/run-details fields for the two-column runner.
            Assert.areEqual('Merge duplicate clients', runner.caseTitle);
            Assert.areEqual('v1.0', runner.version, 'makeCase sets v1.0.');
            Assert.areEqual(Date.today().addDays(14), runner.targetDate,
                'makeCycle targets today+14.');
            Assert.isNotNull(runner.claimedDate, 'Claim stamps Claimed_Date__c.');
            Assert.areEqual(0, runner.steps[0].evidenceCount,
                'No evidence yet — counts default to 0, not null.');

            // Answer step 1 -> live rollup says In Progress.
            UatRunController.ExecutionSummaryDTO summary = UatRunController.saveStepResult(
                JSON.serialize(new Map<String, Object>{
                    'resultId' => runner.steps[0].resultId,
                    'actualResult' => 'It worked',
                    'result' => 'Pass'
                }));
            Assert.areEqual('In Progress', summary.status);

            // Answer step 2 -> Complete/Passed on submit.
            UatRunController.saveStepResult(JSON.serialize(new Map<String, Object>{
                'resultId' => runner.steps[1].resultId,
                'result' => 'Pass'
            }));
            UatRunController.saveFeedback(JSON.serialize(new Map<String, Object>{
                'executionId' => slot.Id,
                'uxRating' => 4,
                'uxRecommendation' => 'Make the button bigger'
            }));
            UatRunController.ExecutionSummaryDTO finalSummary =
                UatRunController.submitExecution(slot.Id);
            Test.stopTest();

            Assert.areEqual('Complete', finalSummary.status);
            Assert.areEqual('Passed', finalSummary.result);
        }
        Test_Execution__c saved = [
            SELECT UX_Rating__c, Last_Tested_Date__c FROM Test_Execution__c WHERE Id = :slot.Id
        ];
        Assert.areEqual(4, saved.UX_Rating__c);
        Assert.areEqual(Date.today(), saved.Last_Tested_Date__c);
    }

    @IsTest
    static void saveAndExitFloorsStatus()
    {
        Test_Cycle__c cycle = standardFixture();
        Test_Execution__c slot = [SELECT Id FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id];
        System.runAs(byLastName('UAT uattst1')) {
            UatRunController.claimAndStart(slot.Id);
            UatRunController.saveAndExit(slot.Id);
        }
        Assert.areEqual('In Progress',
            [SELECT Testing_Status__c FROM Test_Execution__c WHERE Id = :slot.Id].Testing_Status__c,
            'Save & exit floors the status at In Progress even with no answers.');
    }

    @IsTest
    static void outsiderCannotOpenRunner() {
        Test_Cycle__c cycle = standardFixture();
        Test_Execution__c slot = [SELECT Id FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id];
        System.runAs(byLastName('UAT uatout')) {
            try {
                UatRunController.startExecution(slot.Id);
                Assert.fail('Outsider should be rejected.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('assigned'), e.getMessage());
            }
        }
    }

    @IsTest
    static void exploratoryLogIsTeamVisibleButAuthorOwned() {
        Test_Cycle__c cycle = standardFixture();

        Id findingId;
        System.runAs(byLastName('UAT uattst1')) {
            findingId = UatRunController.saveFinding(JSON.serialize(new Map<String, Object>{
                'cycleId' => cycle.Id,
                'title' => 'Dashboard panel renders blank',
                'type' => 'Defect',
                'whatTesting' => 'Poking the dashboard',
                'whatExpected' => 'Charts load',
                'whatHappened' => 'Blank panel',
                'severity' => 'High',
                'noEvidenceReason' => 'Screenshot lives in the session log.'
            }));
        }

        // A teammate READS everything (team-visible, severity included) but
        // can no longer edit or delete someone else's entry — the 2026-08
        // session build superseded the any-member rule.
        System.runAs(byLastName('UAT uattst2')) {
            List<UatRunController.FindingDTO> findings = UatRunController.getFindings(cycle.Id);
            Assert.areEqual(1, findings.size());
            Assert.areEqual('Defect', findings[0].type);
            Assert.areEqual('High', findings[0].severity);
            Assert.isNull(findings[0].sessionId, 'Cycle-log finding carries no session.');

            try {
                UatRunController.saveFinding(JSON.serialize(new Map<String, Object>{
                    'id' => findingId,
                    'title' => 'Dashboard panel renders blank',
                    'type' => 'Question',
                    'whatTesting' => 'Poking the dashboard',
                    'whatHappened' => 'Peer overwrite'
                }));
                Assert.fail('Peer edit must be blocked.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('Only the tester'), e.getMessage());
            }
            try {
                UatRunController.deleteFinding(findingId);
                Assert.fail('Peer delete must be blocked.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('Only the tester'), e.getMessage());
            }
        }

        // The author edits their own entry.
        System.runAs(byLastName('UAT uattst1')) {
            UatRunController.saveFinding(JSON.serialize(new Map<String, Object>{
                'id' => findingId,
                'title' => 'Dashboard panel renders blank',
                'type' => 'Defect',
                'whatTesting' => 'Poking the dashboard',
                'whatHappened' => 'Blank panel — repro confirmed',
                'severity' => 'Critical',
                'noEvidenceReason' => 'Screenshot lives in the session log.'
            }));
        }
        Assert.areEqual('Critical', [
            SELECT Severity__c FROM Exploratory_Finding__c WHERE Id = :findingId
        ].Severity__c);

        // A UAT_Console admin moderates any entry, even off-team.
        System.runAs(byLastName('UAT uatadm')) {
            UatRunController.deleteFinding(findingId);
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Exploratory_Finding__c], 'Deleted by the admin.');
    }

    /** The admin triage fields ride along read-only: testers see them in every
     *  finding view, and a tester's own edit never touches them —
     *  saveFinding writes an explicit field list. */
    @IsTest
    static void findingDtoCarriesTheTriageFieldsAndTesterEditsLeaveThem() {
        Test_Cycle__c cycle = standardFixture();

        Id findingId;
        System.runAs(byLastName('UAT uattst1')) {
            findingId = UatRunController.saveFinding(JSON.serialize(new Map<String, Object>{
                'cycleId' => cycle.Id,
                'title' => 'Dashboard panel renders blank',
                'type' => 'Defect',
                'whatTesting' => 'Poking the dashboard',
                'whatHappened' => 'Blank panel',
                'severity' => 'Low'
            }));
        }
        // Triage happens on the admin surface (UatReportController); here the
        // stored state is all that matters to the tester-side read.
        update new Exploratory_Finding__c(
            Id = findingId,
            Workflow_Status__c = 'Added to Jira',
            External_Ref__c = 'DIV-42'
        );

        System.runAs(byLastName('UAT uattst1')) {
            List<UatRunController.FindingDTO> findings = UatRunController.getFindings(cycle.Id);
            Assert.areEqual('Added to Jira', findings[0].workflowStatus);
            Assert.areEqual('DIV-42', findings[0].externalRef);

            UatRunController.saveFinding(JSON.serialize(new Map<String, Object>{
                'id' => findingId,
                'title' => 'Dashboard panel renders blank',
                'type' => 'Defect',
                'whatTesting' => 'Poking the dashboard',
                'whatHappened' => 'Blank panel — repro confirmed',
                'severity' => 'Low'
            }));
        }
        Exploratory_Finding__c kept = [
            SELECT Workflow_Status__c, External_Ref__c FROM Exploratory_Finding__c
            WHERE Id = :findingId
        ];
        Assert.areEqual('Added to Jira', kept.Workflow_Status__c,
            'A tester edit must not reset the triage state.');
        Assert.areEqual('DIV-42', kept.External_Ref__c);
    }

    @IsTest
    static void dashboardShowsHeroAndContinueTesting() {
        Test_Cycle__c cycle = standardFixture();
        Test_Execution__c slot = [SELECT Id FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id];
        System.runAs(byLastName('UAT uattst1')) {
            UatRunController.RunnerDTO runner = UatRunController.claimAndStart(slot.Id);
            UatRunController.saveStepResult(JSON.serialize(new Map<String, Object>{
                'resultId' => runner.steps[0].resultId, 'result' => 'Pass'
            }));

            Test.startTest();
            UatRunController.DashboardDTO dash = UatRunController.getDashboard(null);
            Test.stopTest();

            Assert.isNotNull(dash.hero, 'Hero cycle present.');
            Assert.areEqual(1, dash.hero.total);
            Assert.areEqual(1, dash.hero.inProgress, 'One of two steps answered — In Progress.');
            Assert.areEqual('Active', dash.hero.cycleStatus, 'Null Status__c normalizes to Active.');
            Assert.areEqual(1, dash.continueTesting.size());
            Assert.areEqual(slot.Id, dash.continueTesting[0].executionId);
            Assert.areEqual(0, dash.recentlyCompleted.size());

            // Active-card enrichment: step math + identifier chips.
            Assert.areEqual(1, dash.continueTesting[0].stepsAnswered);
            Assert.areEqual(2, dash.continueTesting[0].stepsTotal);
            Assert.isTrue(dash.continueTesting[0].caseNumber.startsWith('TC-'),
                'caseNumber is the autonumber: ' + dash.continueTesting[0].caseNumber);
            Assert.areEqual('v1.0', dash.continueTesting[0].version);

            // Cycle-wide counters cover the whole cycle (here: just my seat).
            Assert.areEqual(1, dash.hero.cycleTotal);
            Assert.areEqual(1, dash.hero.cycleInProgress);
            Assert.areEqual(0, dash.hero.cycleAvailable);

            // Personal queue summary.
            Assert.areEqual(1, dash.queueSummary.total);
            Assert.areEqual(1, dash.queueSummary.inProgress);

            // The claim logged a seat event, attributed to me.
            Assert.areEqual(1, dash.recentActivity.size());
            Assert.areEqual('Claimed', dash.recentActivity[0].action);
            Assert.isTrue(dash.recentActivity[0].isMe);
        }
    }

    @IsTest
    static void dashboardRecentlyCompletedAndQueueSummary() {
        UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
        Test_Case__c caseA = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1001);
        Test_Case__c caseB = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1002);
        Team__c team = UatTestDataFactory.makeTeam('Alpha', new List<Id>{ byLastName('UAT uattst1').Id });
        Test_Cycle__c cycle = UatTestDataFactory.makeCycle('Sprint Soon', team.Id, null,
            new List<Id>{ caseA.Id, caseB.Id });
        cycle.Target_Date__c = Date.today().addDays(3);
        update cycle;

        Test_Execution__c slotA = [
            SELECT Id FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id AND Test_Case__c = :caseA.Id
        ];
        Test_Execution__c slotB = [
            SELECT Id FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id AND Test_Case__c = :caseB.Id
        ];

        System.runAs(byLastName('UAT uattst1')) {
            UatRunController.RunnerDTO runnerA = UatRunController.claimAndStart(slotA.Id);
            UatRunController.saveStepResult(JSON.serialize(new Map<String, Object>{
                'resultId' => runnerA.steps[0].resultId, 'result' => 'Pass'
            }));
            UatRunController.submitExecution(slotA.Id);
            UatRunController.claimAndStart(slotB.Id); // left Not Started

            Test.startTest();
            UatRunController.DashboardDTO dash = UatRunController.getDashboard(null);
            Test.stopTest();

            Assert.areEqual(1, dash.recentlyCompleted.size());
            Assert.areEqual(slotA.Id, dash.recentlyCompleted[0].executionId);
            Assert.areEqual(1, dash.hero.completePassed);
            Assert.areEqual(1, dash.hero.notStarted);

            Assert.areEqual(2, dash.queueSummary.total);
            Assert.areEqual(1, dash.queueSummary.completed);
            Assert.areEqual(1, dash.queueSummary.notStarted);

            Assert.areEqual(2, dash.hero.cycleTotal);
            Assert.areEqual(1, dash.hero.cycleCompleted);
            Assert.areEqual(1, dash.hero.cycleClaimedNotStarted);
        }
    }

    @IsTest
    static void dashboardAvailableToClaimSortsByPriority() {
        UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
        Test_Case__c low = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1001);
        low.Priority__c = 'Low';
        Test_Case__c critical = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1002);
        critical.Priority__c = 'Critical';
        update new List<Test_Case__c>{ low, critical };
        Team__c team = UatTestDataFactory.makeTeam('Alpha', new List<Id>{ byLastName('UAT uattst1').Id });
        UatTestDataFactory.makeCycle('Sprint 1', team.Id, null, new List<Id>{ low.Id, critical.Id });

        System.runAs(byLastName('UAT uattst1')) {
            Test.startTest();
            UatRunController.DashboardDTO dash = UatRunController.getDashboard(null);
            Test.stopTest();
            Assert.areEqual(2, dash.availableToClaim.size());
            Assert.areEqual('Critical', dash.availableToClaim[0].priority, 'Critical sorts first.');
        }
    }

    @IsTest
    static void dashboardAvailableToClaimIsUncapped() {
        UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
        List<Id> caseIds = new List<Id>();
        for (Integer i = 0; i < 7; i++) {
            caseIds.add(UatTestDataFactory.makeCase(tax.mod.Id, 1, 1001 + i).Id);
        }
        Team__c team = UatTestDataFactory.makeTeam('Alpha', new List<Id>{ byLastName('UAT uattst1').Id });
        UatTestDataFactory.makeCycle('Sprint Big', team.Id, null, caseIds);

        System.runAs(byLastName('UAT uattst1')) {
            Test.startTest();
            UatRunController.DashboardDTO dash = UatRunController.getDashboard(null);
            Test.stopTest();
            Assert.areEqual(7, dash.availableToClaim.size(),
                'The dashboard pool list is no longer capped at 5.');
            Assert.areEqual(7, dash.hero.cycleAvailable);
            Assert.areEqual(7, dash.hero.cycleTotal);
            Assert.areEqual(0, dash.hero.total, 'No claims yet — my-claims counters stay zero.');
        }
    }

    @IsTest
    static void dashboardCompleteBlockedBucketsAsBlocked() {
        Test_Cycle__c cycle = standardFixture();
        Test_Execution__c slot = [SELECT Id FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id];
        System.runAs(byLastName('UAT uattst1')) {
            UatRunController.RunnerDTO runner = UatRunController.claimAndStart(slot.Id);
            UatRunController.saveStepResult(JSON.serialize(new Map<String, Object>{
                'resultId' => runner.steps[0].resultId, 'result' => 'Pass'
            }));
            UatRunController.saveStepResult(JSON.serialize(new Map<String, Object>{
                'resultId' => runner.steps[1].resultId, 'result' => 'Blocked'
            }));
            UatRunController.submitExecution(slot.Id);

            Test.startTest();
            UatRunController.DashboardDTO dash = UatRunController.getDashboard(null);
            Test.stopTest();

            // Complete run whose verdict is Blocked counts as blocked — it
            // used to leak into completePassed.
            Assert.areEqual(1, dash.hero.blocked);
            Assert.areEqual(0, dash.hero.completePassed);
            Assert.areEqual(1, dash.queueSummary.blocked);
            Assert.areEqual(1, dash.hero.cycleBlocked,
                'Cycle-wide counter agrees: Complete + Blocked verdict is blocked.');
        }
    }

    @IsTest
    static void dashboardCycleWideCountsSeeOtherTesters() {
        UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
        Test_Case__c caseA = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1001);
        Test_Case__c caseB = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1002);
        Team__c team = UatTestDataFactory.makeTeam('Alpha', new List<Id>{
            byLastName('UAT uattst1').Id, byLastName('UAT uattst2').Id
        });
        Test_Cycle__c cycle = UatTestDataFactory.makeCycle('Sprint Duo', team.Id, null,
            new List<Id>{ caseA.Id, caseB.Id });
        Test_Execution__c slotA = [
            SELECT Id FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id AND Test_Case__c = :caseA.Id
        ];
        Test_Execution__c slotB = [
            SELECT Id FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id AND Test_Case__c = :caseB.Id
        ];

        System.runAs(byLastName('UAT uattst2')) {
            UatRunController.RunnerDTO runner = UatRunController.claimAndStart(slotA.Id);
            UatRunController.saveStepResult(JSON.serialize(new Map<String, Object>{
                'resultId' => runner.steps[0].resultId, 'result' => 'Pass'
            }));
            UatRunController.submitExecution(slotA.Id);
        }
        System.runAs(byLastName('UAT uattst1')) {
            UatRunController.claimAndStart(slotB.Id);

            Test.startTest();
            UatRunController.DashboardDTO dash = UatRunController.getDashboard(null);
            Test.stopTest();

            Assert.areEqual(1, dash.hero.total, 'My-claims counters stay mine.');
            Assert.areEqual(2, dash.hero.cycleTotal, 'Cycle-wide sees the other tester\'s seat.');
            Assert.areEqual(1, dash.hero.cycleCompleted);
            Assert.areEqual(1, dash.hero.cycleClaimedNotStarted);

            // Both claims appear in the feed; the other tester's isn't mine.
            Assert.areEqual(2, dash.recentActivity.size());
            Boolean sawOther = false;
            for (UatRunController.ActivityItemDTO item : dash.recentActivity) {
                Assert.areEqual('Claimed', item.action);
                if (!item.isMe) {
                    sawOther = true;
                }
            }
            Assert.isTrue(sawOther, 'Teammate\'s claim shows with isMe=false.');
        }
    }

    @IsTest
    static void dashboardActivityFeedFiltersAndCaps() {
        Test_Cycle__c cycle = standardFixture();
        Test_Case__c tc = [SELECT Id FROM Test_Case__c LIMIT 1];
        Id tester2 = byLastName('UAT uattst2').Id;

        // Backdated seat events, oldest first; the newest row is an admin
        // Force Unassigned that must NOT surface in the tester feed.
        List<Test_Assignment_Event__c> events = new List<Test_Assignment_Event__c>();
        for (Integer i = 0; i < 7; i++) {
            events.add(new Test_Assignment_Event__c(
                Action__c = 'Claimed', Test_Case__c = tc.Id, Test_Cycle__c = cycle.Id,
                Tester__c = tester2, Actor__c = tester2
            ));
        }
        events.add(new Test_Assignment_Event__c(
            Action__c = 'Force Unassigned', Test_Case__c = tc.Id, Test_Cycle__c = cycle.Id,
            Tester__c = tester2, Actor__c = tester2
        ));
        insert events;
        for (Integer i = 0; i < 7; i++) {
            Test.setCreatedDate(events[i].Id, Datetime.now().addHours(-(8 - i)));
        }
        Test.setCreatedDate(events[7].Id, Datetime.now());

        System.runAs(byLastName('UAT uattst1')) {
            Test.startTest();
            UatRunController.DashboardDTO dash = UatRunController.getDashboard(null);
            Test.stopTest();

            Assert.areEqual(6, dash.recentActivity.size(), 'Feed caps at 6.');
            Datetime previous = null;
            for (UatRunController.ActivityItemDTO item : dash.recentActivity) {
                Assert.areNotEqual('Force Unassigned', item.action,
                    'Admin actions stay out of the tester feed.');
                if (previous != null) {
                    Assert.isTrue(item.timestamp <= previous, 'Newest first.');
                }
                previous = item.timestamp;
            }
        }
    }

    @IsTest
    static void saveStepResultPersistsDefectFields() {
        Test_Cycle__c cycle = standardFixture();
        Test_Execution__c slot = [SELECT Id FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id];
        System.runAs(byLastName('UAT uattst1')) {
            UatRunController.RunnerDTO runner = UatRunController.claimAndStart(slot.Id);
            UatRunController.saveStepResult(JSON.serialize(new Map<String, Object>{
                'resultId' => runner.steps[0].resultId,
                'result' => 'Fail',
                'actualResult' => 'Button missing',
                'defectSeverity' => 'High',
                'defectSummary' => 'Save button missing on the household form'
            }));

            UatRunController.RunnerDTO reloaded = UatRunController.startExecution(slot.Id);
            Assert.areEqual('High', reloaded.steps[0].defectSeverity);
            Assert.areEqual('Save button missing on the household form',
                reloaded.steps[0].defectSummary);
        }
    }

    @IsTest
    static void evidencePlumbing() {
        Test_Cycle__c cycle = standardFixture();
        Test_Execution__c slot = [SELECT Id FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id];
        System.runAs(byLastName('UAT uattst1')) {
            UatRunController.RunnerDTO runner = UatRunController.claimAndStart(slot.Id);
            Id docId = UatTestDataFactory.attachFile(slot.Id, 'run-summary');
            UatRunController.registerUploads(slot.Id, new List<String>{ docId });

            List<UatFileService.FileDTO> files = UatRunController.getFiles(slot.Id);
            Assert.areEqual(1, files.size());
            Assert.isTrue(files[0].thumbnailUrl.contains('renditionDownload'), files[0].thumbnailUrl);
            Assert.isTrue(files[0].contentSize > 0, 'ContentSize rides along for the size label.');

            // Step-level evidence rolls into RunnerStepDTO.evidenceCount on reload.
            Id stepDocId = UatTestDataFactory.attachFile(runner.steps[0].resultId, 'step-shot');
            UatRunController.registerUploads(runner.steps[0].resultId, new List<String>{ stepDocId });
            UatRunController.RunnerDTO reloaded = UatRunController.startExecution(slot.Id);
            Assert.areEqual(1, reloaded.steps[0].evidenceCount);
            Assert.areEqual(0, reloaded.steps[1].evidenceCount);

            UatRunController.deleteFile(files[0].contentDocumentId, slot.Id);
            Assert.areEqual(0, UatRunController.getFiles(slot.Id).size());
        }
    }

    // ---- Cycle switcher: getMyCycles ---------------------------------------------

    @IsTest
    static void myCyclesEmptyWhenAllCyclesBelongToOtherTeams() {
        standardFixture(); // team Alpha only
        System.runAs(byLastName('UAT uatout')) {
            Assert.areEqual(0, UatRunController.getMyCycles().size(),
                'A tester on no team sees no team-scoped cycles.');
        }
    }

    @IsTest
    static void myCyclesSingleForTeamMember() {
        Test_Cycle__c cycle = standardFixture();
        Test_Case__c tc = [SELECT Id FROM Test_Case__c LIMIT 1];
        System.runAs(byLastName('UAT uattst1')) {
            List<UatRunController.CycleOptionDTO> cycles = UatRunController.getMyCycles();
            Assert.areEqual(1, cycles.size(), 'Team membership resolves to individual access.');
            Assert.areEqual(cycle.Id, cycles[0].cycleId, 'The team cycle is enumerated.');
            Assert.areEqual('Active', cycles[0].cycleStatus, 'Null Status__c normalizes to Active.');
            Assert.areEqual(14, cycles[0].daysToTarget, 'makeCycle targets today+14.');
            Assert.areEqual(0, cycles[0].myClaimCount, 'No claims yet.');

            UatRunController.claimCase(cycle.Id, tc.Id);
            Assert.areEqual(1, UatRunController.getMyCycles()[0].myClaimCount,
                'Claim count reflects my unreleased claim.');
        }
    }

    @IsTest
    static void myCyclesUnionOrdersByTargetDate() {
        standardFixture(); // team cycle, target +14
        UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Open');
        Test_Case__c openCase = UatTestDataFactory.makeCase(tax.mod.Id, 1, 2001);
        Test_Cycle__c teamless = UatTestDataFactory.makeCycle('Open Sprint', null, null,
            new List<Id>{ openCase.Id });
        teamless.Target_Date__c = Date.today().addDays(3);
        update teamless;

        // Team member sees both; the sooner target sorts first.
        System.runAs(byLastName('UAT uattst1')) {
            List<UatRunController.CycleOptionDTO> cycles = UatRunController.getMyCycles();
            Assert.areEqual(2, cycles.size(), 'Team cycle plus the team-less open cycle.');
            Assert.areEqual(teamless.Id, cycles[0].cycleId, 'Soonest target date first.');
        }
        // A tester on no team still gets the team-less cycle.
        System.runAs(byLastName('UAT uatout')) {
            List<UatRunController.CycleOptionDTO> cycles = UatRunController.getMyCycles();
            Assert.areEqual(1, cycles.size(), 'Team-less cycles are open to every tester.');
            Assert.areEqual(teamless.Id, cycles[0].cycleId, 'Only the open cycle is visible.');
        }
    }

    @IsTest
    static void myCyclesKeepsClaimedCycleAfterTeamSwitch() {
        Test_Cycle__c cycle = standardFixture();
        Test_Case__c tc = [SELECT Id FROM Test_Case__c LIMIT 1];
        System.runAs(byLastName('UAT uattst1')) {
            UatRunController.claimCase(cycle.Id, tc.Id);
        }
        Team__c beta = UatTestDataFactory.makeTeam('Beta', new List<Id>{
            byLastName('UAT uattst2').Id
        });
        cycle.Assigned_Team__c = beta.Id;
        update cycle;

        System.runAs(byLastName('UAT uattst1')) {
            List<UatRunController.CycleOptionDTO> cycles = UatRunController.getMyCycles();
            Assert.areEqual(1, cycles.size(),
                'A live claim keeps the cycle enumerated after a team switch.');
            Assert.areEqual(cycle.Id, cycles[0].cycleId, 'It is the reassigned cycle.');
            Assert.areEqual(1, cycles[0].myClaimCount, 'The stranded claim is counted.');
        }
    }

    @IsTest
    static void myCyclesExcludesClosedCycles() {
        Test_Cycle__c cycle = standardFixture();
        Test_Case__c tc = [SELECT Id FROM Test_Case__c LIMIT 1];
        System.runAs(byLastName('UAT uattst1')) {
            UatRunController.claimCase(cycle.Id, tc.Id);
        }
        cycle.Status__c = 'Closed';
        update cycle;
        System.runAs(byLastName('UAT uattst1')) {
            Assert.areEqual(0, UatRunController.getMyCycles().size(),
                'Closed cycles leave the switcher even when I hold a claim there.');
        }
    }

    // ---- Cycle switcher: getDashboard(cycleId) -------------------------------------

    @IsTest
    static void dashboardScopedToSelectedCycle() {
        UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
        Test_Case__c caseA1 = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1001);
        Test_Case__c caseA2 = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1002);
        Test_Case__c caseB1 = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1003);
        Test_Case__c caseB2 = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1004);
        Team__c team = UatTestDataFactory.makeTeam('Alpha', new List<Id>{ byLastName('UAT uattst1').Id });
        Test_Cycle__c cycleA = UatTestDataFactory.makeCycle('Cycle A', team.Id, null,
            new List<Id>{ caseA1.Id, caseA2.Id });
        cycleA.Target_Date__c = Date.today().addDays(3);
        update cycleA;
        Test_Cycle__c cycleB = UatTestDataFactory.makeCycle('Cycle B', team.Id, null,
            new List<Id>{ caseB1.Id, caseB2.Id });
        cycleB.Target_Date__c = Date.today().addDays(10);
        update cycleB;

        // One claimed In Progress run per cycle; one open seat per cycle.
        Id me = byLastName('UAT uattst1').Id;
        List<Test_Execution__c> claims = [
            SELECT Id FROM Test_Execution__c
            WHERE Test_Case__c IN (:caseA1.Id, :caseB1.Id)
        ];
        for (Test_Execution__c e : claims) {
            e.Assigned_Tester__c = me;
            e.Claimed_Date__c = Datetime.now();
            e.Testing_Status__c = 'In Progress';
        }
        update claims;

        System.runAs(byLastName('UAT uattst1')) {
            Test.startTest();
            UatRunController.DashboardDTO dash = UatRunController.getDashboard(cycleB.Id);
            Test.stopTest();

            Assert.areEqual(cycleB.Id, dash.hero.cycleId,
                'The selected cycle is the hero even though Cycle A sorts first.');
            Assert.areEqual(1, dash.continueTesting.size(), 'Only Cycle B\'s active run.');
            Assert.areEqual(cycleB.Id, dash.continueTesting[0].cycleId,
                'Continue Testing is scoped to the selection.');
            Assert.areEqual(1, dash.availableToClaim.size(), 'Only Cycle B\'s open seat.');
            Assert.areEqual(cycleB.Id, dash.availableToClaim[0].cycleId,
                'Available list is scoped to the selection.');
            Assert.areEqual(1, dash.queueSummary.total,
                'Queue summary counts the selected cycle only.');
            Assert.areEqual(1, dash.queueSummary.inProgress,
                'Cycle B\'s single claim is In Progress.');
        }
    }

    @IsTest
    static void dashboardUnknownCycleIdFallsBackToAutoHero() {
        Test_Cycle__c cycle = standardFixture();
        // A well-formed but nonexistent cycle id: create empty, then delete.
        Test_Cycle__c ghost = UatTestDataFactory.makeCycle('Ghost', null, null, null);
        Id ghostId = ghost.Id;
        delete ghost;

        Test_Execution__c slot = [SELECT Id FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id];
        System.runAs(byLastName('UAT uattst1')) {
            UatRunController.claimAndStart(slot.Id);

            Test.startTest();
            UatRunController.DashboardDTO dash = UatRunController.getDashboard(ghostId);
            Test.stopTest();

            Assert.isNotNull(dash.hero, 'A stale stored id never blanks the dashboard.');
            Assert.areEqual(cycle.Id, dash.hero.cycleId,
                'Unknown cycle id falls back to the auto-picked hero.');
        }
    }

    @IsTest
    static void dashboardOtherTeamsCycleFallsBackToAutoHero() {
        Test_Cycle__c mine = standardFixture();
        UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Other');
        Test_Case__c otherCase = UatTestDataFactory.makeCase(tax.mod.Id, 1, 3001);
        Team__c beta = UatTestDataFactory.makeTeam('Beta', new List<Id>{
            byLastName('UAT uattst2').Id
        });
        Test_Cycle__c theirs = UatTestDataFactory.makeCycle('Beta Sprint', beta.Id, null,
            new List<Id>{ otherCase.Id });

        System.runAs(byLastName('UAT uattst1')) {
            Test.startTest();
            UatRunController.DashboardDTO dash = UatRunController.getDashboard(theirs.Id);
            Test.stopTest();

            Assert.isNotNull(dash.hero, 'No throw on an inaccessible cycle id.');
            Assert.areEqual(mine.Id, dash.hero.cycleId,
                'Another team\'s cycle id falls back to my auto-picked hero.');
        }
    }

    @IsTest
    static void dashboardContinueTestingSpansCycles() {
        UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
        List<Id> busyCases = new List<Id>();
        for (Integer i = 0; i < 5; i++) {
            busyCases.add(UatTestDataFactory.makeCase(tax.mod.Id, 1, 1001 + i).Id);
        }
        Test_Case__c quietCase = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1006);
        Team__c team = UatTestDataFactory.makeTeam('Alpha', new List<Id>{ byLastName('UAT uattst1').Id });
        Test_Cycle__c busy = UatTestDataFactory.makeCycle('Busy Cycle', team.Id, null, busyCases);
        busy.Target_Date__c = Date.today().addDays(3);
        update busy;
        Test_Cycle__c quiet = UatTestDataFactory.makeCycle('Quiet Cycle', team.Id, null,
            new List<Id>{ quietCase.Id });

        // Six In Progress claims stamped in ONE update (identical
        // LastModifiedDate to the second); the quiet cycle's row carries the
        // only Last_Tested_Date__c, so CardRecencyComparator's tiebreak puts
        // it first deterministically.
        Id me = byLastName('UAT uattst1').Id;
        List<Test_Execution__c> slots = [
            SELECT Id, Test_Cycle__c FROM Test_Execution__c
            WHERE Test_Cycle__c IN (:busy.Id, :quiet.Id)
        ];
        Id quietSlotId = null;
        for (Test_Execution__c e : slots) {
            e.Assigned_Tester__c = me;
            e.Claimed_Date__c = Datetime.now();
            e.Testing_Status__c = 'In Progress';
            if (e.Test_Cycle__c == quiet.Id) {
                e.Last_Tested_Date__c = Date.today();
                quietSlotId = e.Id;
            }
        }
        update slots;

        System.runAs(byLastName('UAT uattst1')) {
            Test.startTest();
            UatRunController.DashboardDTO dash = UatRunController.getDashboard(null);
            Test.stopTest();

            Assert.areEqual(5, dash.continueTesting.size(), 'Row still caps at 5.');
            Assert.areEqual(quietSlotId, dash.continueTesting[0].executionId,
                'The hero cycle\'s 5 claims no longer starve the other cycle out of the row.');
        }
    }

    @IsTest
    static void teamlessCycleAppearsInEveryTestersQueue() {
        UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
        Test_Case__c tc = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1001);
        Test_Cycle__c open = UatTestDataFactory.makeCycle('Open Sprint', null, null,
            new List<Id>{ tc.Id });

        // Queue audience now matches the pool: a tester on no team still gets
        // the team-less cycle's group (exploratory-only until they claim).
        System.runAs(byLastName('UAT uatout')) {
            UatRunController.QueueDTO queue = UatRunController.getQueue();
            Assert.areEqual(1, queue.cycleGroups.size(),
                'Team-less open cycle backfills into every tester\'s queue.');
            Assert.areEqual(open.Id, queue.cycleGroups[0].cycleId, 'It is the open cycle.');
            Assert.areEqual(0, queue.cycleGroups[0].cards.size(),
                'No claims yet — the group exists for the exploratory card.');
        }
    }

    @IsTest
    static void queueAndPoolCardsCarryCycleIdentity() {
        UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
        Test_Case__c claimed = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1001);
        Test_Case__c open = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1002);
        Team__c team = UatTestDataFactory.makeTeam('Alpha', new List<Id>{ byLastName('UAT uattst1').Id });
        Test_Cycle__c cycle = UatTestDataFactory.makeCycle('Sprint 1', team.Id, null,
            new List<Id>{ claimed.Id, open.Id });

        System.runAs(byLastName('UAT uattst1')) {
            UatRunController.claimCase(cycle.Id, claimed.Id);

            Test.startTest();
            UatRunController.QueueDTO queue = UatRunController.getQueue();
            List<UatRunController.PoolGroupDTO> pool = UatRunController.getPool();
            Test.stopTest();

            UatRunController.QueueCardDTO queueCard = queue.cycleGroups[0].cards[0];
            Assert.areEqual(cycle.Id, queueCard.cycleId, 'Queue card carries its cycle id.');
            Assert.areEqual('Sprint 1', queueCard.cycleName, 'Queue card carries its cycle name.');
            Assert.areEqual('Sprint 1', pool[0].cards[0].cycleName,
                'Pool card carries its cycle name for the dashboard\'s cross-cycle labels.');
        }
    }

    // ---- Staged evidence (upload-before-first-save; claims onto the finding) ------

    private static Id startSessionFor(Id cycleId) {
        return UatSessionController.startSession(JSON.serialize(new Map<String, Object>{
            'title' => 'Staging session',
            'charter' => 'Verify evidence can be staged before the finding exists.',
            'cycleId' => cycleId
        }));
    }

    private static Id sessionFinding(Id sessionId) {
        return UatRunController.saveFinding(JSON.serialize(new Map<String, Object>{
            'sessionId' => sessionId,
            'title' => 'Survivor history vanished after merge',
            'type' => 'Defect',
            'severity' => 'Low',
            'whatTesting' => 'Merged two records',
            'whatHappened' => 'History vanished from the survivor'
        }));
    }

    @IsTest
    static void claimStagedFilesRelinksSessionEvidenceToFinding() {
        Test_Cycle__c cycle = standardFixture();
        System.runAs(byLastName('UAT uattst1')) {
            Id sessionId = startSessionFor(cycle.Id);
            Id docId = UatTestDataFactory.attachFile(sessionId, 'staged-shot');
            Id findingId = sessionFinding(sessionId);
            // Simulate a partial retry: the doc already reached the finding
            // once — the claim must skip the duplicate, not throw.
            insert new ContentDocumentLink(
                ContentDocumentId = docId, LinkedEntityId = findingId,
                ShareType = 'V', Visibility = 'AllUsers'
            );

            Test.startTest();
            UatRunController.claimStagedFiles(findingId, new List<String>{ docId });
            Test.stopTest();

            Assert.areEqual(1, UatRunController.getFiles(findingId).size(),
                'Doc lives on the finding, exactly once.');
            Assert.areEqual(0, UatRunController.getFiles(sessionId).size(),
                'Staging link removed from the session.');
            ContentDocumentLink cdl = [
                SELECT ShareType, Visibility FROM ContentDocumentLink
                WHERE ContentDocumentId = :docId AND LinkedEntityId = :findingId
            ];
            Assert.areEqual('AllUsers', cdl.Visibility, 'Team-visible like all evidence.');
        }
    }

    @IsTest
    static void claimStagedFilesGatesOwnershipSessionAndStaging() {
        Test_Cycle__c cycle = standardFixture();
        Id sessionId;
        Id findingId;
        Id looseFindingId;
        Id docId;
        System.runAs(byLastName('UAT uattst1')) {
            sessionId = startSessionFor(cycle.Id);
            docId = UatTestDataFactory.attachFile(sessionId, 'staged-shot');
            findingId = sessionFinding(sessionId);
            looseFindingId = UatRunController.saveFinding(JSON.serialize(new Map<String, Object>{
                'cycleId' => cycle.Id,
                'title' => 'Loose cycle-log observation',
                'type' => 'Question',
                'whatHappened' => 'Logged straight into the cycle log'
            }));
        }

        System.runAs(byLastName('UAT uattst2')) {
            try {
                UatRunController.claimStagedFiles(findingId, new List<String>{ docId });
                Assert.fail('A peer must not move evidence onto someone else\'s finding.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('Only the tester'), e.getMessage());
            }
        }

        System.runAs(byLastName('UAT uattst1')) {
            try {
                UatRunController.claimStagedFiles(looseFindingId, new List<String>{ docId });
                Assert.fail('Cycle-log findings have no staging parent.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('no session'), e.getMessage());
            }
            // A doc that was never staged on the session cannot be claimed.
            Id strayDoc = UatTestDataFactory.attachFile(findingId, 'direct-upload');
            try {
                UatRunController.claimStagedFiles(findingId, new List<String>{ strayDoc });
                Assert.fail('Only session-staged docs may be claimed.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('not attached'), e.getMessage());
            }
            try {
                UatRunController.claimStagedFiles(findingId, new List<String>());
                Assert.fail('An empty claim is a client bug — refuse it.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('Nothing to attach'), e.getMessage());
            }
        }
    }

    /**
     * The 2026-08-14 launchpad report: a tester attached three screenshots to a
     * High defect and was still told to attach one when finishing the session.
     *
     * claimStagedFiles and discardStagedFiles asserted the CYCLE audience
     * unconditionally, and a standalone session has no cycle — so
     * assertCycleAudience(null) threw 'Missing cycle' on every claim. The LWC
     * swallows that into a toast, so the finding saved with its evidence left
     * stranded on the session, and the finish gate (which counts files on the
     * FINDING) then blocked a tester who could plainly see the screenshots in
     * the session log. Every existing staging test used a cycle-linked session,
     * which is why this survived.
     */
    @IsTest
    static void stagedEvidenceReachesAStandaloneSessionFinding() {
        System.runAs(byLastName('UAT uattst1')) {
            Id sessionId = startSessionFor(null); // standalone — no cycle
            Id docId = UatTestDataFactory.attachFile(sessionId, 'staged-shot');
            Id findingId = UatRunController.saveFinding(JSON.serialize(new Map<String, Object>{
                'sessionId' => sessionId,
                'title' => 'Envelope will not persist on save',
                'type' => 'Defect',
                'severity' => 'High',
                'whatTesting' => 'Saving an envelope',
                'whatHappened' => 'The record silently failed to persist',
                'stagedDocumentIds' => new List<String>{ docId }
            }));

            Test.startTest();
            UatRunController.claimStagedFiles(findingId, new List<String>{ docId });
            Test.stopTest();

            Assert.areEqual(1, UatRunController.getFiles(findingId).size(),
                'A standalone session must hand its staged evidence to the finding.');
            Assert.areEqual(0, UatRunController.getFiles(sessionId).size(),
                'Staging link removed from the session.');

            // The user-facing symptom: with the evidence where it belongs, the
            // severe-defect gate lets the session close.
            UatSessionController.finishSession(JSON.serialize(new Map<String, Object>{
                'sessionId' => sessionId
            }));
            Assert.areEqual(UatConstants.SESSION_COMPLETED,
                [SELECT Status__c FROM Exploratory_Session__c WHERE Id = :sessionId].Status__c,
                'A standalone session with evidenced findings must be finishable.');
        }
    }

    /** The cancel half of the same defect: discarding a standalone session's
     *  staged uploads threw 'Missing cycle' too, which is how abandoned finding
     *  forms left orphaned files behind on the session. */
    @IsTest
    static void discardStagedFilesWorksOnAStandaloneSession() {
        System.runAs(byLastName('UAT uattst1')) {
            Id sessionId = startSessionFor(null); // standalone — no cycle
            Id docId = UatTestDataFactory.attachFile(sessionId, 'abandoned-shot');

            Test.startTest();
            UatRunController.discardStagedFiles(sessionId, new List<String>{ docId });
            Test.stopTest();

            Assert.areEqual(0, [SELECT COUNT() FROM ContentDocument WHERE Id = :docId],
                'Cancelling a standalone finding form must clean up its uploads.');
        }
    }

    @IsTest
    static void discardStagedFilesDeletesOwnStagedDocsOnly() {
        Test_Cycle__c cycle = standardFixture();
        Id sessionId;
        System.runAs(byLastName('UAT uattst1')) {
            sessionId = startSessionFor(cycle.Id);
        }
        // Staged by someone else (created as the running test-context user).
        Id foreignDoc = UatTestDataFactory.attachFile(sessionId, 'someone-elses');

        System.runAs(byLastName('UAT uattst1')) {
            Id mine = UatTestDataFactory.attachFile(sessionId, 'my-staged');
            Id otherSession = startSessionFor(cycle.Id);
            Id elsewhereDoc = UatTestDataFactory.attachFile(otherSession, 'other-session');

            Test.startTest();
            UatRunController.discardStagedFiles(sessionId, new List<String>{ mine });
            Test.stopTest();
            Assert.areEqual(0, [SELECT COUNT() FROM ContentDocument WHERE Id = :mine],
                'Own staged doc hard-deleted on discard.');

            try {
                UatRunController.discardStagedFiles(sessionId, new List<String>{ foreignDoc });
                Assert.fail('Only the uploader may discard a staged doc.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('you uploaded'), e.getMessage());
            }
            try {
                UatRunController.discardStagedFiles(sessionId, new List<String>{ elsewhereDoc });
                Assert.fail('Docs staged on a different record must not discard here.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('not attached'), e.getMessage());
            }
        }
    }

    // ---- Finding model (2026-08-06 rework) ---------------------------------------

    /** A finding nobody can read is worse than no finding — the org carried one
     *  titled "T" at Critical severity, which is what these rules prevent. */
    @IsTest
    static void findingRulesRejectTheUnreadable() {
        Test_Cycle__c cycle = standardFixture();
        System.runAs(byLastName('UAT uattst1')) {
            Map<String, Object> base = new Map<String, Object>{
                'cycleId' => cycle.Id,
                'title' => 'Dashboard panel renders blank',
                'type' => 'Defect',
                'whatHappened' => 'Blank panel',
                'severity' => 'Low'
            };

            // Title under 10 characters.
            Map<String, Object> shortTitle = new Map<String, Object>(base);
            shortTitle.put('title', 'T');
            assertFindingRejected(shortTitle, 'title of at least');

            // No description.
            Map<String, Object> noBody = new Map<String, Object>(base);
            noBody.remove('whatHappened');
            assertFindingRejected(noBody, 'what happened');

            // A defect with no severity.
            Map<String, Object> noSeverity = new Map<String, Object>(base);
            noSeverity.remove('severity');
            assertFindingRejected(noSeverity, 'needs a severity');

            // An unknown type.
            Map<String, Object> badType = new Map<String, Object>(base);
            badType.put('type', 'Whatever');
            assertFindingRejected(badType, 'what kind of finding');

            // The happy path still saves.
            Assert.isNotNull(UatRunController.saveFinding(JSON.serialize(base)));
        }
    }

    private static void assertFindingRejected(Map<String, Object> payload, String fragment) {
        try {
            UatRunController.saveFinding(JSON.serialize(payload));
            Assert.fail('Expected a rejection mentioning: ' + fragment);
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains(fragment), e.getMessage());
        }
    }

    /** Severity is a property of a defect. "Suggestion, Critical" is exactly
     *  the pairing this rework removes, so it is cleared rather than trusted. */
    @IsTest
    static void severityIsClearedForEveryTypeButDefect() {
        Test_Cycle__c cycle = standardFixture();
        System.runAs(byLastName('UAT uattst1')) {
            Test.startTest();
            Id findingId = UatRunController.saveFinding(JSON.serialize(new Map<String, Object>{
                'cycleId' => cycle.Id,
                'title' => 'The merge screen could explain itself better',
                'type' => 'Suggestion',
                'whatHappened' => 'Nothing broke, but the wording is confusing',
                'severity' => 'Critical'
            }));
            Test.stopTest();

            Exploratory_Finding__c f = [
                SELECT Type__c, Severity__c, Source__c
                FROM Exploratory_Finding__c WHERE Id = :findingId
            ];
            Assert.areEqual('Suggestion', f.Type__c);
            Assert.isNull(f.Severity__c, 'Severity is meaningless without a defect.');
            Assert.areEqual('Session', f.Source__c, 'Stamped server-side.');
        }
    }

    /** A severe defect needs evidence or a stated reason. Staged ids count,
     *  because the claim happens AFTER saveFinding returns — counting only the
     *  finding's own links would reject every new finding with a screenshot. */
    @IsTest
    static void severeDefectsNeedEvidenceOrAStatedReason() {
        Test_Cycle__c cycle = standardFixture();
        System.runAs(byLastName('UAT uattst1')) {
            Map<String, Object> base = new Map<String, Object>{
                'cycleId' => cycle.Id,
                'title' => 'Save button missing on the household form',
                'type' => 'Defect',
                'whatHappened' => 'No save button at all',
                'severity' => 'Critical'
            };
            assertFindingRejected(base, 'screenshot or file');

            Map<String, Object> withReason = new Map<String, Object>(base);
            withReason.put('noEvidenceReason', 'Only reproduces on a locked-down machine.');
            Assert.isNotNull(UatRunController.saveFinding(JSON.serialize(withReason)),
                'A stated reason is an acceptable answer.');

            Map<String, Object> withStaged = new Map<String, Object>(base);
            withStaged.put('stagedDocumentIds', new List<String>{
                UatTestDataFactory.attachFile(cycle.Id, 'evidence-shot')
            });
            Assert.isNotNull(UatRunController.saveFinding(JSON.serialize(withStaged)),
                'Evidence staged in the same save counts.');

            // Low severity never asks.
            Map<String, Object> low = new Map<String, Object>(base);
            low.put('severity', 'Low');
            Assert.isNotNull(UatRunController.saveFinding(JSON.serialize(low)));
        }
    }

    /**
     * The other half of the unification: a defect reported against a scripted
     * step becomes a real Finding, so scripted and ad-hoc defects triage in one
     * list. Upsert, not insert — the runner re-saves a step constantly.
     */
    @IsTest
    static void scriptedDefectsBecomeFindings() {
        Test_Cycle__c cycle = standardFixture();
        Test_Execution__c slot = [SELECT Id FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id];
        System.runAs(byLastName('UAT uattst1')) {
            UatRunController.RunnerDTO runner = UatRunController.claimAndStart(slot.Id);
            Map<String, Object> step = new Map<String, Object>{
                'resultId' => runner.steps[0].resultId,
                'result' => 'Fail',
                'actualResult' => 'Button missing',
                'defectSeverity' => 'High',
                'defectSummary' => 'Save button missing on the household form'
            };

            Test.startTest();
            UatRunController.saveStepResult(JSON.serialize(step));
            UatRunController.saveStepResult(JSON.serialize(step)); // re-save
            Test.stopTest();

            List<Exploratory_Finding__c> findings = [
                SELECT Title__c, Type__c, Source__c, Severity__c,
                    Test_Execution__c, Test_Cycle__c
                FROM Exploratory_Finding__c WHERE Test_Step_Result__c != null
            ];
            Assert.areEqual(1, findings.size(),
                'Re-saving a step must not mint a second finding.');
            Assert.areEqual('Test case', findings[0].Source__c);
            Assert.areEqual('Defect', findings[0].Type__c);
            Assert.areEqual('High', findings[0].Severity__c);
            Assert.areEqual('Save button missing on the household form', findings[0].Title__c);
            Assert.areEqual(slot.Id, findings[0].Test_Execution__c,
                'Denormalized: the step result is purged with the run, this is not.');

            // Clearing the severity means the tester decided it was not a defect.
            step.put('defectSeverity', null);
            UatRunController.saveStepResult(JSON.serialize(step));
            Assert.areEqual(0, [
                SELECT COUNT() FROM Exploratory_Finding__c WHERE Test_Step_Result__c != null
            ]);
        }
    }
}