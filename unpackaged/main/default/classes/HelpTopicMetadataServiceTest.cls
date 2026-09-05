/**
 * HelpTopicMetadataServiceTest
 *
 * Direct tests for the SOAP Metadata API client behind the Help Topics editor.
 * HelpTopicAdminControllerTest already exercises the happy-path read/update
 * round-trip through the controller; this class targets the branches that
 * controller-level tests don't reach: malformed/faulted SOAP responses, the
 * "group not found" / "no root category" guards, and the update-failure
 * default message.
 */
@IsTest
private class HelpTopicMetadataServiceTest {

    private static final String MD_NS = 'http://soap.sforce.com/2006/04/metadata';

    /** Replays one canned HTTP response per callout, capturing the request bodies sent. */
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

    /** Simulates a network-level failure: Http().send() throws before any response exists. */
    private class ThrowingMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            throw new CalloutException('Simulated network failure');
        }
    }

    private static SoapMock arm(String response) {
        SoapMock mock = new SoapMock();
        mock.responses.add(response);
        Test.setMock(HttpCalloutMock.class, mock);
        return mock;
    }

    private static String readResponse() {
        return '<?xml version="1.0" encoding="UTF-8"?>'
            + '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"'
            + ' xmlns="' + MD_NS + '" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
            + '<soapenv:Body><readMetadataResponse><result>'
            + '<records xsi:type="DataCategoryGroup">'
            + '<fullName>Help_Topics</fullName><active>true</active>'
            + '<dataCategory>'
            +   '<dataCategory><label>Getting Started</label><name>Getting_Started</name></dataCategory>'
            +   '<label>All</label><name>All</name>'
            + '</dataCategory>'
            + '<description>Topic taxonomy</description><label>Help Topics</label>'
            + '<objectUsage><object>KnowledgeArticleVersion</object></objectUsage>'
            + '</records></result></readMetadataResponse></soapenv:Body></soapenv:Envelope>';
    }

    // ---- readGroup: happy path (kept direct/minimal; the controller test covers depth) ----

    @IsTest
    static void readGroupParsesRootAndObjectUsage() {
        arm(readResponse());
        Test.startTest();
        HelpTopicMetadataService.GroupSnapshot snap = HelpTopicMetadataService.readGroup('Help_Topics');
        Test.stopTest();

        Assert.areEqual('Help_Topics', snap.fullName);
        Assert.isTrue(snap.active, 'Active flag parsed.');
        Assert.areEqual('Topic taxonomy', snap.description);
        Assert.areEqual('Help Topics', snap.label);
        Assert.areEqual(1, snap.objectUsage.size());
        Assert.areEqual('KnowledgeArticleVersion', snap.objectUsage[0]);
        Assert.areEqual('All', snap.root.name, 'Root category parsed.');
        Assert.areEqual(1, snap.root.children.size());
        Assert.areEqual('Getting_Started', snap.root.children[0].name);
    }

    // ---- readGroup: not-found / structural guards ------------------------------------

    @IsTest
    static void readGroupMissingRecordsThrowsNotFound() {
        String body = '<?xml version="1.0" encoding="UTF-8"?>'
            + '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"'
            + ' xmlns="' + MD_NS + '">'
            + '<soapenv:Body><readMetadataResponse><result>'
            + '</result></readMetadataResponse></soapenv:Body></soapenv:Envelope>';
        arm(body);
        Test.startTest();
        try {
            HelpTopicMetadataService.readGroup('Ghost_Group');
            Assert.fail('Expected a not-found error when records/fullName is missing.');
        } catch (HelpTopicMetadataService.MetadataApiException e) {
            Assert.isTrue(e.getMessage().contains('was not found'), e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void readGroupWithNoRootCategoryThrows() {
        String body = '<?xml version="1.0" encoding="UTF-8"?>'
            + '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"'
            + ' xmlns="' + MD_NS + '">'
            + '<soapenv:Body><readMetadataResponse><result>'
            + '<records>'
            + '<fullName>Help_Topics</fullName><active>true</active>'
            + '</records></result></readMetadataResponse></soapenv:Body></soapenv:Envelope>';
        arm(body);
        Test.startTest();
        try {
            HelpTopicMetadataService.readGroup('Help_Topics');
            Assert.fail('Expected a no-root-category error.');
        } catch (HelpTopicMetadataService.MetadataApiException e) {
            Assert.isTrue(e.getMessage().contains('no root category'), e.getMessage());
        }
        Test.stopTest();
    }

    // ---- updateGroup: failure defaulting + round-trip of a hand-built snapshot -------

    @IsTest
    static void updateGroupSendsFieldsAndHandlesBlankFailureMessage() {
        String failResponse = '<?xml version="1.0" encoding="UTF-8"?>'
            + '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"'
            + ' xmlns="' + MD_NS + '">'
            + '<soapenv:Body><updateMetadataResponse><result>'
            + '<fullName>Help_Topics</fullName>'
            + '<errors><statusCode>UNKNOWN</statusCode></errors>'
            + '<success>false</success>'
            + '</result></updateMetadataResponse></soapenv:Body></soapenv:Envelope>';
        SoapMock mock = arm(failResponse);

        HelpTopicMetadataService.GroupSnapshot snap = new HelpTopicMetadataService.GroupSnapshot();
        snap.fullName = 'Help_Topics';
        snap.active = true;
        snap.label = 'Help Topics';
        // description intentionally blank: exercises the "omit when blank" branch.
        snap.objectUsage = new List<String>{ 'KnowledgeArticleVersion' };
        HelpTopicMetadataService.Category root = new HelpTopicMetadataService.Category();
        root.name = 'All';
        root.label = 'All';
        HelpTopicMetadataService.Category child = new HelpTopicMetadataService.Category();
        child.name = 'Getting_Started';
        child.label = 'Getting Started';
        root.children.add(child);
        snap.root = root;

        Test.startTest();
        try {
            HelpTopicMetadataService.updateGroup(snap);
            Assert.fail('Expected a rejected-update error.');
        } catch (HelpTopicMetadataService.MetadataApiException e) {
            Assert.areEqual('The metadata update was rejected.', e.getMessage(),
                'No error message on the wire falls back to the default.');
        }
        Test.stopTest();

        String sent = mock.requestBodies[0];
        Assert.isTrue(sent.contains('<met:fullName>Help_Topics</met:fullName>'), sent);
        Assert.isTrue(sent.contains('<met:active>true</met:active>'), sent);
        Assert.isTrue(sent.contains('<met:objectUsage><met:object>KnowledgeArticleVersion</met:object></met:objectUsage>'), sent);
        Assert.isFalse(sent.contains('<met:description>'), 'Blank description is omitted entirely.');
        Assert.isTrue(sent.indexOf('<met:name>Getting_Started</met:name>') < sent.indexOf('<met:name>All</met:name>'),
            'Child category serializes before its parent (schema sequence).');
    }

    // ---- SOAP transport failure modes -------------------------------------------------

    @IsTest
    static void soapFaultSurfacesFaultString() {
        String body = '<?xml version="1.0" encoding="UTF-8"?>'
            + '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/">'
            + '<soapenv:Body><soapenv:Fault>'
            + '<faultcode>soapenv:Client</faultcode>'
            + '<faultstring>Session expired or invalid</faultstring>'
            + '</soapenv:Fault></soapenv:Body></soapenv:Envelope>';
        arm(body);
        Test.startTest();
        try {
            HelpTopicMetadataService.readGroup('Help_Topics');
            Assert.fail('Expected the SOAP fault to surface.');
        } catch (HelpTopicMetadataService.MetadataApiException e) {
            Assert.areEqual('Session expired or invalid', e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void malformedXmlBodyThrowsUnexpectedResponse() {
        arm('this is not xml at all');
        Test.startTest();
        try {
            HelpTopicMetadataService.readGroup('Help_Topics');
            Assert.fail('Expected an unexpected-response error for unparsable XML.');
        } catch (HelpTopicMetadataService.MetadataApiException e) {
            Assert.isTrue(e.getMessage().contains('Unexpected Metadata API response'), e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void missingSoapBodyThrowsMalformedResponse() {
        String body = '<?xml version="1.0" encoding="UTF-8"?>'
            + '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/">'
            + '</soapenv:Envelope>';
        arm(body);
        Test.startTest();
        try {
            HelpTopicMetadataService.readGroup('Help_Topics');
            Assert.fail('Expected a malformed-response error when Body is missing.');
        } catch (HelpTopicMetadataService.MetadataApiException e) {
            Assert.areEqual('Malformed SOAP response.', e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void missingExpectedElementThrowsUnexpectedResponse() {
        String body = '<?xml version="1.0" encoding="UTF-8"?>'
            + '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/">'
            + '<soapenv:Body></soapenv:Body></soapenv:Envelope>';
        arm(body);
        Test.startTest();
        try {
            HelpTopicMetadataService.readGroup('Help_Topics');
            Assert.fail('Expected an unexpected-response error when the response element is missing.');
        } catch (HelpTopicMetadataService.MetadataApiException e) {
            Assert.isTrue(e.getMessage().contains('Unexpected Metadata API response'), e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void calloutFailureWrapsAsMetadataApiException() {
        Test.setMock(HttpCalloutMock.class, new ThrowingMock());
        Test.startTest();
        try {
            HelpTopicMetadataService.readGroup('Help_Topics');
            Assert.fail('Expected the callout failure to be wrapped.');
        } catch (HelpTopicMetadataService.MetadataApiException e) {
            Assert.isTrue(e.getMessage().contains('Could not reach the Metadata API'), e.getMessage());
        }
        Test.stopTest();
    }
}