/**
 * HelpTopicMetadataService
 *
 * Minimal SOAP Metadata API client for exactly one metadata type: the
 * Help_Topics DataCategoryGroup. Metadata.Operations (the CMDT publish channel)
 * cannot deploy DataCategoryGroup, so the console's Help Topic editor
 * round-trips the whole group through readMetadata/updateMetadata against this
 * org's own SOAP endpoint.
 *
 * Session: Lightning sessions are not API-enabled, so the API session id is
 * rendered by the ApiSessionBridge Visualforce page and read via getContent().
 * The org's own domain must be listed as a Remote Site (RemoteSiteSelfCosmosdev
 * here; RemoteSiteSelf1 covers production).
 *
 * SOAP element order matters: DataCategory serializes children, then label,
 * then name (schema sequence — verified against a live readMetadata response).
 */
public with sharing class HelpTopicMetadataService {

    private static final String MD_NS = 'http://soap.sforce.com/2006/04/metadata';
    private static final String SOAP_NS = 'http://schemas.xmlsoap.org/soap/envelope/';

    public class MetadataApiException extends Exception {}

    public class Category {
        @AuraEnabled public String name;
        @AuraEnabled public String label;
        @AuraEnabled public List<Category> children = new List<Category>();
    }

    /** Whole-group snapshot so writes round-trip every untouched field. */
    public class GroupSnapshot {
        public String fullName;
        public Boolean active;
        public String description;
        public String label;
        public List<String> objectUsage = new List<String>();
        public Category root; // the 'All' category
    }

    /** Test seams: canned session id + captured request bodies via HttpCalloutMock. */
    @TestVisible private static String sessionIdOverride;

    // ---- Public API ----------------------------------------------------------------

    public static GroupSnapshot readGroup(String groupFullName) {
        String body =
            '<met:readMetadata>'
            + '<met:type>DataCategoryGroup</met:type>'
            + '<met:fullNames>' + esc(groupFullName) + '</met:fullNames>'
            + '</met:readMetadata>';
        Dom.XmlNode result = call(body, 'readMetadataResponse');

        Dom.XmlNode records = result.getChildElement('records', MD_NS);
        if (records == null || records.getChildElement('fullName', MD_NS) == null) {
            throw new MetadataApiException(
                'Data category group "' + groupFullName + '" was not found.');
        }
        GroupSnapshot snap = new GroupSnapshot();
        snap.fullName = childText(records, 'fullName');
        snap.active = childText(records, 'active') == 'true';
        snap.description = childText(records, 'description');
        snap.label = childText(records, 'label');
        Dom.XmlNode usage = records.getChildElement('objectUsage', MD_NS);
        if (usage != null) {
            for (Dom.XmlNode obj : usage.getChildElements()) {
                if (obj.getName() == 'object') {
                    snap.objectUsage.add(obj.getText());
                }
            }
        }
        Dom.XmlNode rootNode = records.getChildElement('dataCategory', MD_NS);
        snap.root = rootNode == null ? null : parseCategory(rootNode);
        if (snap.root == null) {
            throw new MetadataApiException('The category group has no root category.');
        }
        return snap;
    }

    public static void updateGroup(GroupSnapshot snap) {
        List<String> parts = new List<String>();
        parts.add('<met:updateMetadata>');
        parts.add('<met:metadata xsi:type="met:DataCategoryGroup">');
        parts.add('<met:fullName>' + esc(snap.fullName) + '</met:fullName>');
        parts.add('<met:active>' + (snap.active == false ? 'false' : 'true') + '</met:active>');
        writeCategory(snap.root, parts);
        if (String.isNotBlank(snap.description)) {
            parts.add('<met:description>' + esc(snap.description) + '</met:description>');
        }
        parts.add('<met:label>' + esc(snap.label) + '</met:label>');
        for (String obj : snap.objectUsage) {
            parts.add('<met:objectUsage><met:object>' + esc(obj) + '</met:object></met:objectUsage>');
        }
        parts.add('</met:metadata>');
        parts.add('</met:updateMetadata>');

        Dom.XmlNode result = call(String.join(parts, ''), 'updateMetadataResponse');
        if (childText(result, 'success') != 'true') {
            Dom.XmlNode error = result.getChildElement('errors', MD_NS);
            String message = error == null ? null : childText(error, 'message');
            throw new MetadataApiException(
                String.isBlank(message) ? 'The metadata update was rejected.' : message);
        }
    }

    // ---- SOAP plumbing --------------------------------------------------------------

    /** Sends the body, unwraps Envelope/Body/<responseName>/result (fault-aware). */
    private static Dom.XmlNode call(String innerBody, String responseName) {
        String envelope =
            '<?xml version="1.0" encoding="UTF-8"?>'
            + '<soapenv:Envelope xmlns:soapenv="' + SOAP_NS + '"'
            + ' xmlns:met="' + MD_NS + '"'
            + ' xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
            + '<soapenv:Header><met:SessionHeader><met:sessionId>'
            + esc(apiSessionId())
            + '</met:sessionId></met:SessionHeader></soapenv:Header>'
            + '<soapenv:Body>' + innerBody + '</soapenv:Body>'
            + '</soapenv:Envelope>';

        HttpRequest req = new HttpRequest();
        req.setEndpoint(Url.getOrgDomainUrl().toExternalForm() + '/services/Soap/m/62.0');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'text/xml; charset=UTF-8');
        req.setHeader('SOAPAction', '""');
        req.setTimeout(60000);
        req.setBody(envelope);

        HttpResponse res;
        try {
            res = new Http().send(req);
        } catch (Exception e) {
            throw new MetadataApiException(
                'Could not reach the Metadata API — is the org domain a Remote Site? ('
                + e.getMessage() + ')');
        }

        Dom.Document doc = new Dom.Document();
        try {
            doc.load(res.getBody());
        } catch (Exception e) {
            throw new MetadataApiException(
                'Unexpected Metadata API response (HTTP ' + res.getStatusCode() + ').');
        }
        Dom.XmlNode bodyNode = doc.getRootElement().getChildElement('Body', SOAP_NS);
        if (bodyNode == null) {
            throw new MetadataApiException('Malformed SOAP response.');
        }
        Dom.XmlNode fault = bodyNode.getChildElement('Fault', SOAP_NS);
        if (fault != null) {
            Dom.XmlNode faultString = fault.getChildElement('faultstring', null);
            throw new MetadataApiException(
                faultString == null ? 'SOAP fault.' : faultString.getText());
        }
        Dom.XmlNode response = bodyNode.getChildElement(responseName, MD_NS);
        Dom.XmlNode result = response == null
            ? null : response.getChildElement('result', MD_NS);
        if (result == null) {
            throw new MetadataApiException(
                'Unexpected Metadata API response (HTTP ' + res.getStatusCode() + ').');
        }
        return result;
    }

    private static Category parseCategory(Dom.XmlNode node) {
        Category c = new Category();
        for (Dom.XmlNode child : node.getChildElements()) {
            if (child.getName() == 'name') {
                c.name = child.getText();
            } else if (child.getName() == 'label') {
                c.label = child.getText();
            } else if (child.getName() == 'dataCategory') {
                c.children.add(parseCategory(child));
            }
        }
        return c;
    }

    /** Schema sequence: nested dataCategory elements first, then label, then name. */
    private static void writeCategory(Category c, List<String> parts) {
        parts.add('<met:dataCategory>');
        for (Category child : c.children) {
            writeCategory(child, parts);
        }
        parts.add('<met:label>' + esc(c.label) + '</met:label>');
        parts.add('<met:name>' + esc(c.name) + '</met:name>');
        parts.add('</met:dataCategory>');
    }

    private static String apiSessionId() {
        if (sessionIdOverride != null) {
            return sessionIdOverride;
        }
        if (Test.isRunningTest()) {
            return 'TEST_SESSION_ID';
        }
        String sid;
        try {
            sid = Page.ApiSessionBridge.getContent().toString().trim();
        } catch (Exception e) {
            throw new MetadataApiException(
                'Could not obtain an API session (' + e.getMessage()
                + '). Edit topics in Setup → Data Category Setup instead.');
        }
        if (String.isBlank(sid)) {
            throw new MetadataApiException(
                'Could not obtain an API session. Edit topics in Setup → Data Category Setup instead.');
        }
        return sid;
    }

    private static String childText(Dom.XmlNode parent, String name) {
        Dom.XmlNode child = parent.getChildElement(name, MD_NS);
        return child == null ? null : child.getText();
    }

    private static String esc(String value) {
        return value == null ? '' : value.escapeXml();
    }
}