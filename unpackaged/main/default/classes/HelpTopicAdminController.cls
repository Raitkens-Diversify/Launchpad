/**
 * HelpTopicAdminController
 *
 * Admin Console management for the Help_Topics Knowledge data category group:
 * add topic/subtopic, rename display labels, reorder, and delete. Delete is
 * guarded — article assignments (Knowledge__DataCategorySelection) reference
 * categories by name string and would be silently orphaned, so a topic (or
 * any of its subtopics) with ANY article version filed under it (draft,
 * online or archived) cannot be deleted from here; the admin moves those
 * articles first. Empty subtopics are removed with their parent. Renaming an
 * API name is still not offered and stays in Setup → Data Category Setup.
 *
 * Writes go through HelpTopicMetadataService (SOAP Metadata API — see that
 * class for why Metadata.Operations can't do this). Every write re-reads the
 * live group first so concurrent Setup edits are never clobbered from a stale
 * snapshot. Gate mirrors SynonymAdminController: Modify Metadata.
 */
public with sharing class HelpTopicAdminController {

    private static final String GROUP_NAME = 'Help_Topics';
    private static final Integer NAME_MAX = 40;
    private static final Integer MAX_DEPTH = 2; // topics + subtopics (UI convention)
    // Category API names are alphanumerics/underscores (see uniqueName); anything
    // else is rejected before a callout is spent on it.
    private static final Pattern NAME_PATTERN = Pattern.compile('^[A-Za-z0-9_]{1,40}$');
    // DataCategoryGroupName/DataCategoryName are not filterable in SOQL, so the
    // delete guard scans selections and filters in Apex. Fail closed past this.
    @TestVisible private static Integer selectionScanLimit = 10000;

    public class TopicTreeDTO {
        @AuraEnabled public Boolean editable;
        @AuraEnabled public List<HelpTopicMetadataService.Category> topics;
    }

    /** Pre-flight for the delete confirm: what blocks, and what cascades. */
    public class TopicDeleteImpactDTO {
        @AuraEnabled public String label;
        @AuraEnabled public Integer articleCount;   // filed article versions (draft/online/archived); > 0 blocks
        @AuraEnabled public Integer subtopicCount;  // removed with the topic (all empty by then)
    }

    /** Cheap gate check for the UI (no callout — display uses the describe tree). */
    @AuraEnabled(cacheable=true)
    public static Boolean canEditTopics() {
        return AdminAccessService.hasModifyMetadata();
    }

    @AuraEnabled
    public static TopicTreeDTO getTopicTree() {
        TopicTreeDTO dto = new TopicTreeDTO();
        dto.editable = AdminAccessService.hasModifyMetadata();
        try {
            dto.topics = readGroup().root.children;
        } catch (Exception e) {
            throw auraError(e.getMessage());
        }
        return dto;
    }

    /** parentName null/blank = new top-level topic; else a subtopic under it. */
    @AuraEnabled
    public static void addTopic(String parentName, String label) {
        assertTopicAdmin();
        if (String.isBlank(label)) {
            throw auraError('Give the new topic a label.');
        }
        try {
            HelpTopicMetadataService.GroupSnapshot snap = readGroup();
            HelpTopicMetadataService.Category parent = snap.root;
            if (String.isNotBlank(parentName)) {
                // Subtopics only nest under top-level topics (the Help Center
                // renders exactly two levels).
                parent = findChild(snap.root, parentName.trim(), 1);
                if (parent == null) {
                    throw auraError('Topic "' + parentName + '" no longer exists — refresh.');
                }
            }
            HelpTopicMetadataService.Category fresh = new HelpTopicMetadataService.Category();
            fresh.label = label.trim();
            fresh.name = uniqueName(fresh.label, collectNames(snap.root));
            parent.children.add(fresh);
            HelpTopicMetadataService.updateGroup(snap);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw auraError(e.getMessage());
        }
    }

    /** Display-label rename only — the API name (and every assignment) is untouched. */
    @AuraEnabled
    public static void renameTopic(String name, String newLabel) {
        assertTopicAdmin();
        if (String.isBlank(newLabel)) {
            throw auraError('The new label cannot be blank.');
        }
        try {
            HelpTopicMetadataService.GroupSnapshot snap = readGroup();
            HelpTopicMetadataService.Category target =
                findChild(snap.root, name == null ? '' : name.trim(), MAX_DEPTH);
            if (target == null) {
                throw auraError('Topic "' + name + '" no longer exists — refresh.');
            }
            target.label = newLabel.trim();
            HelpTopicMetadataService.updateGroup(snap);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw auraError(e.getMessage());
        }
    }

    /**
     * Reorders the children of parentName (null/blank = top-level topics).
     * orderedNamesJson is a JSON array of the sibling API names — string
     * transport because non-primitive @AuraEnabled params arrive null from
     * LWC in this org.
     */
    @AuraEnabled
    public static void reorderTopics(String parentName, String orderedNamesJson) {
        assertTopicAdmin();
        List<String> orderedNames;
        try {
            orderedNames = String.isBlank(orderedNamesJson)
                ? null
                : (List<String>) JSON.deserialize(orderedNamesJson, List<String>.class);
        } catch (Exception e) {
            throw auraError('Could not read the new order — refresh and try again.');
        }
        try {
            HelpTopicMetadataService.GroupSnapshot snap = readGroup();
            HelpTopicMetadataService.Category parent = String.isBlank(parentName)
                ? snap.root
                : findChild(snap.root, parentName.trim(), 1);
            if (parent == null) {
                throw auraError('Topic "' + parentName + '" no longer exists — refresh.');
            }
            Map<String, HelpTopicMetadataService.Category> byName =
                new Map<String, HelpTopicMetadataService.Category>();
            for (HelpTopicMetadataService.Category c : parent.children) {
                byName.put(c.name, c);
            }
            if (orderedNames == null
                || orderedNames.size() != parent.children.size()
                || !byName.keySet().equals(new Set<String>(orderedNames))) {
                throw auraError('The topic list changed while you were editing — refresh.');
            }
            List<HelpTopicMetadataService.Category> reordered =
                new List<HelpTopicMetadataService.Category>();
            for (String n : orderedNames) {
                reordered.add(byName.get(n));
            }
            parent.children = reordered;
            HelpTopicMetadataService.updateGroup(snap);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw auraError(e.getMessage());
        }
    }

    // ---- Delete ------------------------------------------------------------------

    /**
     * What deleting `name` would touch: distinct articles filed under it or
     * any subtopic (any version — blocks), and how many subtopics go with it.
     * The UI shows this before asking for confirmation; deleteTopic re-checks.
     */
    @AuraEnabled
    public static TopicDeleteImpactDTO getTopicDeleteImpact(String name) {
        assertTopicAdmin();
        requireValidName(name);
        try {
            HelpTopicMetadataService.GroupSnapshot snap = readGroup();
            HelpTopicMetadataService.Category target = findChild(snap.root, name, MAX_DEPTH);
            if (target == null) {
                throw auraError('Topic "' + name + '" no longer exists — refresh.');
            }
            TopicDeleteImpactDTO dto = new TopicDeleteImpactDTO();
            dto.label = target.label;
            dto.subtopicCount = target.children.size();
            dto.articleCount = countArticlesFiledUnder(collectNames(target));
            return dto;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw auraError(e.getMessage());
        }
    }

    /**
     * Removes the topic (and its subtopics) from the group by writing the
     * group back without that node — the Metadata API has no per-category
     * delete. Refused while any article version is filed under the subtree.
     */
    @AuraEnabled
    public static void deleteTopic(String name) {
        assertTopicAdmin();
        requireValidName(name);
        try {
            HelpTopicMetadataService.GroupSnapshot snap = readGroup();
            HelpTopicMetadataService.Category parent = findParentOf(snap.root, name, MAX_DEPTH);
            if (parent == null) {
                throw auraError('Topic "' + name + '" no longer exists — refresh.');
            }
            Integer index = -1;
            for (Integer i = 0; i < parent.children.size(); i++) {
                if (parent.children[i].name == name) {
                    index = i;
                }
            }
            HelpTopicMetadataService.Category target = parent.children[index];
            Integer filed = countArticlesFiledUnder(collectNames(target));
            if (filed > 0) {
                throw auraError('Can\'t delete this topic — ' + filed + ' article version'
                    + (filed == 1 ? ' is' : 's are')
                    + ' filed under it (drafts and archived versions included). '
                    + 'Move those articles to another topic first.');
            }
            parent.children.remove(index);
            HelpTopicMetadataService.updateGroup(snap);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw auraError(e.getMessage());
        }
    }

    // ---- Internals ----------------------------------------------------------------

    private static HelpTopicMetadataService.GroupSnapshot readGroup() {
        return HelpTopicMetadataService.readGroup(GROUP_NAME);
    }

    /** Depth-limited search among descendants (depth 1 = direct children). */
    private static HelpTopicMetadataService.Category findChild(
            HelpTopicMetadataService.Category node, String name, Integer maxDepth) {
        for (HelpTopicMetadataService.Category child : node.children) {
            if (child.name == name) {
                return child;
            }
            if (maxDepth > 1) {
                HelpTopicMetadataService.Category hit = findChild(child, name, maxDepth - 1);
                if (hit != null) {
                    return hit;
                }
            }
        }
        return null;
    }

    /** The node whose direct children contain `name` (same depth rule as findChild). */
    private static HelpTopicMetadataService.Category findParentOf(
            HelpTopicMetadataService.Category node, String name, Integer maxDepth) {
        for (HelpTopicMetadataService.Category child : node.children) {
            if (child.name == name) {
                return node;
            }
            if (maxDepth > 1) {
                HelpTopicMetadataService.Category hit = findParentOf(child, name, maxDepth - 1);
                if (hit != null) {
                    return hit;
                }
            }
        }
        return null;
    }

    private static Set<String> collectNames(HelpTopicMetadataService.Category node) {
        Set<String> names = new Set<String>{ node.name };
        for (HelpTopicMetadataService.Category child : node.children) {
            names.addAll(collectNames(child));
        }
        return names;
    }

    /**
     * Distinct article versions (draft, online or archived) filed under any of
     * `names` in the Help_Topics group. Neither selection column is
     * filterable, so scan and filter here (ArticleAdminController does the
     * same per article). Deliberately counts selection parents rather than
     * resolving them through Knowledge__kav: draft versions are invisible to
     * a user without the Knowledge User license, and a guard that quietly
     * saw fewer filings would fail open.
     */
    private static Integer countArticlesFiledUnder(Set<String> names) {
        Set<Id> versionIds = new Set<Id>();
        List<Knowledge__DataCategorySelection> selections = [
            SELECT ParentId, DataCategoryGroupName, DataCategoryName
            FROM Knowledge__DataCategorySelection
            LIMIT :selectionScanLimit
        ];
        if (selections.size() >= selectionScanLimit) {
            throw auraError('Too many article filings to check safely — delete this topic '
                + 'in Setup → Data Category Setup.');
        }
        for (Knowledge__DataCategorySelection sel : selections) {
            if (sel.DataCategoryGroupName == GROUP_NAME && names.contains(sel.DataCategoryName)) {
                versionIds.add(sel.ParentId);
            }
        }
        return versionIds.size();
    }

    private static void requireValidName(String name) {
        if (String.isBlank(name) || !NAME_PATTERN.matcher(name).matches()) {
            throw auraError('Invalid topic name.');
        }
    }

    /** Label → unique category API name: alphanumerics + single underscores. */
    @TestVisible
    private static String uniqueName(String label, Set<String> taken) {
        String base = label.trim()
            .replaceAll('[^a-zA-Z0-9]+', '_')
            .replaceAll('_+', '_')
            .replaceAll('^_|_$', '');
        if (String.isBlank(base)) {
            base = 'Topic';
        }
        if (base.substring(0, 1).isNumeric()) {
            base = 'T' + base;
        }
        if (base.length() > NAME_MAX) {
            base = base.substring(0, NAME_MAX).replaceAll('_$', '');
        }
        String candidate = base;
        Integer suffix = 2;
        while (taken.contains(candidate)) {
            String tail = '_' + suffix;
            candidate = (base.length() + tail.length() > NAME_MAX
                ? base.substring(0, NAME_MAX - tail.length()) : base) + tail;
            suffix++;
        }
        return candidate;
    }

    private static void assertTopicAdmin() {
        if (!AdminAccessService.hasModifyMetadata()) {
            throw auraError('You need Modify Metadata access to edit help topics.');
        }
    }

    /** AuraHandledException whose message survives into logs and test output. */
    private static AuraHandledException auraError(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}