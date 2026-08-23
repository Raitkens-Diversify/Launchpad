/**
 * Tests for UatTaxonomyAdminController — the Admin Console UAT Taxonomy
 * section. Users come from UatTestDataFactory, which strips the permission
 * sets org automation auto-assigns to every new user, so the access-gating
 * assertions here test exactly what UAT_Admin / UAT_Tester grant.
 */
@IsTest
private class UatTaxonomyAdminControllerTest {

    @TestSetup
    static void setup() {
        UatTestDataFactory.createAdminUser('uatadm');
        UatTestDataFactory.createTesterUser('uattst');
    }

    private static User adminUser() {
        return [SELECT Id FROM User WHERE LastName = 'UAT uatadm' LIMIT 1];
    }

    private static User testerUser() {
        return [SELECT Id FROM User WHERE LastName = 'UAT uattst' LIMIT 1];
    }

    private static String node(Id id, String name, String code, String description, Id parentId) {
        UatTaxonomyAdminController.NodeInput input = new UatTaxonomyAdminController.NodeInput();
        input.id = id;
        input.name = name;
        input.code = code;
        input.description = description;
        input.parentId = parentId;
        return JSON.serialize(input);
    }

    @IsTest
    static void adminBuildsAndReadsThreeLevels() {
        System.runAs(adminUser()) {
            Test.startTest();
            // Messy code input on purpose: normalization must strip to a-z0-9.
            Id sysId = UatTaxonomyAdminController.saveSystem(
                node(null, '  Helios ', 'HEL iOS!', 'The CRM', null));
            Id grpId = UatTaxonomyAdminController.saveModuleGroup(
                node(null, 'Client Management', null, null, sysId));
            Id modId = UatTaxonomyAdminController.saveModule(
                node(null, 'Households', null, null, grpId));
            List<UatTaxonomyAdminController.SystemDTO> tree =
                UatTaxonomyAdminController.getTaxonomy();
            Test.stopTest();

            Assert.areEqual(1, tree.size(), 'One system.');
            Assert.areEqual(sysId, tree[0].id);
            Assert.areEqual('Helios', tree[0].name, 'Name trimmed.');
            Assert.areEqual('helios', tree[0].code, 'Code normalized to a-z0-9.');
            Assert.areEqual(1, tree[0].groups.size(), 'One group under the system.');
            Assert.areEqual(grpId, tree[0].groups[0].id);
            Assert.areEqual(1, tree[0].groups[0].modules.size(), 'One module under the group.');
            Assert.areEqual(modId, tree[0].groups[0].modules[0].id);
        }
    }

    @IsTest
    static void adminEditsExistingSystem() {
        System.runAs(adminUser()) {
            Id sysId = UatTaxonomyAdminController.saveSystem(
                node(null, 'Helios', 'helios', null, null));

            Test.startTest();
            Id savedId = UatTaxonomyAdminController.saveSystem(
                node(sysId, 'Helios CRM', 'helios', 'Renamed', null));
            Test.stopTest();

            Assert.areEqual(sysId, savedId, 'Edit returns the same record.');
            System__c saved = [SELECT Name, Description__c FROM System__c WHERE Id = :sysId];
            Assert.areEqual('Helios CRM', saved.Name);
            Assert.areEqual('Renamed', saved.Description__c);
            Assert.areEqual(1, [SELECT COUNT() FROM System__c], 'No duplicate created.');
        }
    }

    @IsTest
    static void blankNameAndBlankCodeRejected() {
        System.runAs(adminUser()) {
            try {
                UatTaxonomyAdminController.saveSystem(node(null, '   ', 'helios', null, null));
                Assert.fail('Blank name should throw.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('name'), 'Blank-name message: ' + e.getMessage());
            }
            try {
                UatTaxonomyAdminController.saveSystem(node(null, 'Helios', '!!!', null, null));
                Assert.fail('Code that normalizes to nothing should throw.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('code'), 'Blank-code message: ' + e.getMessage());
            }
        }
    }

    @IsTest
    static void groupRequiresParentOnCreate() {
        System.runAs(adminUser()) {
            try {
                UatTaxonomyAdminController.saveModuleGroup(node(null, 'Orphan Group', null, null, null));
                Assert.fail('Group without a system should throw.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('system'), 'Parent message: ' + e.getMessage());
            }
        }
    }

    @IsTest
    static void testerReadsButCannotWrite() {
        System.runAs(adminUser()) {
            Id sysId = UatTaxonomyAdminController.saveSystem(
                node(null, 'Helios', 'helios', null, null));
            UatTaxonomyAdminController.saveModuleGroup(
                node(null, 'Client Management', null, null, sysId));
        }
        System.runAs(testerUser()) {
            List<UatTaxonomyAdminController.SystemDTO> tree =
                UatTaxonomyAdminController.getTaxonomy();
            Assert.areEqual(1, tree.size(), 'Tester can read the taxonomy.');
            Assert.areEqual(1, tree[0].groups.size(), 'Tester sees groups too.');

            try {
                UatTaxonomyAdminController.saveSystem(node(null, 'Rogue', 'rogue', null, null));
                Assert.fail('Tester write should throw.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('access'), 'Access message: ' + e.getMessage());
            }
        }
        Assert.areEqual(1, [SELECT COUNT() FROM System__c], 'Nothing was written by the tester.');
    }

    @IsTest
    static void malformedJsonRejected() {
        System.runAs(adminUser()) {
            try {
                UatTaxonomyAdminController.saveSystem('{not json');
                Assert.fail('Malformed JSON should throw.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('refresh'), 'Friendly parse message: ' + e.getMessage());
            }
        }
    }

    // ---- Deletes (2026-08-05: blocked by descendant cases, else cascade) ----------

    @IsTest
    static void deleteModuleBlockedByCases() {
        System.runAs(adminUser()) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('TaxDel');
            UatTestDataFactory.makeCase(tax.mod.Id, 0, 1001);

            try {
                UatTaxonomyAdminController.deleteModule(tax.mod.Id);
                Assert.fail('A module with cases must not delete.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('test case'), e.getMessage());
                Assert.isFalse(e.getMessage().contains('DELETE_FAILED'),
                    'Friendly preflight, not the raw restrict error.');
            }
            Assert.areEqual(1, [SELECT COUNT() FROM Module__c WHERE Id = :tax.mod.Id]);

            // The whole chain is equally blocked from above.
            try {
                UatTaxonomyAdminController.deleteSystem(tax.sys.Id);
                Assert.fail('A system with descendant cases must not delete.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('test case'), e.getMessage());
            }
        }
    }

    @IsTest
    static void deleteSystemCascadesEmptyDescendants() {
        System.runAs(adminUser()) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('TaxDel');

            Test.startTest();
            UatTaxonomyAdminController.deleteSystem(tax.sys.Id);
            Test.stopTest();

            Assert.areEqual(0, [SELECT COUNT() FROM System__c WHERE Id = :tax.sys.Id]);
            Assert.areEqual(0, [SELECT COUNT() FROM Module_Group__c WHERE Id = :tax.grp.Id],
                'Empty groups cascade with the master-detail.');
            Assert.areEqual(0, [SELECT COUNT() FROM Module__c WHERE Id = :tax.mod.Id],
                'Empty modules cascade too.');
        }
    }

    @IsTest
    static void taxonomyDeleteImpactCountsPerLevel() {
        System.runAs(adminUser()) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('TaxDel');
            UatTestDataFactory.makeCase(tax.mod.Id, 0, 1001);
            UatTestDataFactory.makeCase(tax.mod.Id, 0, 1002);

            UatTaxonomyAdminController.TaxonomyDeleteImpactDTO sys =
                UatTaxonomyAdminController.getTaxonomyDeleteImpact('system', tax.sys.Id);
            Assert.areEqual(2, sys.caseCount);
            Assert.areEqual(1, sys.groupCount);
            Assert.areEqual(1, sys.moduleCount);

            UatTaxonomyAdminController.TaxonomyDeleteImpactDTO grp =
                UatTaxonomyAdminController.getTaxonomyDeleteImpact('group', tax.grp.Id);
            Assert.areEqual(2, grp.caseCount);
            Assert.areEqual(1, grp.moduleCount);

            UatTaxonomyAdminController.TaxonomyDeleteImpactDTO mod =
                UatTaxonomyAdminController.getTaxonomyDeleteImpact('module', tax.mod.Id);
            Assert.areEqual(2, mod.caseCount);

            try {
                UatTaxonomyAdminController.getTaxonomyDeleteImpact('galaxy', tax.sys.Id);
                Assert.fail('Unknown level should throw.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('Unknown taxonomy level'), e.getMessage());
            }
        }
    }

    @IsTest
    static void deleteTaxonomyGateNegative() {
        UatTestDataFactory.Taxonomy tax;
        System.runAs(adminUser()) {
            tax = UatTestDataFactory.makeTaxonomy('TaxDel');
        }
        System.runAs(testerUser()) {
            try {
                UatTaxonomyAdminController.deleteModule(tax.mod.Id);
                Assert.fail('Testers must not delete taxonomy entries.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('access'), e.getMessage());
            }
        }
        Assert.areEqual(1, [SELECT COUNT() FROM Module__c WHERE Id = :tax.mod.Id]);
    }
}