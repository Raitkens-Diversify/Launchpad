/**
 * UatAdminAccessServiceTest — the UAT Admin Console gate. Capability-driven:
 * a user with the UAT_Admin permission set sees every section; a tester
 * (read-only on the roots) and a minimal user see none.
 */
@IsTest
private class UatAdminAccessServiceTest {

    @TestSetup
    static void setup() {
        UatTestDataFactory.createAdminUser('uaaadm');
        UatTestDataFactory.createTesterUser('uaatst');
        UatTestDataFactory.createUser('uaamin', new List<String>());
    }

    private static User byLastName(String lastName) {
        return [SELECT Id FROM User WHERE LastName = :lastName LIMIT 1];
    }

    @IsTest
    static void uatAdminSeesEverySection() {
        System.runAs(byLastName('UAT uaaadm')) {
            Test.startTest();
            UatAdminAccessService.AccessDTO dto = UatAdminAccessService.getAccess();
            Test.stopTest();

            System.assertEquals(true, dto.uatCycles, 'UAT_Admin grants Test_Cycle__c create/edit');
            System.assertEquals(true, dto.uatBooks, 'UAT_Admin grants Test_Book__c create/edit');
            System.assertEquals(true, dto.uatCases, 'UAT_Admin grants Test_Case__c create/edit');
            System.assertEquals(true, dto.uatTaxonomy, 'UAT_Admin grants System__c create/edit');
            System.assertEquals(true, dto.uatTeams, 'UAT_Admin grants Team__c create/edit');
            System.assertEquals(true, dto.uatCoverage, 'Coverage = cycles + audit-trail read');
            System.assertEquals(true, dto.uatDashboard, 'Dashboard shares the coverage gate');
            System.assertEquals(true, dto.uatReport, 'Report shares the coverage gate');
            System.assertEquals(true, dto.anySection, 'At least one section visible');
        }
    }

    @IsTest
    static void testerSeesNoAdminSections() {
        System.runAs(byLastName('UAT uaatst')) {
            Test.startTest();
            UatAdminAccessService.AccessDTO dto = UatAdminAccessService.getAccess();
            Test.stopTest();

            System.assertEquals(false, dto.uatCycles, 'Testers are read-only on cycles');
            System.assertEquals(false, dto.uatBooks, 'Testers are read-only on books');
            System.assertEquals(false, dto.uatCases, 'Testers are read-only on cases');
            System.assertEquals(false, dto.uatTaxonomy, 'Testers are read-only on taxonomy');
            System.assertEquals(false, dto.uatTeams, 'Testers are read-only on teams');
            System.assertEquals(false, dto.uatCoverage, 'Coverage follows the cycles gate');
            System.assertEquals(false, dto.uatDashboard, 'Dashboard follows the coverage gate');
            System.assertEquals(false, dto.uatReport, 'Report follows the coverage gate');
            System.assertEquals(false, dto.anySection, 'Nothing to render');
        }
    }

    @IsTest
    static void minimalUserSeesNothing() {
        System.runAs(byLastName('UAT uaamin')) {
            UatAdminAccessService.AccessDTO dto = UatAdminAccessService.getAccess();
            System.assertEquals(false, dto.anySection, 'No UAT object perms means no sections');
        }
    }
}