/**
 * HelpGuideController
 *
 * Runtime read API for the config-driven "Get Help" guided-navigation trees.
 * Context-agnostic: backs both the LWR Experience surface and the core
 * Lightning App surface. Modeled on TutorialTourController.
 *
 * The whole tree is returned in one cacheable call; the LWC walks it client-side
 * (start at rootNodeKey, follow each option's targetValue when targetType='node',
 * otherwise treat it as a terminal target). Custom metadata reads need no
 * CRUD/FLS guards — CMDT is readable from Apex without object or field grants.
 */
public with sharing class HelpGuideController {

    private static final String KEY_PATTERN = '^[A-Za-z0-9_]{1,40}$';

    public class GuideDTO {
        @AuraEnabled public String guideKey;
        @AuraEnabled public String label;
        @AuraEnabled public Integer version;
        @AuraEnabled public String rootNodeKey;
        @AuraEnabled public List<NodeDTO> nodes;
    }

    public class NodeDTO {
        @AuraEnabled public String nodeKey;
        @AuraEnabled public String question;
        @AuraEnabled public List<OptionDTO> options;
    }

    public class OptionDTO {
        @AuraEnabled public String label;
        @AuraEnabled public String targetType;  // node | category | article | resource | case
        @AuraEnabled public String targetValue; // next node key, slug, UrlName, or case prefill
    }

    /**
     * The published guide plus every active node and option, or null when no
     * active guide exists for the key (the client stays inert on null).
     */
    @AuraEnabled(cacheable=true)
    public static GuideDTO getGuide(String guideKey) {
        validateKey(guideKey);

        List<Help_Guide__mdt> guides = [
            SELECT MasterLabel, Guide_Key__c, Version__c
            FROM Help_Guide__mdt
            WHERE Guide_Key__c = :guideKey AND Active__c = true
            LIMIT 1
        ];
        if (guides.isEmpty()) {
            return null;
        }
        Help_Guide__mdt g = guides[0];

        GuideDTO dto = new GuideDTO();
        dto.guideKey = g.Guide_Key__c;
        dto.label = g.MasterLabel;
        dto.version = g.Version__c == null ? 1 : Integer.valueOf(g.Version__c);
        dto.nodes = new List<NodeDTO>();

        Map<String, NodeDTO> byKey = new Map<String, NodeDTO>();
        Map<Id, String> keyByRecordId = new Map<Id, String>();
        for (Help_Guide_Node__mdt n : [
            SELECT Id, Node_Key__c, Question__c, Is_Root__c, Order__c
            FROM Help_Guide_Node__mdt
            WHERE Guide__r.Guide_Key__c = :guideKey AND Active__c = true
            ORDER BY Order__c ASC NULLS LAST
        ]) {
            NodeDTO nd = new NodeDTO();
            nd.nodeKey = n.Node_Key__c;
            nd.question = n.Question__c;
            nd.options = new List<OptionDTO>();
            byKey.put(nd.nodeKey, nd);
            keyByRecordId.put(n.Id, nd.nodeKey);
            dto.nodes.add(nd);
            if (n.Is_Root__c == true && dto.rootNodeKey == null) {
                dto.rootNodeKey = n.Node_Key__c;
            }
        }
        if (dto.rootNodeKey == null && !dto.nodes.isEmpty()) {
            dto.rootNodeKey = dto.nodes[0].nodeKey; // fallback: first node by order
        }

        if (!keyByRecordId.isEmpty()) {
            for (Help_Guide_Option__mdt o : [
                SELECT Node__c, Label__c, Target_Type__c, Target_Value__c, Order__c
                FROM Help_Guide_Option__mdt
                WHERE Node__c IN :keyByRecordId.keySet() AND Active__c = true
                ORDER BY Order__c ASC NULLS LAST
            ]) {
                NodeDTO parent = byKey.get(keyByRecordId.get(o.Node__c));
                if (parent == null) {
                    continue;
                }
                OptionDTO od = new OptionDTO();
                od.label = o.Label__c;
                od.targetType = o.Target_Type__c;
                od.targetValue = o.Target_Value__c;
                parent.options.add(od);
            }
        }
        return dto;
    }

    private static void validateKey(String guideKey) {
        if (String.isBlank(guideKey) || !Pattern.matches(KEY_PATTERN, guideKey)) {
            throw new AuraHandledException('Invalid guide key.');
        }
    }
}