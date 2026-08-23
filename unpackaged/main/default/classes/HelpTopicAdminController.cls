/**
 * HelpTopicAdminController
 *
 * Admin Console management for the Help_Topics Knowledge data category group —
 * SAFE operations only: add topic/subtopic, rename display labels, reorder.
 * Deleting or renaming API names is deliberately NOT offered: article
 * assignments (Knowledge__DataCategorySelection) and help-guide category
 * targets reference categories by name string, so those operations silently
 * orphan content. They stay in Setup → Data Category Setup.
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

    public class TopicTreeDTO {
        @AuraEnabled public Boolean editable;
        @AuraEnabled public List<HelpTopicMetadataService.Category> topics;
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

    private static Set<String> collectNames(HelpTopicMetadataService.Category node) {
        Set<String> names = new Set<String>{ node.name };
        for (HelpTopicMetadataService.Category child : node.children) {
            names.addAll(collectNames(child));
        }
        return names;
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