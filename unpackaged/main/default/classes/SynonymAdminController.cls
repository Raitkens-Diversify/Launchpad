/**
 * SynonymAdminController
 *
 * Admin Console CRUD for Search_Synonym__mdt (help-center search synonyms).
 * Writes deploy custom metadata via the Apex Metadata API — the same pattern as
 * HelpGuideAdminController.publish(), including the injectable deployer seam
 * (enqueueDeployment throws in tests).
 *
 * Notes:
 *  - CMDT records can't be deleted from Apex: "delete" re-emits the record with
 *    Is_Active__c=false; NexSKnowledgeController.synonymRows() skips inactive rows.
 *  - A record deploy REPLACES the record's values, so every emit includes all
 *    fields, not just the changed one.
 *  - Deploys are async and there is no draft record to poll (unlike guides):
 *    the UI polls getSynonyms() until the change is visible, with a timeout
 *    message pointing at Setup → Deployment Status.
 *  - Requires Modify Metadata (granted by Resource_Center_Admin).
 */
public with sharing class SynonymAdminController {

    private static final String CMDT_PREFIX = 'Search_Synonym.';
    private static final Integer TERM_MAX = 80;
    private static final Integer SYNONYMS_MAX = 255;
    private static final Integer DEV_NAME_MAX = 40;

    // ---- Metadata deploy seam (injectable; enqueueDeployment throws in tests) --

    public interface MetadataDeployer {
        Id enqueue(Metadata.DeployContainer container, Metadata.DeployCallback callback);
    }
    public class RealDeployer implements MetadataDeployer {
        public Id enqueue(Metadata.DeployContainer container, Metadata.DeployCallback callback) {
            return Metadata.Operations.enqueueDeployment(container, callback);
        }
    }
    @TestVisible private static MetadataDeployer deployer = new RealDeployer();

    /** Test seam: rows to use instead of the live CMDT table. */
    @TestVisible private static Map<String, Search_Synonym__mdt> testRows;

    public class SynonymDTO {
        @AuraEnabled public String developerName;
        @AuraEnabled public String term;
        @AuraEnabled public String synonyms;
        @AuraEnabled public Boolean bidirectional;
        @AuraEnabled public Boolean active;
    }

    // ---- Reads -----------------------------------------------------------------

    @AuraEnabled
    public static List<SynonymDTO> getSynonyms() {
        assertSynonymAdmin();
        List<String> names = new List<String>(rowMap().keySet());
        names.sort();
        List<SynonymDTO> out = new List<SynonymDTO>();
        for (String name : names) {
            Search_Synonym__mdt row = rowMap().get(name);
            SynonymDTO dto = new SynonymDTO();
            dto.developerName = row.DeveloperName;
            dto.term = row.Term__c;
            dto.synonyms = row.Synonyms__c;
            dto.bidirectional = row.Bidirectional__c == true;
            dto.active = row.Is_Active__c != false;
            out.add(dto);
        }
        return out;
    }

    // ---- Writes (Metadata API deploys) ------------------------------------------

    /**
     * Create or update a synonym group. Pass developerName=null to create (the
     * name is derived from the term). Returns the record DeveloperName the UI
     * polls getSynonyms() for.
     */
    @AuraEnabled
    public static String saveSynonym(String developerName, String term,
            String synonyms, Boolean bidirectional) {
        assertSynonymAdmin();

        String cleanTerm = normalize(term, TERM_MAX, 'Term');
        String cleanSynonyms = normalize(synonyms, SYNONYMS_MAX, 'Synonyms');

        String devName = String.isBlank(developerName)
            ? deriveDeveloperName(cleanTerm)
            : developerName.trim();
        if (String.isNotBlank(developerName) && !rowMap().containsKey(devName)) {
            throw auraError('No synonym named "' + devName + '" exists to update.');
        }

        enqueueRecord(devName, cleanTerm, cleanSynonyms, bidirectional == true, true);
        return devName;
    }

    /** "Delete" (deactivate) or restore a synonym group. */
    @AuraEnabled
    public static String setSynonymActive(String developerName, Boolean active) {
        assertSynonymAdmin();
        Search_Synonym__mdt row = rowMap().get(developerName);
        if (row == null) {
            throw auraError('No synonym named "' + developerName + '" exists.');
        }
        enqueueRecord(row.DeveloperName, row.Term__c, row.Synonyms__c,
            row.Bidirectional__c == true, active == true);
        return row.DeveloperName;
    }

    // ---- Internals ---------------------------------------------------------------

    private static void enqueueRecord(String devName, String term, String synonyms,
            Boolean bidirectional, Boolean active) {
        Metadata.CustomMetadata md = new Metadata.CustomMetadata();
        md.fullName = CMDT_PREFIX + devName;
        md.label = term;
        addValue(md, 'Term__c', term);
        addValue(md, 'Synonyms__c', synonyms);
        addValue(md, 'Bidirectional__c', bidirectional);
        addValue(md, 'Is_Active__c', active);

        Metadata.DeployContainer container = new Metadata.DeployContainer();
        container.addMetadata(md);
        try {
            deployer.enqueue(container, null);
        } catch (Exception e) {
            throw auraError('Could not start the synonym deploy: ' + e.getMessage());
        }
    }

    private static String normalize(String value, Integer max, String fieldLabel) {
        if (String.isBlank(value)) {
            throw auraError(fieldLabel + ' is required.');
        }
        String clean = value.trim().toLowerCase();
        if (clean.length() > max) {
            throw auraError(fieldLabel + ' is too long (max ' + max + ' characters).');
        }
        return clean;
    }

    /** Term → unique CMDT DeveloperName: alphanumeric + single underscores. */
    @TestVisible
    private static String deriveDeveloperName(String term) {
        String base = term.replaceAll('[^a-zA-Z0-9]+', '_')
            .replaceAll('^_+|_+$', '')
            .capitalize();
        if (String.isBlank(base)) {
            throw auraError('Term must contain letters or numbers.');
        }
        if (!base.substring(0, 1).isAlpha()) {
            base = 'S_' + base;
        }
        base = base.abbreviate(DEV_NAME_MAX).removeEnd('_');

        Set<String> taken = new Set<String>();
        for (String key : rowMap().keySet()) {
            taken.add(key.toLowerCase());
        }
        String candidate = base;
        Integer i = 2;
        while (taken.contains(candidate.toLowerCase())) {
            String suffix = '_' + i;
            candidate = base.abbreviate(DEV_NAME_MAX - suffix.length()).removeEnd('_') + suffix;
            i++;
        }
        return candidate;
    }

    private static Map<String, Search_Synonym__mdt> rowMap() {
        if (Test.isRunningTest()) {
            return (testRows == null) ? new Map<String, Search_Synonym__mdt>() : testRows;
        }
        return Search_Synonym__mdt.getAll();
    }

    private static void addValue(Metadata.CustomMetadata md, String field, Object value) {
        Metadata.CustomMetadataValue v = new Metadata.CustomMetadataValue();
        v.field = field;
        v.value = value;
        md.values.add(v);
    }

    /** AuraHandledException whose message survives into logs and test output. */
    private static AuraHandledException auraError(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }

    private static void assertSynonymAdmin() {
        if (!Schema.sObjectType.Search_Synonym__mdt.isAccessible()
            || !AdminAccessService.hasModifyMetadata()) {
            throw auraError(
                'You need synonym admin access (Modify Metadata) to do this.');
        }
    }
}