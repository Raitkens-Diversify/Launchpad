/**
 * HelpTopicAdminController
 *
 * Admin Console management for the Help_Topics Knowledge data category group,
 * any depth up to CategoryTreeService.helpTopicMaxDepth(): add a topic under
 * any node, rename display labels, reorder siblings, move a subtree to another
 * parent, and delete. Delete is guarded — article assignments
 * (Knowledge__DataCategorySelection) reference categories by name string and
 * would be silently orphaned — and never cascades: either the subtopics move
 * up to the deleted topic's parent ("reparent") or the topic must already be
 * empty ("block"). Renaming an API name is still not offered and stays in
 * Setup → Data Category Setup.
 *
 * Writes go through HelpTopicMetadataService (SOAP Metadata API — see that
 * class for why Metadata.Operations can't do this). Every write re-reads the
 * live group first so concurrent Setup edits are never clobbered from a stale
 * snapshot; tree rules (cycles, depth counting the moved subtree) are checked
 * on that snapshot through CategoryTreeService, the same rules the resource
 * side and c/treeUtil apply. Gate mirrors SynonymAdminController: Modify Metadata.
 */
public with sharing class HelpTopicAdminController {

    private static final String GROUP_NAME = 'Help_Topics';
    private static final Integer NAME_MAX = 40;
    public static final String MODE_BLOCK = 'block';
    public static final String MODE_REPARENT = 'reparent';
    // Category API names are alphanumerics/underscores (see uniqueName); anything
    // else is rejected before a callout is spent on it.
    private static final Pattern NAME_PATTERN = Pattern.compile('^[A-Za-z0-9_]{1,40}$');
    // DataCategoryGroupName/DataCategoryName are not filterable in SOQL, so the
    // delete guard scans selections and filters in Apex. Fail closed past this.
    @TestVisible private static Integer selectionScanLimit = 10000;

    /** The admin tree: CategoryTreeService nodes (id = API name) + the limit. */
    public class TopicTreeDTO {
        @AuraEnabled public Boolean editable;
        @AuraEnabled public Integer maxDepth;
        @AuraEnabled public List<CategoryTreeService.TreeNode> roots;
    }

    /** Pre-flight for the delete dialog: what blocks, and where children would go. */
    public class TopicDeleteImpactDTO {
        @AuraEnabled public String label;
        @AuraEnabled public String parentName;    // null = top level: children would become topics
        @AuraEnabled public String parentLabel;
        @AuraEnabled public Integer childCount;       // direct subtopics
        @AuraEnabled public Integer descendantCount;  // whole subtree below
        @AuraEnabled public Integer articleCount;     // versions filed anywhere in the subtree; blocks "block"
        @AuraEnabled public Integer ownArticleCount;  // versions filed on the topic itself; blocks "reparent"
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
            CategoryTreeService.Tree tree = HelpTopicTreeProvider.fromSnapshot(readGroup().root.children, true);
            dto.maxDepth = tree.maxDepth;
            dto.roots = tree.roots;
        } catch (Exception e) {
            throw auraError(e.getMessage());
        }
        return dto;
    }

    /** parentName null/blank = new top-level topic; else a child of that node (any depth). */
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
                parent = findChild(snap.root, parentName.trim());
                if (parent == null) {
                    throw auraError('Topic "' + parentName + '" no longer exists — refresh.');
                }
                CategoryTreeService.Tree tree = HelpTopicTreeProvider.fromSnapshot(snap.root.children, false);
                if (tree.get(parent.name).depth + 1 > tree.maxDepth) {
                    throw auraError(CategoryTreeService.depthMessage(tree.maxDepth));
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
            HelpTopicMetadataService.Category target = findChild(snap.root, name == null ? '' : name.trim());
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
        List<String> orderedNames = parseNames(orderedNamesJson);
        try {
            HelpTopicMetadataService.GroupSnapshot snap = readGroup();
            HelpTopicMetadataService.Category parent = String.isBlank(parentName)
                ? snap.root
                : findChild(snap.root, parentName.trim());
            if (parent == null) {
                throw auraError('Topic "' + parentName + '" no longer exists — refresh.');
            }
            parent.children = inOrder(parent.children, orderedNames);
            HelpTopicMetadataService.updateGroup(snap);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw auraError(e.getMessage());
        }
    }

    /**
     * Drag-and-drop move: `name` (with its whole subtree) becomes a child of
     * newParentName (null/blank = top level), and orderedNamesJson lists EVERY
     * sibling under the new parent including the moved one, in final order.
     * Refused when the target is the node itself or inside its subtree, or when
     * the subtree's height would push past the depth limit.
     */
    @AuraEnabled
    public static void moveTopic(String name, String newParentName, String orderedNamesJson) {
        assertTopicAdmin();
        requireValidName(name);
        List<String> orderedNames = parseNames(orderedNamesJson);
        String targetName = String.isBlank(newParentName) ? null : newParentName.trim();
        try {
            HelpTopicMetadataService.GroupSnapshot snap = readGroup();
            CategoryTreeService.Tree tree = HelpTopicTreeProvider.fromSnapshot(snap.root.children, false);
            String problem = tree.validateMove(name, targetName);
            if (problem != null) {
                throw auraError(problem);
            }
            HelpTopicMetadataService.Category oldParent = findParentOf(snap.root, name);
            HelpTopicMetadataService.Category node = findChild(snap.root, name);
            HelpTopicMetadataService.Category target = targetName == null
                ? snap.root : findChild(snap.root, targetName);
            if (oldParent == null || node == null || target == null) {
                throw auraError('Topic "' + name + '" no longer exists — refresh.');
            }
            // Detach, then rebuild the target's children in the submitted order.
            for (Integer i = oldParent.children.size() - 1; i >= 0; i--) {
                if (oldParent.children[i].name == name) {
                    oldParent.children.remove(i);
                }
            }
            List<HelpTopicMetadataService.Category> pool =
                new List<HelpTopicMetadataService.Category>(target.children);
            pool.add(node);
            target.children = inOrder(pool, orderedNames);
            HelpTopicMetadataService.updateGroup(snap);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw auraError(e.getMessage());
        }
    }

    // ---- Delete ------------------------------------------------------------------

    /**
     * What deleting `name` would touch: article versions filed in the subtree
     * (any version — the "block" guard) and on the node itself (the
     * "reparent" guard), plus how many subtopics would move up and to where.
     * The UI shows this before asking for the choice; deleteTopic re-checks.
     */
    @AuraEnabled
    public static TopicDeleteImpactDTO getTopicDeleteImpact(String name) {
        assertTopicAdmin();
        requireValidName(name);
        try {
            HelpTopicMetadataService.GroupSnapshot snap = readGroup();
            return impactOf(snap, name);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw auraError(e.getMessage());
        }
    }

    /**
     * Removes the topic by writing the group back without that node — the
     * Metadata API has no per-category delete. mode 'reparent' splices its
     * subtopics into its parent at the same position (nothing may be filed on
     * the node itself); mode 'block' (default) needs the whole subtree empty
     * and childless. Never a cascade.
     */
    @AuraEnabled
    public static void deleteTopic(String name, String mode) {
        assertTopicAdmin();
        requireValidName(name);
        Boolean reparent = mode == MODE_REPARENT;
        try {
            HelpTopicMetadataService.GroupSnapshot snap = readGroup();
            TopicDeleteImpactDTO impact = impactOf(snap, name);
            HelpTopicMetadataService.Category parent = findParentOf(snap.root, name);
            Integer index = -1;
            for (Integer i = 0; i < parent.children.size(); i++) {
                if (parent.children[i].name == name) {
                    index = i;
                }
            }
            HelpTopicMetadataService.Category target = parent.children[index];
            if (reparent) {
                if (impact.ownArticleCount > 0) {
                    throw auraError('Can\'t delete this topic — ' + articleVersions(impact.ownArticleCount)
                        + ' filed on it directly. Move those articles to another topic first.');
                }
                parent.children.remove(index);
                for (Integer i = 0; i < target.children.size(); i++) {
                    parent.children.add(index + i, target.children[i]);
                }
            } else {
                if (impact.childCount > 0) {
                    throw auraError('Can\'t delete this topic — it has ' + impact.childCount
                        + (impact.childCount == 1 ? ' subtopic' : ' subtopics')
                        + '. Move them up or move them elsewhere first.');
                }
                if (impact.articleCount > 0) {
                    throw auraError('Can\'t delete this topic — ' + articleVersions(impact.articleCount)
                        + ' filed under it (drafts and archived versions included). '
                        + 'Move those articles to another topic first.');
                }
                parent.children.remove(index);
            }
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

    private static TopicDeleteImpactDTO impactOf(HelpTopicMetadataService.GroupSnapshot snap, String name) {
        HelpTopicMetadataService.Category target = findChild(snap.root, name);
        HelpTopicMetadataService.Category parent = findParentOf(snap.root, name);
        if (target == null || parent == null) {
            throw auraError('Topic "' + name + '" no longer exists — refresh.');
        }
        TopicDeleteImpactDTO dto = new TopicDeleteImpactDTO();
        dto.label = target.label;
        dto.parentName = parent === snap.root ? null : parent.name;
        dto.parentLabel = parent === snap.root ? null : parent.label;
        dto.childCount = target.children.size();
        dto.descendantCount = collectNames(target).size() - 1;
        Map<String, Integer> filed = countArticlesFiledUnder(collectNames(target));
        dto.articleCount = filed.get('subtree');
        dto.ownArticleCount = filed.containsKey(name) ? filed.get(name) : 0;
        return dto;
    }

    private static String articleVersions(Integer n) {
        return n + ' article version' + (n == 1 ? ' is' : 's are');
    }

    private static List<String> parseNames(String orderedNamesJson) {
        try {
            return String.isBlank(orderedNamesJson)
                ? null
                : (List<String>) JSON.deserialize(orderedNamesJson, List<String>.class);
        } catch (Exception e) {
            throw auraError('Could not read the new order — refresh and try again.');
        }
    }

    /** The pool in the submitted order; the two sets must match exactly. */
    private static List<HelpTopicMetadataService.Category> inOrder(
            List<HelpTopicMetadataService.Category> pool, List<String> orderedNames) {
        Map<String, HelpTopicMetadataService.Category> byName =
            new Map<String, HelpTopicMetadataService.Category>();
        for (HelpTopicMetadataService.Category c : pool) {
            byName.put(c.name, c);
        }
        if (orderedNames == null
            || orderedNames.size() != pool.size()
            || !byName.keySet().equals(new Set<String>(orderedNames))) {
            throw auraError('The topic list changed while you were editing — refresh.');
        }
        List<HelpTopicMetadataService.Category> reordered =
            new List<HelpTopicMetadataService.Category>();
        for (String n : orderedNames) {
            reordered.add(byName.get(n));
        }
        return reordered;
    }

    /** Search the whole subtree (iterative — depth is data-controlled). */
    private static HelpTopicMetadataService.Category findChild(
            HelpTopicMetadataService.Category node, String name) {
        List<HelpTopicMetadataService.Category> stack =
            new List<HelpTopicMetadataService.Category>(node.children);
        while (!stack.isEmpty()) {
            HelpTopicMetadataService.Category c = stack.remove(stack.size() - 1);
            if (c.name == name) {
                return c;
            }
            stack.addAll(c.children);
        }
        return null;
    }

    /** The node whose direct children contain `name`, anywhere in the tree. */
    private static HelpTopicMetadataService.Category findParentOf(
            HelpTopicMetadataService.Category node, String name) {
        List<HelpTopicMetadataService.Category> stack =
            new List<HelpTopicMetadataService.Category>{ node };
        while (!stack.isEmpty()) {
            HelpTopicMetadataService.Category c = stack.remove(stack.size() - 1);
            for (HelpTopicMetadataService.Category child : c.children) {
                if (child.name == name) {
                    return c;
                }
            }
            stack.addAll(c.children);
        }
        return null;
    }

    private static Set<String> collectNames(HelpTopicMetadataService.Category node) {
        Set<String> names = new Set<String>();
        List<HelpTopicMetadataService.Category> stack =
            new List<HelpTopicMetadataService.Category>{ node };
        while (!stack.isEmpty()) {
            HelpTopicMetadataService.Category c = stack.remove(stack.size() - 1);
            names.add(c.name);
            stack.addAll(c.children);
        }
        return names;
    }

    /**
     * Distinct article versions (draft, online or archived) filed under each of
     * `names` in the Help_Topics group, plus the distinct total under key
     * 'subtree'. Neither selection column is filterable, so scan and filter
     * here (ArticleAdminController does the same per article). Deliberately
     * counts selection parents rather than resolving them through
     * Knowledge__kav: draft versions are invisible to a user without the
     * Knowledge User license, and a guard that quietly saw fewer filings
     * would fail open.
     */
    private static Map<String, Integer> countArticlesFiledUnder(Set<String> names) {
        Map<String, Set<Id>> byName = new Map<String, Set<Id>>();
        Set<Id> subtree = new Set<Id>();
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
                subtree.add(sel.ParentId);
                if (!byName.containsKey(sel.DataCategoryName)) {
                    byName.put(sel.DataCategoryName, new Set<Id>());
                }
                byName.get(sel.DataCategoryName).add(sel.ParentId);
            }
        }
        Map<String, Integer> counts = new Map<String, Integer>{ 'subtree' => subtree.size() };
        for (String n : byName.keySet()) {
            counts.put(n, byName.get(n).size());
        }
        return counts;
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