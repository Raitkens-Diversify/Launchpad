@isTest
private class HelpGuideAdminControllerTest {

    private class MockDeployer implements HelpGuideAdminController.MetadataDeployer {
        public Metadata.DeployContainer captured;
        public Id enqueue(Metadata.DeployContainer container, Metadata.DeployCallback callback) {
            this.captured = container;
            return null; // no real async deploy in tests
        }
    }

    private static Id newGuide() {
        return HelpGuideAdminController.saveDraftGuide(null, 'get_help', 'Get Help', true, 1);
    }

    @isTest
    static void createReadUpdateGuide() {
        Id gId = newGuide();
        HelpGuideAdminController.GuideDraftDTO dto = HelpGuideAdminController.getDraftGuide(gId);
        Assert.areEqual('get_help', dto.guideKey, 'Round-trips the key.');
        Assert.isFalse(HelpGuideAdminController.getDraftGuides().isEmpty(), 'Lists the draft.');

        HelpGuideAdminController.saveDraftGuide(gId, 'get_help', 'Get Help v2', true, 2);
        Assert.areEqual(2, HelpGuideAdminController.getDraftGuide(gId).version, 'Update applied.');
    }

    @isTest
    static void invalidGuideKeyThrows() {
        try {
            HelpGuideAdminController.saveDraftGuide(null, 'Bad Key!', 'x', true, 1);
            Assert.fail('Expected invalid-key error.');
        } catch (AuraHandledException e) {
            // expected
        }
    }

    @isTest
    static void nodeAutoKeyAndSingleRoot() {
        Id gId = newGuide();
        Id n1 = HelpGuideAdminController.saveDraftNode(null, gId, null, 'First?', null, true);
        Id n2 = HelpGuideAdminController.saveDraftNode(null, gId, null, 'Second?', null, true);

        Map<Id, HelpGuideAdminController.NodeDraftDTO> byId =
            new Map<Id, HelpGuideAdminController.NodeDraftDTO>();
        for (HelpGuideAdminController.NodeDraftDTO n : HelpGuideAdminController.getDraftGuide(gId).nodes) {
            byId.put(n.recordId, n);
        }
        Assert.areEqual('n1', byId.get(n1).nodeKey, 'First node gets n1.');
        Assert.areEqual('n2', byId.get(n2).nodeKey, 'Second node gets n2.');
        Assert.isFalse(byId.get(n1).isRoot, 'Setting n2 root cleared n1.');
        Assert.isTrue(byId.get(n2).isRoot, 'n2 is the single root.');
    }

    @isTest
    static void optionValidation() {
        Id gId = newGuide();
        Id nId = HelpGuideAdminController.saveDraftNode(null, gId, null, 'Q?', null, true);

        // node target with no value -> error
        try {
            HelpGuideAdminController.saveDraftOption(null, nId, null, 'Go', 'node', '  ');
            Assert.fail('node target needs a value.');
        } catch (AuraHandledException e) { /* expected */ }

        // case target with no value -> allowed
        Id caseOpt = HelpGuideAdminController.saveDraftOption(null, nId, null, 'Contact us', 'case', null);
        Assert.isNotNull(caseOpt, 'case option saves without a value.');

        // category target with value -> allowed
        Id catOpt = HelpGuideAdminController.saveDraftOption(null, nId, 2, 'Marketing', 'category', 'marketing');
        Assert.isNotNull(catOpt, 'category option saves.');

        HelpGuideAdminController.GuideDraftDTO dto = HelpGuideAdminController.getDraftGuide(gId);
        Assert.areEqual(2, dto.nodes[0].options.size(), 'Both options attached to the node.');

        HelpGuideAdminController.deleteDraftOption(catOpt);
        Assert.areEqual(1, HelpGuideAdminController.getDraftGuide(gId).nodes[0].options.size(),
            'Option deleted.');
    }

    @isTest
    static void publishBuildsContainer() {
        MockDeployer mock = new MockDeployer();
        HelpGuideAdminController.deployer = mock;

        Id gId = newGuide();
        Id nId = HelpGuideAdminController.saveDraftNode(null, gId, null, 'What do you need?', null, true);
        HelpGuideAdminController.saveDraftOption(null, nId, null, 'Marketing', 'category', 'marketing');

        Test.startTest();
        HelpGuideAdminController.publish(gId);
        Test.stopTest();

        Assert.isNotNull(mock.captured, 'Deploy container was built and enqueued.');
        Assert.isTrue(mock.captured.getMetadata().size() >= 3,
            'Container holds the guide + node + option metadata.');
    }

    @isTest
    static void publishWithoutNodesThrows() {
        HelpGuideAdminController.deployer = new MockDeployer();
        Id gId = newGuide();
        try {
            HelpGuideAdminController.publish(gId);
            Assert.fail('Expected "add a node" error.');
        } catch (AuraHandledException e) { /* expected */ }
    }

    @isTest
    static void publishWithoutRootThrows() {
        HelpGuideAdminController.deployer = new MockDeployer();
        Id gId = newGuide();
        HelpGuideAdminController.saveDraftNode(null, gId, null, 'Q?', null, false);
        try {
            HelpGuideAdminController.publish(gId);
            Assert.fail('Expected "mark a root" error.');
        } catch (AuraHandledException e) { /* expected */ }
    }

    @isTest
    static void guestCannotPublish() {
        HelpGuideAdminController.deployer = new MockDeployer();
        HelpGuideAdminController.guestOverride = true;
        Id gId = newGuide();
        HelpGuideAdminController.saveDraftNode(null, gId, null, 'Q?', null, true);
        try {
            HelpGuideAdminController.publish(gId);
            Assert.fail('Guests cannot publish.');
        } catch (AuraHandledException e) { /* expected */ }
    }

    @isTest
    static void deleteGuideCascades() {
        Id gId = newGuide();
        HelpGuideAdminController.saveDraftNode(null, gId, null, 'Q?', null, true);
        HelpGuideAdminController.deleteDraftGuide(gId);
        Assert.areEqual(0, [SELECT COUNT() FROM Help_Guide_Draft__c WHERE Id = :gId], 'Guide gone.');
        Assert.areEqual(0, [SELECT COUNT() FROM Help_Guide_Node_Draft__c WHERE Guide__c = :gId],
            'Nodes cascaded.');
    }

    @isTest
    static void importUnknownKeyThrows() {
        try {
            HelpGuideAdminController.importFromPublished('no_such_guide_key');
            Assert.fail('Expected not-found error.');
        } catch (AuraHandledException e) { /* expected */ }
    }
}