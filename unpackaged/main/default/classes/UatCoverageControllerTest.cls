/**
 * Tests for UatCoverageController — the Pool Health section: per-cycle
 * coverage rollups, the at-risk flag, the unclaimed drill-down, and the
 * assignment-event feed. Read-only surface; the seat mechanics themselves are
 * covered by UatExecutionServiceTest.
 */
@IsTest
private class UatCoverageControllerTest {

    @TestSetup
    static void setup() {
        UatTestDataFactory.createAdminUser('uatadm');
        UatTestDataFactory.createTesterUser('uattst1');
    }

    private static User byLastName(String lastName) {
        return [SELECT Id FROM User WHERE LastName = :lastName LIMIT 1];
    }

    @IsTest
    static void coverageRollsUpSeatsAndFlagsRisk() {
        User tester1 = byLastName('UAT uattst1');
        System.runAs(byLastName('UAT uatadm')) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
            Test_Case__c c1 = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1001);
            Test_Case__c c2 = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1002);
            Test_Cycle__c cycle = UatTestDataFactory.makeCycle('Sprint 1', null, null,
                new List<Id>{ c1.Id, c2.Id });
            // Target inside the risk window with open work -> at risk.
            cycle.Target_Date__c = Date.today().addDays(3);
            update cycle;
            UatExecutionService.claimSeat(cycle.Id, c1.Id, tester1.Id);

            Test.startTest();
            List<UatCoverageController.CycleHealthDTO> rows = UatCoverageController.getCoverage();
            Test.stopTest();

            Assert.areEqual(1, rows.size());
            UatCoverageController.CycleHealthDTO row = rows[0];
            Assert.areEqual(2, row.caseCount, 'Distinct cases in scope.');
            Assert.areEqual(1, row.unclaimedSeats, 'c2 still open.');
            Assert.areEqual(1, row.notStartedClaims, 'c1 claimed but not started.');
            Assert.areEqual(0, row.oldestUnclaimedDays, 'The open seat opened today.');
            Assert.areEqual(3, row.daysToTarget);
            Assert.isTrue(row.atRisk, 'Open work + target within the window = at risk.');

            UatCoverageController.DrilldownDTO drill =
                UatCoverageController.getCycleDrilldown(cycle.Id);
            Assert.areEqual(1, drill.unclaimed.size());
            Assert.areEqual(c2.Id, [
                SELECT Test_Case__c FROM Test_Execution__c WHERE Id = :drill.unclaimed[0].executionId
            ].Test_Case__c);
            Assert.areEqual(1, drill.events.size(), 'The claim is in the feed.');
            Assert.areEqual('Claimed', drill.events[0].action);
        }
    }

    @IsTest
    static void closedCyclesAndComfortableTargetsAreCalm() {
        System.runAs(byLastName('UAT uatadm')) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
            Test_Case__c c1 = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1001);
            Test_Cycle__c comfy = UatTestDataFactory.makeCycle('Comfy', null, null, new List<Id>{ c1.Id });
            Test_Cycle__c closed = UatTestDataFactory.makeCycle('Done', null, null, new List<Id>{ c1.Id });
            closed.Status__c = 'Closed';
            update closed;

            List<UatCoverageController.CycleHealthDTO> rows = UatCoverageController.getCoverage();
            Assert.areEqual(1, rows.size(), 'Closed cycles drop out of pool health.');
            Assert.areEqual(comfy.Id, rows[0].cycleId);
            Assert.isFalse(rows[0].atRisk, 'Two weeks out (factory default) is comfortable.');
        }
    }

    @IsTest
    static void dashboardSummaryAggregatesAndFindsHero() {
        User tester1 = byLastName('UAT uattst1');
        System.runAs(byLastName('UAT uatadm')) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
            Test_Case__c c1 = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1001);
            Test_Case__c c2 = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1002);
            Team__c team = UatTestDataFactory.makeTeam('Alpha', new List<Id>{ tester1.Id });
            Test_Cycle__c cycle = UatTestDataFactory.makeCycle('Sprint 1', team.Id, null,
                new List<Id>{ c1.Id, c2.Id });
            cycle.Target_Date__c = Date.today().addDays(3);
            update cycle;
            UatExecutionService.claimSeat(cycle.Id, c1.Id, tester1.Id);

            Test.startTest();
            UatCoverageController.DashboardSummaryDTO summary = UatCoverageController.getDashboardSummary();
            Test.stopTest();

            Assert.areEqual(1, summary.atRiskCycles);
            Assert.areEqual(1, summary.unclaimedSeats, 'c2 still open.');
            Assert.areEqual(0, summary.failedRuns);
            Assert.areEqual(cycle.Id, summary.heroCycle.cycleId);
            Assert.areEqual(1, summary.atRisk.size());
            Assert.areEqual(1, summary.testersTotal, 'One team member on the cycle\'s team.');
            Assert.areEqual(1, summary.testersParticipating, 'tester1 claimed a seat.');
        }
    }

    @IsTest
    static void dashboardSummaryOmitsDenominatorForTeamlessCycles() {
        System.runAs(byLastName('UAT uatadm')) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
            Test_Case__c c1 = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1001);
            UatTestDataFactory.makeCycle('Open Sprint', null, null, new List<Id>{ c1.Id });

            UatCoverageController.DashboardSummaryDTO summary = UatCoverageController.getDashboardSummary();
            Assert.isNull(summary.testersTotal, 'No assigned team = no fixed roster to divide by.');
        }
    }

    @IsTest
    static void testersCannotReadPoolHealth() {
        System.runAs(byLastName('UAT uattst1')) {
            try {
                UatCoverageController.getCoverage();
                Assert.fail('Coverage keys on the cycle-manage capability.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('access'), e.getMessage());
            }
        }
    }
}