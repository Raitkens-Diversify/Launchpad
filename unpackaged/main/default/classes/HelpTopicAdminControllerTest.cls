@IsTest
private class HelpTopicAdminControllerTest {

    /** The deployer's own access is not enough in production; see HelpCenterTestDataFactory. */
    @TestSetup
    static void grantAccess() {
        HelpCenterTestDataFactory.grantAdminToRunningUser();
    }

    /** Queue of canned SOAP responses; captures every request body sent. */
    private class SoapMock implements HttpCalloutMock {
        List<String> responses = new List<String>();
        List<String> requestBodies = new List<String>();
        public HttpResponse respond(HttpRequest req) {
            requestBodies.add(req.getBody());
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody(responses.remove(0));
            return res;
        }
    }

    private static final String MD_NS = 'http://soap.sforce.com/2006/04/metadata';

    private static String readResponse() {
        return '<?xml version="1.0" encoding="UTF-8"?>'
            + '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"'
            + ' xmlns="' + MD_NS + '" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
            + '<soapenv:Body><readMetadataResponse><result>'
            + '<records xsi:type="DataCategoryGroup">'
            + '<fullName>Help_Topics</fullName><active>true</active>'
            + '<dataCategory>'
            +   '<dataCategory>'
            +     '<dataCategory><label>The Basics</label><name>The_Basics</name></dataCategory>'
            +     '<label>Getting Started</label><name>Getting_Started</name>'
            +   '</dataCategory>'
            +   '<dataCategory><label>Cases and Tasks</label><name>Cases_and_Tasks</name></dataCategory>'
            +   '<label>All</label><name>All</name>'
            + '</dataCategory>'
            + '<description>Topic taxonomy &amp; more</description><label>Help Topics</label>'
            + '<objectUsage><object>KnowledgeArticleVersion</object></objectUsage>'
            + '</records></result></readMetadataResponse></soapenv:Body></soapenv:Envelope>';
    }

    private static String updateResponse(Boolean success, String message) {
        return '<?xml version="1.0" encoding="UTF-8"?>'
            + '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"'
            + ' xmlns="' + MD_NS + '">'
            + '<soapenv:Body><updateMetadataResponse><result>'
            + '<fullName>Help_Topics</fullName>'
            + (success ? '' : '<errors><message>' + message + '</message><statusCode>INVALID</statusCode></errors>')
            + '<success>' + success + '</success>'
            + '</result></updateMetadataResponse></soapenv:Body></soapenv:Envelope>';
    }

    private static SoapMock arm(List<String> responses) {
        SoapMock mock = new SoapMock();
        mock.responses.addAll(responses);
        Test.setMock(HttpCalloutMock.class, mock);
        return mock;
    }

    private static String nameTag(String name) {
        return '<met:name>' + name + '</met:name>';
    }

    @IsTest
    static void treeParsesLabelsNamesAndNesting() {
        arm(new List<String>{ readResponse() });
        Test.startTest();
        HelpTopicAdminController.TopicTreeDTO dto = HelpTopicAdminController.getTopicTree();
        Test.stopTest();

        Assert.areEqual(2, dto.topics.size(), 'Root children only (All itself is hidden).');
        Assert.areEqual('Getting_Started', dto.topics[0].name);
        Assert.areEqual('Getting Started', dto.topics[0].label);
        Assert.areEqual(1, dto.topics[0].children.size());
        Assert.areEqual('The_Basics', dto.topics[0].children[0].name);
        Assert.isNotNull(dto.editable, 'Editable flag is populated.');
    }

    @IsTest
    static void addTopicAppendsWithGeneratedUniqueName() {
        SoapMock mock = arm(new List<String>{ readResponse(), updateResponse(true, null) });
        Test.startTest();
        HelpTopicAdminController.addTopic(null, '  Billing & Fees!  ');
        Test.stopTest();

        String sent = mock.requestBodies[1];
        // Children serialize before label/name (schema sequence) and the whole
        // group round-trips: description, group label, objectUsage.
        Assert.isTrue(sent.contains('<met:label>Billing &amp; Fees!</met:label><met:name>Billing_Fees</met:name>'),
            'New topic serialized with sanitized API name: ' + sent);
        Assert.isTrue(sent.contains('<met:description>Topic taxonomy &amp; more</met:description>'),
            'Description round-trips.');
        Assert.isTrue(sent.contains('<met:objectUsage><met:object>KnowledgeArticleVersion</met:object></met:objectUsage>'),
            'Object usage round-trips.');
        Assert.isTrue(sent.indexOf('<met:name>Billing_Fees</met:name>') < sent.indexOf('<met:name>All</met:name>'),
            'New topic nests inside the All root (children before the root name).');
    }

    @IsTest
    static void addSubtopicNestsUnderParent() {
        SoapMock mock = arm(new List<String>{ readResponse(), updateResponse(true, null) });
        Test.startTest();
        HelpTopicAdminController.addTopic('Getting_Started', 'Shortcuts');
        Test.stopTest();

        String sent = mock.requestBodies[1];
        Assert.isTrue(sent.indexOf('<met:name>Shortcuts</met:name>')
            < sent.indexOf('<met:name>Getting_Started</met:name>'),
            'Subtopic serializes inside its parent: ' + sent);
    }

    @IsTest
    static void renameChangesLabelOnly() {
        SoapMock mock = arm(new List<String>{ readResponse(), updateResponse(true, null) });
        Test.startTest();
        HelpTopicAdminController.renameTopic('The_Basics', 'Basics 101');
        Test.stopTest();

        String sent = mock.requestBodies[1];
        Assert.isTrue(sent.contains('<met:label>Basics 101</met:label><met:name>The_Basics</met:name>'),
            'Label changed, API name untouched: ' + sent);
    }

    @IsTest
    static void reorderRewritesSequenceAndRejectsStaleLists() {
        SoapMock mock = arm(new List<String>{ readResponse(), updateResponse(true, null), readResponse() });
        Test.startTest();
        HelpTopicAdminController.reorderTopics(null,
            JSON.serialize(new List<String>{ 'Cases_and_Tasks', 'Getting_Started' }));

        String sent = mock.requestBodies[1];
        Assert.isTrue(sent.indexOf('<met:name>Cases_and_Tasks</met:name>')
            < sent.indexOf('<met:name>Getting_Started</met:name>'),
            'Children serialize in the new order: ' + sent);

        try {
            HelpTopicAdminController.reorderTopics(null,
                JSON.serialize(new List<String>{ 'Cases_and_Tasks' }));
            Assert.fail('Stale/partial order must be rejected');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('refresh'), e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void serverRejectionSurfacesMessage() {
        arm(new List<String>{ readResponse(), updateResponse(false, 'Not allowed today') });
        Test.startTest();
        try {
            HelpTopicAdminController.addTopic(null, 'Doomed');
            Assert.fail('Server rejection must surface');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Not allowed today'), e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void blankLabelAndMissingParentRejected() {
        try {
            HelpTopicAdminController.addTopic(null, '   ');
            Assert.fail('Blank label must be rejected');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('label'), e.getMessage());
        }

        arm(new List<String>{ readResponse() });
        Test.startTest();
        try {
            HelpTopicAdminController.addTopic('Gone_Topic', 'Child');
            Assert.fail('Unknown parent must be rejected');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('no longer exists'), e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void uniqueNameSanitizesAndDeduplicates() {
        Set<String> taken = new Set<String>{ 'Billing', 'Billing_2' };
        Assert.areEqual('Billing_3', HelpTopicAdminController.uniqueName('Billing', taken));
        Assert.areEqual('T401k_Plans', HelpTopicAdminController.uniqueName('401k Plans!', new Set<String>()));
        Assert.areEqual('Topic', HelpTopicAdminController.uniqueName('!!!', new Set<String>()));
        String longLabel = 'A'.repeat(60);
        Assert.isTrue(HelpTopicAdminController.uniqueName(longLabel, new Set<String>()).length() <= 40,
            'Names cap at 40 chars.');
    }

    // ---- Delete ------------------------------------------------------------------

    @IsTest
    static void deleteTopicRemovesNodeAndRoundTripsRest() {
        SoapMock mock = arm(new List<String>{ readResponse(), updateResponse(true, null) });
        Test.startTest();
        HelpTopicAdminController.deleteTopic('Cases_and_Tasks');
        Test.stopTest();

        Assert.areEqual(2, mock.requestBodies.size(), 'One read, one update.');
        String sent = mock.requestBodies[1];
        Assert.isTrue(sent.contains('updateMetadata'), 'Delete is an update without the node.');
        Assert.isFalse(sent.contains(nameTag('Cases_and_Tasks')), 'Deleted topic is gone: ' + sent);
        Assert.isTrue(sent.contains(nameTag('Getting_Started')), 'Sibling survives.');
        Assert.isTrue(sent.contains(nameTag('The_Basics')), 'Sibling subtree survives.');
        Assert.isTrue(sent.contains(nameTag('All')), 'Root survives.');
        Assert.isTrue(sent.contains('<met:description>Topic taxonomy &amp; more</met:description>'),
            'Description round-trips.');
        Assert.isTrue(sent.contains('<met:objectUsage><met:object>KnowledgeArticleVersion</met:object></met:objectUsage>'),
            'Object usage round-trips.');
    }

    @IsTest
    static void deleteTopicCascadesEmptySubtree() {
        SoapMock mock = arm(new List<String>{ readResponse(), readResponse(), updateResponse(true, null) });
        Test.startTest();
        HelpTopicAdminController.TopicDeleteImpactDTO impact =
            HelpTopicAdminController.getTopicDeleteImpact('Getting_Started');
        Assert.areEqual('Getting Started', impact.label);
        Assert.areEqual(1, impact.subtopicCount, 'The Basics goes with its parent.');
        Assert.areEqual(0, impact.articleCount, 'Nothing filed in this org fixture.');

        HelpTopicAdminController.deleteTopic('Getting_Started');
        Test.stopTest();

        String sent = mock.requestBodies[2];
        Assert.isFalse(sent.contains(nameTag('Getting_Started')), 'Parent removed: ' + sent);
        Assert.isFalse(sent.contains(nameTag('The_Basics')), 'Empty subtopic removed with it.');
        Assert.isTrue(sent.contains(nameTag('Cases_and_Tasks')), 'Sibling survives.');
    }

    @IsTest
    static void deleteSubtopicLeavesParent() {
        SoapMock mock = arm(new List<String>{ readResponse(), updateResponse(true, null) });
        Test.startTest();
        HelpTopicAdminController.deleteTopic('The_Basics');
        Test.stopTest();

        String sent = mock.requestBodies[1];
        Assert.isFalse(sent.contains(nameTag('The_Basics')), 'Subtopic removed: ' + sent);
        Assert.isTrue(sent.contains('<met:label>Getting Started</met:label>' + nameTag('Getting_Started')),
            'Parent keeps its label and name.');
    }

    /**
     * Filing an article under a fixture topic needs that category to exist in
     * the org — The_Basics ships in Help_Topics in every org this deploys to.
     * Creating and filing the draft needs the Knowledge User license on the
     * running user (a sandbox where the deployer lacks the seat cannot
     * exercise this path; prod deployers hold it), so the test proves the
     * guard only when it can actually plant a filing.
     */
    @IsTest
    static void deleteTopicBlockedByFiledArticle() {
        Boolean licensed = [
            SELECT UserPermissionsKnowledgeUser FROM User WHERE Id = :UserInfo.getUserId()
        ].UserPermissionsKnowledgeUser;
        if (!licensed) {
            System.debug('Skipped: running user has no Knowledge User license.');
            return;
        }
        Knowledge__kav draft = new Knowledge__kav(
            Title = 'Filed Under Basics', UrlName = 'filed-under-basics-' + System.currentTimeMillis(),
            Summary = 'Blocks the delete');
        insert draft;
        insert new Knowledge__DataCategorySelection(
            ParentId = draft.Id, DataCategoryGroupName = 'Help_Topics', DataCategoryName = 'The_Basics');

        SoapMock mock = arm(new List<String>{ readResponse(), readResponse() });
        Test.startTest();
        Assert.areEqual(1,
            HelpTopicAdminController.getTopicDeleteImpact('Getting_Started').articleCount,
            'An article filed under a subtopic counts against the parent.');
        try {
            HelpTopicAdminController.deleteTopic('The_Basics');
            Assert.fail('A topic with filed articles must not delete');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('filed under'), e.getMessage());
        }
        Test.stopTest();

        for (String body : mock.requestBodies) {
            Assert.isFalse(body.contains('updateMetadata'), 'No write was attempted.');
        }
    }

    @IsTest
    static void deleteTopicScanLimitFailsClosed() {
        HelpTopicAdminController.selectionScanLimit = 0;
        arm(new List<String>{ readResponse() });
        Test.startTest();
        try {
            HelpTopicAdminController.deleteTopic('Cases_and_Tasks');
            Assert.fail('Past the scan limit the delete must refuse');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Setup'), e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void deleteTopicUnknownOrInvalidNameRejected() {
        SoapMock mock = arm(new List<String>{ readResponse() });
        Test.startTest();
        for (String bad : new List<String>{ null, '  ', 'bad name!', 'x/y' }) {
            try {
                HelpTopicAdminController.deleteTopic(bad);
                Assert.fail('Invalid name must be rejected: ' + bad);
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('Invalid'), e.getMessage());
            }
        }
        Assert.areEqual(0, mock.requestBodies.size(), 'Invalid names never reach the Metadata API.');

        try {
            HelpTopicAdminController.deleteTopic('Gone_Topic');
            Assert.fail('Unknown topic must be rejected');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('no longer exists'), e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void deleteTopicServerRejectionSurfaces() {
        arm(new List<String>{ readResponse(), updateResponse(false, 'Category in use') });
        Test.startTest();
        try {
            HelpTopicAdminController.deleteTopic('Cases_and_Tasks');
            Assert.fail('Server rejection must surface');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Category in use'), e.getMessage());
        }
        Test.stopTest();
    }
}