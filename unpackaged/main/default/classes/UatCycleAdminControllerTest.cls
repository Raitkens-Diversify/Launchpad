/**
 * Tests for UatCycleAdminController — cycle list aggregates, cycle detail
 * (scope rows with source tags + execution chips), junction management, and
 * add-tester (the multi-tester model, 03 §5). The engine itself is covered by
 * UatExecutionServiceTest; these tests exercise the controller contract.
 */
@IsTest
private class UatCycleAdminControllerTest {

    @TestSetup
    static void setup() {
        UatTestDataFactory.createAdminUser('uatadm');
        UatTestDataFactory.createTesterUser('uattst1');
        UatTestDataFactory.createTesterUser('uattst2');
    }

    private static User byLastName(String lastName) {
        return [SELECT Id FROM User WHERE LastName = :lastName LIMIT 1];
    }

    @IsTest
    static void cycleDetailShowsUnionWithSourcesAndChips() {
        User tester1 = byLastName('UAT uattst1');
        User tester2 = byLastName('UAT uattst2');
        System.runAs(byLastName('UAT uatadm')) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
            Test_Case__c c1 = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1001);
            Test_Case__c c2 = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1002);
            Test_Book__c book = UatTestDataFactory.makeBook('Book A', new List<Id>{ c1.Id });
            Team__c team = UatTestDataFactory.makeTeam('Alpha', new List<Id>{ tester1.Id, tester2.Id });

            Id cycleId = UatCycleAdminController.saveCycle(JSON.serialize(new Map<String, Object>{
                'name' => 'Sprint 42 Regression',
                'targetDate' => Date.today().addDays(10),
                'teamId' => team.Id
            }));
            UatCycleAdminController.attachBook(cycleId, book.Id);
            UatCycleAdminController.addDirectCase(cycleId, c1.Id); // same case, second path
            UatCycleAdminController.addDirectCase(cycleId, c2.Id);

            Test.startTest();
            UatCycleAdminController.CycleDetailDTO detail =
                UatCycleAdminController.getCycleDetail(cycleId);
            Test.stopTest();

            Assert.areEqual(2, detail.scopeRows.size(), 'Union de-duplicated: c1 appears once.');
            UatCycleAdminController.ScopeRowDTO c1Row;
            for (UatCycleAdminController.ScopeRowDTO row : detail.scopeRows) {
                if (row.caseId == c1.Id) {
                    c1Row = row;
                }
            }
            Assert.isTrue(c1Row.sourceLabel.contains('Book A'), c1Row.sourceLabel);
            Assert.isTrue(c1Row.sourceLabel.contains('Added directly'), c1Row.sourceLabel);
            Assert.areEqual(1, c1Row.executions.size(), 'One eager unclaimed slot per case.');
            Assert.isNull(c1Row.executions[0].testerName, 'Chip reads Unclaimed.');
            Assert.areEqual(2, detail.teamMembers.size(), 'Add-tester options from the team.');
        }
    }

    @IsTest
    static void addTesterCreatesAdditionalIndependentRun() {
        User tester1 = byLastName('UAT uattst1');
        User tester2 = byLastName('UAT uattst2');
        System.runAs(byLastName('UAT uatadm')) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
            Test_Case__c c1 = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1001);
            Team__c team = UatTestDataFactory.makeTeam('Alpha', new List<Id>{ tester1.Id, tester2.Id });
            Test_Cycle__c cycle = UatTestDataFactory.makeCycle('Sprint 1', team.Id, null, new List<Id>{ c1.Id });

            // Claim the eager slot as tester1, then add tester2.
            Test_Execution__c slot = [SELECT Id FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id];
            UatExecutionService.claim(slot.Id, tester1.Id);

            Test.startTest();
            UatCycleAdminController.ExecutionChipDTO chip =
                UatCycleAdminController.addTesterExecution(cycle.Id, c1.Id, tester2.Id);
            Test.stopTest();

            Assert.areNotEqual(slot.Id, chip.id, 'A NEW independent execution.');
            Assert.areEqual(2, [
                SELECT COUNT() FROM Test_Execution__c
                WHERE Test_Cycle__c = :cycle.Id AND Test_Case__c = :c1.Id
            ]);
        }
    }

    @IsTest
    static void cycleListAggregates() {
        User tester1 = byLastName('UAT uattst1');
        System.runAs(byLastName('UAT uatadm')) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
            Test_Case__c c1 = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1001);
            Test_Book__c book = UatTestDataFactory.makeBook('Book A', new List<Id>{ c1.Id });
            Test_Cycle__c cycle = UatTestDataFactory.makeCycle('Sprint 1', null,
                new List<Id>{ book.Id }, null);
            insert new Exploratory_Finding__c(
                Test_Cycle__c = cycle.Id,
                What_Testing__c = 'Poking around',
                Tester__c = tester1.Id,
                Date__c = Date.today()
            );

            Test.startTest();
            List<UatCycleAdminController.CycleRowDTO> rows = UatCycleAdminController.getCycles();
            Test.stopTest();

            Assert.areEqual(1, rows.size());
            Assert.areEqual('Book A', rows[0].bookNames);
            Assert.isFalse(rows[0].hasDirectCases);
            Assert.areEqual(1, rows[0].totalExecutions, 'Y counts EXECUTIONS.');
            Assert.areEqual(0, rows[0].completeCount);
            Assert.areEqual(1, rows[0].findingsCount);
        }
    }

    @IsTest
    static void duplicateJunctionsRejected() {
        System.runAs(byLastName('UAT uatadm')) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
            Test_Case__c c1 = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1001);
            Test_Book__c book = UatTestDataFactory.makeBook('Book A', new List<Id>{ c1.Id });
            Test_Cycle__c cycle = UatTestDataFactory.makeCycle('Sprint 1', null,
                new List<Id>{ book.Id }, new List<Id>{ c1.Id });

            try {
                UatCycleAdminController.attachBook(cycle.Id, book.Id);
                Assert.fail('Duplicate book attach should throw.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('already'), e.getMessage());
            }
            try {
                UatCycleAdminController.addDirectCase(cycle.Id, c1.Id);
                Assert.fail('Duplicate direct case should throw.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('already'), e.getMessage());
            }
        }
    }

    @IsTest
    static void closeAndReopenCycle() {
        System.runAs(byLastName('UAT uatadm')) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
            Test_Case__c c1 = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1001);
            Test_Cycle__c cycle = UatTestDataFactory.makeCycle('Sprint 1', null, null,
                new List<Id>{ c1.Id });

            Test.startTest();
            UatCycleAdminController.setCycleStatus(cycle.Id, 'Closed');
            Test.stopTest();

            Assert.areEqual('Closed', UatCycleAdminController.getCycles()[0].status);
            Assert.areEqual('Closed', UatCycleAdminController.getCycleDetail(cycle.Id).status);

            // Reversible: nothing was deleted, reopening restores as-was.
            UatCycleAdminController.setCycleStatus(cycle.Id, 'Active');
            Assert.areEqual('Active', UatCycleAdminController.getCycles()[0].status);
            Assert.areEqual(1, [SELECT COUNT() FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id]);

            try {
                UatCycleAdminController.setCycleStatus(cycle.Id, 'Bogus');
                Assert.fail('Unknown status should throw.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('status'), e.getMessage());
            }
        }
    }

    @IsTest
    static void draftCasesGatedOutOfCycles() {
        System.runAs(byLastName('UAT uatadm')) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
            Test_Case__c done = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1001);
            Test_Case__c draft = new Test_Case__c(
                Module__c = tax.mod.Id,
                Version__c = 'v1.0',
                Sequence__c = 1002,
                Creation_Status__c = 'Draft',
                Testing_Surface__c = 'Lightning App (Internal)'
            );
            insert draft;
            Test_Cycle__c cycle = UatTestDataFactory.makeCycle('Sprint 1', null, null, null);

            UatCycleAdminController.CycleDetailDTO detail =
                UatCycleAdminController.getCycleDetail(cycle.Id);
            Assert.areEqual(1, detail.availableCases.size(), 'Draft case is not offered.');
            Assert.areEqual(done.Id, detail.availableCases[0].targetId);

            try {
                UatCycleAdminController.addDirectCase(cycle.Id, draft.Id);
                Assert.fail('Adding a Draft case should throw.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('Complete'), e.getMessage());
            }
        }
    }

    @IsTest
    static void cloneCopiesScopeAndTeamWithFreshSlots() {
        User tester1 = byLastName('UAT uattst1');
        System.runAs(byLastName('UAT uatadm')) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
            Test_Case__c c1 = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1001);
            Test_Case__c c2 = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1002);
            Test_Book__c book = UatTestDataFactory.makeBook('Book A', new List<Id>{ c1.Id });
            Team__c team = UatTestDataFactory.makeTeam('Alpha', new List<Id>{ tester1.Id });
            Test_Cycle__c source = UatTestDataFactory.makeCycle('Sprint 1', team.Id,
                new List<Id>{ book.Id }, new List<Id>{ c2.Id });

            Test.startTest();
            Id cloneId = UatCycleAdminController.cloneCycle(source.Id);
            Test.stopTest();

            Test_Cycle__c clone = [
                SELECT Name, Assigned_Team__c, Target_Date__c
                FROM Test_Cycle__c WHERE Id = :cloneId
            ];
            Assert.areEqual('Sprint 1 (copy)', clone.Name);
            Assert.areEqual(team.Id, clone.Assigned_Team__c, 'Team carries over.');
            Assert.isNull(clone.Target_Date__c, 'A new run gets its own date.');
            Assert.areEqual(1, [
                SELECT COUNT() FROM Test_Cycle_Book__c WHERE Test_Cycle__c = :cloneId
            ], 'Book junction copied.');
            Assert.areEqual(1, [
                SELECT COUNT() FROM Test_Cycle_Case__c WHERE Test_Cycle__c = :cloneId
            ], 'Direct-case junction copied.');
            Assert.areEqual(2, [
                SELECT COUNT() FROM Test_Execution__c
                WHERE Test_Cycle__c = :cloneId AND Assigned_Tester__c = null
            ], 'Fresh unclaimed slots materialized for the full scope.');
        }
    }

    @IsTest
    static void testerCannotWrite() {
        User tester = byLastName('UAT uattst1');
        System.runAs(tester) {
            try {
                UatCycleAdminController.saveCycle(JSON.serialize(new Map<String, Object>{ 'name' => 'Rogue' }));
                Assert.fail('Tester write should throw.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('access'), e.getMessage());
            }
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Test_Cycle__c]);
    }

    // ---- Per-cycle focus prompts (exploratory-session notes chips) ----------------

    /* Round-trips through saveCycle -> getCycleDetail. Worth its own test
     * because saveCycle runs Security.stripInaccessible: without editable FLS
     * on UAT_Admin the field is dropped SILENTLY, with a green save and no
     * value stored. */
    @IsTest
    static void saveCycleRoundTripsFocusPrompts() {
        System.runAs(byLastName('UAT uatadm')) {
            Id cycleId = UatCycleAdminController.saveCycle(JSON.serialize(
                new Map<String, Object>{ 'name' => 'Prompted Sprint' }));
            String prompts = 'Steps | Steps to reproduce:\nRegression';

            Test.startTest();
            UatCycleAdminController.saveCycle(JSON.serialize(new Map<String, Object>{
                'id' => cycleId,
                'name' => 'Prompted Sprint',
                'focusPrompts' => prompts
            }));
            Test.stopTest();

            UatCycleAdminController.CycleDetailDTO detail =
                UatCycleAdminController.getCycleDetail(cycleId);
            Assert.areEqual(prompts, detail.focusPrompts,
                'The override must survive stripInaccessible.');
        }
    }

    /** Blank normalizes to null so "inherit the org defaults" is one state. */
    @IsTest
    static void blankFocusPromptsNormalizeToNull() {
        System.runAs(byLastName('UAT uatadm')) {
            Id cycleId = UatCycleAdminController.saveCycle(JSON.serialize(
                new Map<String, Object>{
                    'name' => 'Blanked Sprint',
                    'focusPrompts' => '   '
                }));
            Assert.isNull([
                SELECT Focus_Prompts__c FROM Test_Cycle__c WHERE Id = :cycleId
            ].Focus_Prompts__c);
        }
    }

    // ---- Open-pool additions (design §2, §3.2, §5) -------------------------------

    @IsTest
    static void saveCycleRoundTripsPoolSettingsAndReconciles() {
        User tester1 = byLastName('UAT uattst1');
        System.runAs(byLastName('UAT uatadm')) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
            Test_Case__c c1 = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1001);
            Test_Cycle__c cycle = UatTestDataFactory.makeCycle('Sprint 1', null, null, new List<Id>{ c1.Id });
            UatExecutionService.claimSeat(cycle.Id, c1.Id, tester1.Id);
            Assert.areEqual(1, [SELECT COUNT() FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id],
                'Capacity 1: seat full, no slot.');

            Test.startTest();
            UatCycleAdminController.saveCycle(JSON.serialize(new Map<String, Object>{
                'id' => cycle.Id,
                'name' => 'Sprint 1',
                'maxTesters' => 2,
                'claimLimitPerTester' => 3,
                'staleClaimDays' => 5
            }));
            Test.stopTest();

            UatCycleAdminController.CycleDetailDTO detail =
                UatCycleAdminController.getCycleDetail(cycle.Id);
            Assert.areEqual(2, detail.maxTesters);
            Assert.areEqual(3, detail.claimLimitPerTester);
            Assert.areEqual(5, detail.staleClaimDays);
            Assert.areEqual(2, [SELECT COUNT() FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id],
                'Raising capacity on save reconciled the seats — a slot reopened.');
        }
    }

    /** Field precision is (3,0): 100 must save (the original bug — the field
     *  shipped as 2 digits and 100 died as a raw DML error), 1000 must be
     *  rejected with a readable message instead of leaking the DML error. */
    @IsTest
    static void saveCycleEnforcesNumericBounds() {
        System.runAs(byLastName('UAT uatadm')) {
            Id cycleId = UatCycleAdminController.saveCycle(JSON.serialize(new Map<String, Object>{
                'name' => 'Wizard End-to-End Testing',
                'maxTesters' => 100
            }));
            Assert.areEqual(100,
                UatCycleAdminController.getCycleDetail(cycleId).maxTesters,
                'Three-digit seat counts fit the widened field.');

            try {
                UatCycleAdminController.saveCycle(JSON.serialize(new Map<String, Object>{
                    'name' => 'Too big', 'maxTesters' => 1000
                }));
                Assert.fail('Max Testers above 999 should be rejected.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('between 1 and 999'), e.getMessage());
            }
            try {
                UatCycleAdminController.saveCycle(JSON.serialize(new Map<String, Object>{
                    'name' => 'Too big', 'claimLimitPerTester' => 1000
                }));
                Assert.fail('Claim limit above 999 should be rejected.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('between 1 and 999'), e.getMessage());
            }
            try {
                UatCycleAdminController.saveCycle(JSON.serialize(new Map<String, Object>{
                    'name' => 'Too big', 'staleClaimDays' => 1000
                }));
                Assert.fail('Stale days above 999 should be rejected.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('between 1 and 999'), e.getMessage());
            }
        }
    }

    @IsTest
    static void claimsPausedStatusRoundTrip() {
        System.runAs(byLastName('UAT uatadm')) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
            Test_Case__c c1 = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1001);
            Test_Cycle__c cycle = UatTestDataFactory.makeCycle('Sprint 1', null, null, new List<Id>{ c1.Id });

            UatCycleAdminController.setCycleStatus(cycle.Id, 'Claims Paused');
            Assert.areEqual('Claims Paused',
                UatCycleAdminController.getCycleDetail(cycle.Id).status);
            try {
                UatExecutionService.claimSeat(cycle.Id, c1.Id, byLastName('UAT uattst1').Id);
                Assert.fail('Paused cycles take no new claims.');
            } catch (UatExecutionService.UatExecutionException e) {
                Assert.isTrue(e.getMessage().contains('claims'), e.getMessage());
            }
            UatCycleAdminController.setCycleStatus(cycle.Id, 'Active');
            Assert.areEqual('Active', UatCycleAdminController.getCycleDetail(cycle.Id).status);
        }
    }

    @IsTest
    static void forceUnassignRequiresReasonAndReopensSeat() {
        User tester1 = byLastName('UAT uattst1');
        System.runAs(byLastName('UAT uatadm')) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
            Test_Case__c c1 = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1001);
            Test_Cycle__c cycle = UatTestDataFactory.makeCycle('Sprint 1', null, null, new List<Id>{ c1.Id });
            Test_Execution__c claimed = UatExecutionService.claimSeat(cycle.Id, c1.Id, tester1.Id);

            try {
                UatCycleAdminController.forceUnassign(JSON.serialize(new Map<String, Object>{
                    'executionId' => claimed.Id
                }));
                Assert.fail('Unassign without a reason must be rejected.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('reason'), e.getMessage());
            }

            Test.startTest();
            UatCycleAdminController.forceUnassign(JSON.serialize(new Map<String, Object>{
                'executionId' => claimed.Id,
                'reason' => 'Tester is out this sprint'
            }));
            Test.stopTest();

            Assert.isNull([
                SELECT Assigned_Tester__c FROM Test_Execution__c WHERE Id = :claimed.Id
            ].Assigned_Tester__c, 'Pristine unassign reverted the seat to the pool.');
            Test_Assignment_Event__c event = [
                SELECT Tester__c, Actor__c, Reason__c FROM Test_Assignment_Event__c
                WHERE Action__c = 'Force Unassigned'
            ];
            Assert.areEqual(tester1.Id, event.Tester__c);
            Assert.areEqual(byLastName('UAT uatadm').Id, event.Actor__c,
                'The admin is the actor, the tester is the affected user.');
        }
    }

    @IsTest
    static void reassignHandsTheNewTesterTheirOwnRun() {
        User tester1 = byLastName('UAT uattst1');
        User tester2 = byLastName('UAT uattst2');
        System.runAs(byLastName('UAT uatadm')) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
            Test_Case__c c1 = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1001);
            Test_Cycle__c cycle = UatTestDataFactory.makeCycle('Sprint 1', null, null, new List<Id>{ c1.Id });
            Test_Execution__c claimed = UatExecutionService.claimSeat(cycle.Id, c1.Id, tester1.Id);
            // Record work so the old run must be preserved, not recycled.
            List<Test_Step_Result__c> results = UatExecutionService.ensureStepResults(claimed.Id);
            results[0].Result__c = 'Fail';
            update results[0];

            Test.startTest();
            UatCycleAdminController.ExecutionChipDTO chip =
                UatCycleAdminController.reassignTester(JSON.serialize(new Map<String, Object>{
                    'executionId' => claimed.Id,
                    'newTesterId' => tester2.Id,
                    'reason' => 'Rebalancing the sprint'
                }));
            Test.stopTest();

            Assert.areNotEqual(claimed.Id, chip.id, 'The new tester gets their OWN execution.');
            Assert.areEqual(tester2.Id, chip.testerId);
            Assert.isTrue([
                SELECT Released__c FROM Test_Execution__c WHERE Id = :claimed.Id
            ].Released__c, 'The old run is kept as history with its results.');
            Assert.areEqual(0, [
                SELECT COUNT() FROM Test_Execution__c
                WHERE Test_Cycle__c = :cycle.Id AND Assigned_Tester__c = null
            ], 'Net seats unchanged — no slot reopened by the swap.');
        }
    }

    // ---- Delete cycle (2026-08-05: purge-then-delete) ----------------------------

    /** Team(tester1) cycle with one claimed+started run, a session, and a finding. */
    private static Test_Cycle__c populatedCycle() {
        UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Purge');
        Test_Case__c tc = UatTestDataFactory.makeCase(tax.mod.Id, 2, 1001);
        Team__c team = UatTestDataFactory.makeTeam('Alpha', new List<Id>{
            byLastName('UAT uattst1').Id
        });
        return UatTestDataFactory.makeCycle('Purge Sprint', team.Id, null, new List<Id>{ tc.Id });
    }

    @IsTest
    static void deleteCycleImpactCountsRunsSessionsFindingsAndLinks() {
        Test_Cycle__c cycle = populatedCycle();
        System.runAs(byLastName('UAT uattst1')) {
            Test_Execution__c slot = [
                SELECT Id FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id
            ];
            UatRunController.claimAndStart(slot.Id);
            UatRunController.startExecution(slot.Id); // materializes step results
            Id sessionId = UatSessionController.startSession(JSON.serialize(new Map<String, Object>{
                'title' => 'Impact session', 'charter' => 'Counting things.', 'cycleId' => cycle.Id
            }));
            UatRunController.saveFinding(JSON.serialize(new Map<String, Object>{
                'sessionId' => sessionId,
                'title' => 'Impact finding for the delete counts',
                'type' => 'Question',
                'whatHappened' => 'Something worth counting'
            }));
        }

        System.runAs(byLastName('UAT uatadm')) {
            Test.startTest();
            UatCycleAdminController.CycleDeleteImpactDTO impact =
                UatCycleAdminController.getCycleDeleteImpact(cycle.Id);
            Test.stopTest();

            Assert.areEqual('Purge Sprint', impact.cycleName);
            Assert.areEqual(1, impact.executions);
            Assert.areEqual(1, impact.claimedRuns, 'The claimed run is the scary number.');
            Assert.areEqual(2, impact.stepResults, 'Both materialized step results counted.');
            Assert.areEqual(1, impact.sessions);
            Assert.areEqual(1, impact.findings);
            Assert.areEqual(0, impact.bookLinks);
            Assert.areEqual(1, impact.directCases);
        }
    }

    @IsTest
    static void deleteCyclePurgesHistoryAndCascades() {
        Test_Cycle__c cycle = populatedCycle();
        Id caseId = [SELECT Id FROM Test_Case__c LIMIT 1].Id;
        Id standaloneId;
        System.runAs(byLastName('UAT uattst1')) {
            Test_Execution__c slot = [
                SELECT Id FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id
            ];
            UatRunController.claimAndStart(slot.Id); // writes an audit event
            UatRunController.startExecution(slot.Id);
            Id sessionId = UatSessionController.startSession(JSON.serialize(new Map<String, Object>{
                'title' => 'Purge session', 'charter' => 'Doomed.', 'cycleId' => cycle.Id
            }));
            UatRunController.saveFinding(JSON.serialize(new Map<String, Object>{
                'sessionId' => sessionId,
                'title' => 'Doomed finding, purged with its cycle',
                'type' => 'Question',
                'whatHappened' => 'Something the purge should remove'
            }));
            // Cycle-less session — the purge must not touch it.
            standaloneId = UatSessionController.startSession(JSON.serialize(new Map<String, Object>{
                'title' => 'Standalone bystander', 'charter' => 'Survives.'
            }));
        }
        List<Test_Assignment_Event__c> auditBefore = [
            SELECT Id FROM Test_Assignment_Event__c WHERE Test_Cycle__c = :cycle.Id
        ];
        Assert.isFalse(auditBefore.isEmpty(), 'The claim audited — fixture sanity.');

        System.runAs(byLastName('UAT uatadm')) {
            Test.startTest();
            UatCycleAdminController.deleteCycle(cycle.Id);
            Test.stopTest();
        }

        Assert.areEqual(0, [SELECT COUNT() FROM Test_Cycle__c WHERE Id = :cycle.Id]);
        Assert.areEqual(0, [SELECT COUNT() FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id]);
        Assert.areEqual(0, [SELECT COUNT() FROM Test_Step_Result__c]);
        Assert.areEqual(0, [
            SELECT COUNT() FROM Exploratory_Session__c WHERE Test_Cycle__c = :cycle.Id
        ], 'The cycle\'s sessions are purged explicitly (Restrict lookup, no cascade).');
        Assert.areEqual(0, [SELECT COUNT() FROM Exploratory_Finding__c]);
        Assert.areEqual(1, [
            SELECT COUNT() FROM Exploratory_Session__c WHERE Id = :standaloneId
        ], 'A standalone session is untouched by a cycle purge.');
        Assert.areEqual(0, [SELECT COUNT() FROM Test_Cycle_Case__c WHERE Test_Cycle__c = :cycle.Id]);
        Assert.areEqual(1, [SELECT COUNT() FROM Test_Case__c WHERE Id = :caseId],
            'Definitions are never touched.');
        for (Test_Assignment_Event__c evt : [
            SELECT Test_Cycle__c FROM Test_Assignment_Event__c WHERE Id IN :auditBefore
        ]) {
            Assert.isNull(evt.Test_Cycle__c, 'Audit rows survive with the lookup nulled.');
        }
    }

    @IsTest
    static void deleteCycleGateNegative() {
        Test_Cycle__c cycle = populatedCycle();
        System.runAs(byLastName('UAT uattst1')) {
            try {
                UatCycleAdminController.deleteCycle(cycle.Id);
                Assert.fail('Testers must not delete cycles.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('access'), e.getMessage());
            }
        }
        Assert.areEqual(1, [SELECT COUNT() FROM Test_Cycle__c WHERE Id = :cycle.Id],
            'Blocked delete left the cycle intact.');
    }
}