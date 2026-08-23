/**
 * HelpGuideControllerTest
 *
 * getGuide reads custom metadata (Help_Guide__mdt et al), which cannot be
 * inserted in a test. It relies on the shipped starter guide records; the
 * structural assertions run only if an active guide is deployed, so the test is
 * stable whether or not the starter config is present.
 */
@isTest
private class HelpGuideControllerTest {

    @isTest
    static void invalidKeyThrows() {
        try {
            HelpGuideController.getGuide('bad key!!');
            Assert.fail('Expected invalid-key error.');
        } catch (AuraHandledException e) { /* expected */ }
    }

    @isTest
    static void unknownKeyReturnsNull() {
        Assert.isNull(HelpGuideController.getGuide('no_such_guide'),
            'Unknown key yields null so the client stays inert.');
    }

    @isTest
    static void shippedGuideResolvesTree() {
        List<Help_Guide__mdt> active = [
            SELECT Guide_Key__c FROM Help_Guide__mdt WHERE Active__c = true LIMIT 1
        ];
        if (active.isEmpty()) {
            return; // no starter config in this org — nothing to assert
        }
        HelpGuideController.GuideDTO dto = HelpGuideController.getGuide(active[0].Guide_Key__c);
        Assert.isNotNull(dto, 'Active guide resolves.');
        Assert.isNotNull(dto.nodes, 'Nodes list is present.');
        if (!dto.nodes.isEmpty()) {
            Assert.isNotNull(dto.rootNodeKey, 'A root node key is resolved when nodes exist.');
        }
    }
}