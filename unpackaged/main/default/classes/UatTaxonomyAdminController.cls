/**
 * UatTaxonomyAdminController
 *
 * Apex behind the Admin Console's UAT Taxonomy section (adminUatTaxonomy):
 * the three-level System -> Module Group -> Module browser with create/edit
 * per level, plus delete per level (2026-08-05, superseding the 03-doc
 * deferred decision): a node deletes only when NO test case lives under it —
 * Test_Case__c.Module__c is a required Restrict lookup, so the preflight
 * turns the raw DELETE_FAILED into a plain-language reason. Empty descendant
 * groups/modules cascade with the master-detail chain.
 *
 * Conventions (mirrors ResourceAdminController / ArticleAdminController):
 *  - `with sharing`, describe-based CRUD asserts, stripInaccessible before DML,
 *    AuraHandledException with actionable messages.
 *  - Structured write payloads cross the LWC boundary as a JSON string
 *    (custom-Apex-type @AuraEnabled params arrive null/blank in this org).
 *  - Reads are NOT cacheable: the section refetches after every save.
 */
public with sharing class UatTaxonomyAdminController {

    // ---- DTOs ----------------------------------------------------------------

    public class ModuleDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String description;
    }

    public class GroupDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String description;
        @AuraEnabled public List<ModuleDTO> modules = new List<ModuleDTO>();
    }

    public class SystemDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String code;
        @AuraEnabled public String description;
        @AuraEnabled public List<GroupDTO> groups = new List<GroupDTO>();
    }

    /** Create/edit payload for any of the three levels. */
    public class NodeInput {
        public Id id;           // null = create
        public String name;
        public String code;     // systems only
        public String description;
        public Id parentId;     // group: owning system; module: owning group
    }

    // ---- Reads ---------------------------------------------------------------

    /** The full three-level tree in one payload; columns filter client-side. */
    @AuraEnabled
    public static List<SystemDTO> getTaxonomy() {
        assertTaxonomyReadable();

        Map<Id, SystemDTO> systemsById = new Map<Id, SystemDTO>();
        List<SystemDTO> ordered = new List<SystemDTO>();
        for (System__c s : [
            SELECT Id, Name, System_Code__c, Description__c
            FROM System__c
            ORDER BY Name
        ]) {
            SystemDTO dto = new SystemDTO();
            dto.id = s.Id;
            dto.name = s.Name;
            dto.code = s.System_Code__c;
            dto.description = s.Description__c;
            systemsById.put(s.Id, dto);
            ordered.add(dto);
        }

        Map<Id, GroupDTO> groupsById = new Map<Id, GroupDTO>();
        for (Module_Group__c g : [
            SELECT Id, Name, Description__c, System__c
            FROM Module_Group__c
            ORDER BY Name
        ]) {
            GroupDTO dto = new GroupDTO();
            dto.id = g.Id;
            dto.name = g.Name;
            dto.description = g.Description__c;
            groupsById.put(g.Id, dto);
            SystemDTO parent = systemsById.get(g.System__c);
            if (parent != null) {
                parent.groups.add(dto);
            }
        }

        for (Module__c m : [
            SELECT Id, Name, Description__c, Module_Group__c
            FROM Module__c
            ORDER BY Name
        ]) {
            ModuleDTO dto = new ModuleDTO();
            dto.id = m.Id;
            dto.name = m.Name;
            dto.description = m.Description__c;
            GroupDTO parent = groupsById.get(m.Module_Group__c);
            if (parent != null) {
                parent.modules.add(dto);
            }
        }
        return ordered;
    }

    // ---- Writes ---------------------------------------------------------------

    @AuraEnabled
    public static Id saveSystem(String inputJson) {
        assertTaxonomyAdmin();
        NodeInput input = parse(inputJson);
        if (String.isBlank(input.name)) {
            throw auraError('Give the system a name.');
        }
        String code = normalizeCode(input.code);
        if (String.isBlank(code)) {
            throw auraError('Give the system a code — it becomes the first segment of every Case ID under it.');
        }
        System__c record = new System__c(
            Id = input.id,
            Name = input.name.trim(),
            System_Code__c = code,
            Description__c = input.description
        );
        upsertStripped(record);
        return record.Id;
    }

    @AuraEnabled
    public static Id saveModuleGroup(String inputJson) {
        assertTaxonomyAdmin();
        NodeInput input = parse(inputJson);
        if (String.isBlank(input.name)) {
            throw auraError('Give the module group a name.');
        }
        if (input.id == null && input.parentId == null) {
            throw auraError('A module group needs an owning system.');
        }
        Module_Group__c record = new Module_Group__c(
            Id = input.id,
            Name = input.name.trim(),
            Description__c = input.description
        );
        if (input.id == null) {
            record.System__c = input.parentId;
        }
        upsertStripped(record);
        return record.Id;
    }

    @AuraEnabled
    public static Id saveModule(String inputJson) {
        assertTaxonomyAdmin();
        NodeInput input = parse(inputJson);
        if (String.isBlank(input.name)) {
            throw auraError('Give the module a name.');
        }
        if (input.id == null && input.parentId == null) {
            throw auraError('A module needs an owning module group.');
        }
        Module__c record = new Module__c(
            Id = input.id,
            Name = input.name.trim(),
            Description__c = input.description
        );
        if (input.id == null) {
            record.Module_Group__c = input.parentId;
        }
        upsertStripped(record);
        return record.Id;
    }

    // ---- Deletes (2026-08-05) -----------------------------------------------------

    public class TaxonomyDeleteImpactDTO {
        @AuraEnabled public Integer caseCount;    // any > 0 blocks the delete
        @AuraEnabled public Integer groupCount;   // descendant groups (system level)
        @AuraEnabled public Integer moduleCount;  // descendant modules (system/group)
    }

    /** Descendant counts for the delete confirm. level: 'system' | 'group' | 'module'. */
    @AuraEnabled
    public static TaxonomyDeleteImpactDTO getTaxonomyDeleteImpact(String level, Id nodeId) {
        assertTaxonomyReadable();
        TaxonomyDeleteImpactDTO dto = new TaxonomyDeleteImpactDTO();
        dto.groupCount = 0;
        dto.moduleCount = 0;
        if (level == 'system') {
            dto.caseCount = [
                SELECT COUNT() FROM Test_Case__c
                WHERE Module__r.Module_Group__r.System__c = :nodeId
            ];
            dto.groupCount = [SELECT COUNT() FROM Module_Group__c WHERE System__c = :nodeId];
            dto.moduleCount = [
                SELECT COUNT() FROM Module__c WHERE Module_Group__r.System__c = :nodeId
            ];
        } else if (level == 'group') {
            dto.caseCount = [
                SELECT COUNT() FROM Test_Case__c WHERE Module__r.Module_Group__c = :nodeId
            ];
            dto.moduleCount = [SELECT COUNT() FROM Module__c WHERE Module_Group__c = :nodeId];
        } else if (level == 'module') {
            dto.caseCount = [SELECT COUNT() FROM Test_Case__c WHERE Module__c = :nodeId];
        } else {
            throw auraError('Unknown taxonomy level.');
        }
        return dto;
    }

    @AuraEnabled
    public static void deleteSystem(Id systemId) {
        assertTaxonomyAdmin();
        deleteNode('system', Schema.sObjectType.System__c, new System__c(Id = systemId), systemId);
    }

    @AuraEnabled
    public static void deleteModuleGroup(Id groupId) {
        assertTaxonomyAdmin();
        deleteNode('group', Schema.sObjectType.Module_Group__c, new Module_Group__c(Id = groupId), groupId);
    }

    @AuraEnabled
    public static void deleteModule(Id moduleId) {
        assertTaxonomyAdmin();
        deleteNode('module', Schema.sObjectType.Module__c, new Module__c(Id = moduleId), moduleId);
    }

    private static void deleteNode(String level, Schema.DescribeSObjectResult describe,
        SObject record, Id nodeId) {
        if (!describe.isDeletable()) {
            throw auraError('You do not have access to delete taxonomy entries.');
        }
        Integer cases = getTaxonomyDeleteImpact(level, nodeId).caseCount;
        if (cases > 0) {
            throw auraError('Can\'t delete this ' + (level == 'group' ? 'module group' : level)
                + ' — ' + cases + ' test case' + (cases == 1 ? ' lives' : 's live')
                + ' under it. Delete or move those cases first.');
        }
        try {
            delete record;
        } catch (DmlException e) {
            throw auraError('It could not be deleted: ' + e.getDmlMessage(0));
        }
    }

    // ---- Internals -------------------------------------------------------------

    private static NodeInput parse(String inputJson) {
        try {
            NodeInput input = String.isBlank(inputJson)
                ? null
                : (NodeInput) JSON.deserialize(inputJson, NodeInput.class);
            if (input == null) {
                throw auraError('Could not read the form — refresh and try again.');
            }
            return input;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw auraError('Could not read the form — refresh and try again.');
        }
    }

    /** Lowercase, strip everything but a-z and 0-9 — Case ID segment rules. */
    private static String normalizeCode(String code) {
        return code == null ? null : code.toLowerCase().replaceAll('[^a-z0-9]', '');
    }

    private static void upsertStripped(SObject record) {
        SObjectAccessDecision decision = Security.stripInaccessible(
            record.Id == null ? AccessType.CREATABLE : AccessType.UPDATABLE,
            new List<SObject>{ record }
        );
        SObject stripped = decision.getRecords()[0];
        if (record.Id == null) {
            insert stripped;
            record.Id = stripped.Id;
        } else {
            update stripped;
        }
    }

    private static void assertTaxonomyAdmin() {
        if (!Schema.sObjectType.System__c.isCreateable()
            || !Schema.sObjectType.System__c.isUpdateable()) {
            throw auraError('You do not have access to manage the UAT taxonomy.');
        }
    }

    private static void assertTaxonomyReadable() {
        if (!Schema.sObjectType.System__c.isAccessible()
            || !Schema.sObjectType.Module_Group__c.isAccessible()
            || !Schema.sObjectType.Module__c.isAccessible()) {
            throw auraError('You do not have access to the UAT taxonomy.');
        }
    }

    /** AuraHandledException whose message survives into logs and test output. */
    private static AuraHandledException auraError(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}