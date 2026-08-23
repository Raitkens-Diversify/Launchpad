@IsTest
private class HelpTopicAdminControllerTest {

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
}