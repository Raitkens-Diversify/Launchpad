/**
 * ResourceAdminController
 *
 * Admin Console management API for Resource__c and Resource_Category__c:
 * list/save with server-side slug checks, type-conditional validation, file
 * (ContentDocumentLink) listing/removal so "newest file wins" is explicit, and
 * resource-side Article_Resource__c junction writes (the reverse of
 * ArticleAdminController's article-side writer).
 *
 * Junction integrity: related articles arrive as version-stable KnowledgeArticleIds
 * picked from live search — Article_UrlName__c is resolved server-side, raw Ids
 * are never typed.
 *
 * Conventions: `with sharing`, describe asserts, auraError with real messages,
 * no SOQL in loops.
 */
public with sharing class ResourceAdminController {

    private static final String LANG = 'en_US';
    private static final Integer LIST_LIMIT = 500;
    private static final Integer PICKER_LIMIT = 10;
    // Client-side mirror: lwc/rcConstants FILE_TYPES — change both together.
    // Webinar is NOT file-backed for download purposes; its recording may be an
    // attached file, but that is lifecycle (WebinarLifecycle), not delivery.
    private static final Set<String> FILE_TYPES =
        new Set<String>{ 'PDF', 'Form', 'Template' };
    private static final Integer MAX_DURATION_MINUTES = 999;
    /** Summary__c length — one sentence under the title (mirror: adminResourceEditor max-length). */
    private static final Integer MAX_SUMMARY_LENGTH = 160;

    // ---- DTOs -------------------------------------------------------------------

    public class ResourceRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String slug;
        @AuraEnabled public String resourceType;
        @AuraEnabled public String categoryName;                       // home category
        @AuraEnabled public Id categoryId;
        @AuraEnabled public List<String> secondaryCategoryNames = new List<String>(); // "Also show in"
        /** Same placements as ids — the list filters by category subtree, not by name. */
        @AuraEnabled public List<Id> secondaryCategoryIds = new List<Id>();
        @AuraEnabled public Boolean featured;
        @AuraEnabled public Boolean active;
        @AuraEnabled public Decimal displayOrder;
        @AuraEnabled public Decimal downloadCount;
        @AuraEnabled public Datetime lastModified;
        // Webinar-only (null otherwise) — WebinarLifecycle status for the list chip/filter.
        @AuraEnabled public String webinarStatus;
        @AuraEnabled public Datetime eventDatetime;
    }

    public class ArticleLink {
        @AuraEnabled public String kaId;
        @AuraEnabled public String title;
        @AuraEnabled public String urlName;
    }

    public class FileInfo {
        @AuraEnabled public Id contentDocumentId;
        @AuraEnabled public String title;
        @AuraEnabled public String extension;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public Boolean isCurrent; // the one ResourceCenterService serves
    }

    public class ResourceDetail {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String slug;
        @AuraEnabled public String description;      // rich text (HTML) as stored
        @AuraEnabled public String summary;
        @AuraEnabled public List<String> audience = new List<String>();
        @AuraEnabled public String resourceType;
        @AuraEnabled public Id categoryId;
        @AuraEnabled public String externalUrl;
        @AuraEnabled public String videoEmbedUrl;
        @AuraEnabled public Boolean featured;
        @AuraEnabled public Boolean active;
        @AuraEnabled public Decimal displayOrder;
        // Webinar-only fields (null for other types).
        @AuraEnabled public Datetime eventDatetime;
        @AuraEnabled public String registrationUrl;
        @AuraEnabled public Decimal durationMinutes;
        @AuraEnabled public String presenter;
        // Arc announcement (WebinarAnnouncementService): the flag, the explicit
        // time, the time it will actually use, and Scheduled/Pending/Live/Ended.
        @AuraEnabled public Boolean announceOnArc;
        @AuraEnabled public Datetime announceAt;
        @AuraEnabled public Datetime effectiveAnnounceAt;
        @AuraEnabled public String announcementStatus;
        @AuraEnabled public List<ArticleLink> relatedArticles = new List<ArticleLink>();
        @AuraEnabled public List<FileInfo> files = new List<FileInfo>();
        /** "Also show in" categories (never the home category). */
        @AuraEnabled public List<Id> secondaryCategoryIds = new List<Id>();
    }

    public class ResourceInput {
        @AuraEnabled public Id id;                   // null = create
        @AuraEnabled public String name;
        @AuraEnabled public String slug;
        @AuraEnabled public String description;      // rich text (HTML) from lightning-input-rich-text
        @AuraEnabled public String summary;          // ≤ MAX_SUMMARY_LENGTH
        @AuraEnabled public List<String> audience;   // Audience__c selections; null/empty = none
        @AuraEnabled public String resourceType;
        @AuraEnabled public Id categoryId;
        @AuraEnabled public String externalUrl;
        @AuraEnabled public String videoEmbedUrl;
        @AuraEnabled public Boolean featured;
        @AuraEnabled public Boolean active;
        @AuraEnabled public Decimal displayOrder;
        // Webinar-only; ignored (and cleared on the record) for other types.
        @AuraEnabled public Datetime eventDatetime;      // ISO-8601 string from the LWC
        @AuraEnabled public String registrationUrl;
        @AuraEnabled public Decimal durationMinutes;
        @AuraEnabled public String presenter;
        @AuraEnabled public Boolean announceOnArc;
        @AuraEnabled public Datetime announceAt;             // null = the 8:00 AM default
        @AuraEnabled public List<String> relatedArticleKaIds;
        /** "Also show in" category Ids: null = untouched, empty = clear all. Home is stripped. */
        @AuraEnabled public List<String> secondaryCategoryIds;
    }

    public class CategoryInput {
        @AuraEnabled public Id id;                   // null = create
        @AuraEnabled public String name;
        @AuraEnabled public String slug;
        @AuraEnabled public String iconName;
        @AuraEnabled public Decimal displayOrder;
        @AuraEnabled public Id parentId;
        @AuraEnabled public Boolean active;
    }

    /** Tree node shaped for c-admin-category-tree ({name,label,children}). */
    public class CategoryNode {
        @AuraEnabled public String name;   // Resource_Category__c Id
        @AuraEnabled public String label;
        @AuraEnabled public List<CategoryNode> children = new List<CategoryNode>();
    }

    public class PickItem {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
        @AuraEnabled public String sublabel;
    }

    // ---- Resource reads ------------------------------------------------------------

    @AuraEnabled
    public static List<ResourceRow> listResources() {
        assertResourceAdmin();
        List<ResourceRow> out = new List<ResourceRow>();
        List<Resource__c> rows = [
            SELECT Id, Name, Slug__c, Resource_Type__c, Category__c, Category__r.Name,
                   Is_Featured__c, Is_Active__c, Display_Order__c, Download_Count__c,
                   LastModifiedDate, Video_Embed_URL__c, Event_Datetime__c
            FROM Resource__c
            ORDER BY Name ASC
            LIMIT :LIST_LIMIT
        ];
        // Lifecycle chips need recording presence: one bulk file lookup over
        // the webinar rows only, using the same "newest file wins" rule the
        // public pages serve.
        Set<Id> webinarIds = new Set<Id>();
        for (Resource__c r : rows) {
            if (WebinarLifecycle.isWebinar(r.Resource_Type__c)) {
                webinarIds.add(r.Id);
            }
        }
        Map<Id, ResourceCenterService.FileInfo> files = webinarIds.isEmpty()
            ? new Map<Id, ResourceCenterService.FileInfo>()
            : ResourceCenterService.fileInfoByResource(webinarIds);
        // "Also show in" placements, one bulk query over every listed row —
        // names for the cell, ids for the category-subtree filter.
        Map<Id, List<String>> secondaryNames = new Map<Id, List<String>>();
        Map<Id, List<Id>> secondaryIds = new Map<Id, List<Id>>();
        for (Resource_Category_Link__c link : [
            SELECT Resource__c, Category__c, Category__r.Name
            FROM Resource_Category_Link__c
            WHERE Resource__c IN :rows
            ORDER BY Category__r.Name ASC
        ]) {
            if (!secondaryNames.containsKey(link.Resource__c)) {
                secondaryNames.put(link.Resource__c, new List<String>());
                secondaryIds.put(link.Resource__c, new List<Id>());
            }
            secondaryNames.get(link.Resource__c).add(link.Category__r.Name);
            secondaryIds.get(link.Resource__c).add(link.Category__c);
        }
        Datetime now = System.now();
        for (Resource__c r : rows) {
            ResourceRow row = new ResourceRow();
            row.id = r.Id;
            row.name = r.Name;
            row.slug = r.Slug__c;
            row.resourceType = r.Resource_Type__c;
            row.categoryId = r.Category__c;
            row.categoryName = r.Category__r == null ? null : r.Category__r.Name;
            if (secondaryNames.containsKey(r.Id)) {
                row.secondaryCategoryNames = secondaryNames.get(r.Id);
                row.secondaryCategoryIds = secondaryIds.get(r.Id);
            }
            row.featured = r.Is_Featured__c == true;
            row.active = r.Is_Active__c == true;
            row.displayOrder = r.Display_Order__c;
            row.downloadCount = r.Download_Count__c;
            row.lastModified = r.LastModifiedDate;
            row.eventDatetime = r.Event_Datetime__c;
            row.webinarStatus = WebinarLifecycle.statusFor(r, files.containsKey(r.Id), now);
            out.add(row);
        }
        return out;
    }

    @AuraEnabled
    public static ResourceDetail getResource(Id resourceId) {
        assertResourceAdmin();
        List<Resource__c> rows = [
            SELECT Id, Name, Slug__c, Description__c, Summary__c, Audience__c, Resource_Type__c, Category__c,
                   External_URL__c, Video_Embed_URL__c, Is_Featured__c, Is_Active__c,
                   Display_Order__c, Event_Datetime__c, Registration_URL__c,
                   Event_Duration_Minutes__c, Presenter__c,
                   Announce_On_Arc__c, Announce_At__c, Announcement__c, Announcement__r.Is_Active__c
            FROM Resource__c
            WHERE Id = :resourceId
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw auraError('Resource not found.');
        }
        Resource__c r = rows[0];
        ResourceDetail detail = new ResourceDetail();
        detail.id = r.Id;
        detail.name = r.Name;
        detail.slug = r.Slug__c;
        detail.description = r.Description__c;
        detail.summary = r.Summary__c;
        detail.audience = ResourceCenterService.splitMulti(r.Audience__c);
        detail.resourceType = r.Resource_Type__c;
        detail.categoryId = r.Category__c;
        detail.externalUrl = r.External_URL__c;
        detail.videoEmbedUrl = r.Video_Embed_URL__c;
        detail.featured = r.Is_Featured__c == true;
        detail.active = r.Is_Active__c == true;
        detail.displayOrder = r.Display_Order__c;
        detail.eventDatetime = r.Event_Datetime__c;
        detail.registrationUrl = r.Registration_URL__c;
        detail.durationMinutes = r.Event_Duration_Minutes__c;
        detail.presenter = r.Presenter__c;
        detail.announceOnArc = r.Announce_On_Arc__c == true;
        detail.announceAt = r.Announce_At__c;
        detail.effectiveAnnounceAt = WebinarLifecycle.isWebinar(r.Resource_Type__c)
            ? WebinarAnnouncementService.effectiveAnnounceAt(r.Event_Datetime__c, r.Announce_At__c)
            : null;
        detail.announcementStatus = WebinarAnnouncementService.statusFor(
            r, r.Announcement__c == null ? null : r.Announcement__r.Is_Active__c, System.now());
        detail.relatedArticles = relatedArticlesFor(resourceId);
        detail.files = filesFor(resourceId);
        detail.secondaryCategoryIds = secondaryCategoryIdsFor(resourceId);
        return detail;
    }

    @AuraEnabled
    public static Boolean isSlugAvailable(String slug, Id excludeId) {
        assertResourceAdmin();
        if (String.isBlank(slug)) {
            return false;
        }
        for (Resource__c r : [
            SELECT Id FROM Resource__c WHERE Slug__c = :slug.trim() LIMIT 5
        ]) {
            if (excludeId == null || r.Id != excludeId) {
                return false;
            }
        }
        return true;
    }

    /** Article picker for the resource-side linker: value = the stable KA Id. */
    @AuraEnabled
    public static List<PickItem> searchArticlesForLink(String term) {
        if (!Schema.sObjectType.Knowledge__kav.isAccessible()) {
            throw auraError('You do not have access to Knowledge articles.');
        }
        List<PickItem> out = new List<PickItem>();
        if (String.isBlank(term) || term.trim().length() < 2) {
            return out;
        }
        String likeTerm = '%' + String.escapeSingleQuotes(term.trim()) + '%';
        for (Knowledge__kav v : [
            SELECT KnowledgeArticleId, Title, UrlName FROM Knowledge__kav
            WHERE PublishStatus = 'Online' AND IsLatestVersion = true
            AND Language = :LANG AND Title LIKE :likeTerm
            ORDER BY Title ASC
            LIMIT :PICKER_LIMIT
        ]) {
            PickItem item = new PickItem();
            item.value = v.KnowledgeArticleId;
            item.label = v.Title;
            item.sublabel = v.UrlName;
            out.add(item);
        }
        return out;
    }

    // ---- Resource writes -------------------------------------------------------------

    @AuraEnabled
    public static Id saveResource(String inputJson) {
        assertResourceAdmin();
        ResourceInput input = (ResourceInput) parseInput(inputJson, ResourceInput.class);
        if (input == null || String.isBlank(input.name) || String.isBlank(input.slug)) {
            throw auraError('Name and URL slug are required.');
        }
        if (String.isBlank(input.resourceType)) {
            throw auraError('Pick a resource type first — it decides what else is needed.');
        }
        if (input.resourceType == 'Video' && String.isBlank(input.videoEmbedUrl)) {
            throw auraError('Video resources need a Video Embed URL.');
        }
        if (input.resourceType == 'External Link' && String.isBlank(input.externalUrl)) {
            throw auraError('External Link resources need an External URL.');
        }
        if (input.categoryId == null) {
            throw auraError('Pick a home category — resources always live in one.');
        }
        // Webinar rules mirror the two validation rules on Resource__c
        // (Webinar_Requires_Event_Datetime, Webinar_Upcoming_Requires_Registration)
        // so the admin sees a friendly message instead of a DML error.
        Boolean isWebinar = WebinarLifecycle.isWebinar(input.resourceType);
        if (isWebinar && input.eventDatetime == null) {
            throw auraError('Webinars need an event date and time.');
        }
        if (isWebinar && input.eventDatetime > System.now()
            && String.isBlank(input.registrationUrl)) {
            throw auraError('Upcoming webinars need a registration URL so people can sign up.');
        }
        if (isWebinar && input.durationMinutes != null
            && (input.durationMinutes < 1 || input.durationMinutes > MAX_DURATION_MINUTES)) {
            throw auraError('Duration must be between 1 and ' + MAX_DURATION_MINUTES + ' minutes.');
        }
        if (isWebinar && input.announceAt != null && input.eventDatetime != null
            && input.announceAt >= input.eventDatetime) {
            throw auraError('The Arc announcement must go out before the event starts.');
        }
        String summary = String.isBlank(input.summary) ? null : input.summary.trim();
        if (summary != null && summary.length() > MAX_SUMMARY_LENGTH) {
            throw auraError('Keep the summary to ' + MAX_SUMMARY_LENGTH + ' characters — one sentence.');
        }
        List<String> audience = new List<String>();
        for (String a : input.audience == null ? new List<String>() : input.audience) {
            if (String.isNotBlank(a)) {
                audience.add(a.trim());
            }
        }

        Resource__c record = new Resource__c(
            Name = input.name.trim(),
            Slug__c = input.slug.trim(),
            Description__c = input.description,
            Summary__c = summary,
            Audience__c = audience.isEmpty() ? null : String.join(audience, ';'),
            Resource_Type__c = input.resourceType,
            Category__c = input.categoryId,
            External_URL__c = input.externalUrl,
            Video_Embed_URL__c = normalizeVideoUrl(input.videoEmbedUrl),
            Is_Featured__c = input.featured == true,
            Is_Active__c = input.active != false,
            Display_Order__c = input.displayOrder,
            // Cleared for non-webinars so a type switch never carries stale event data.
            Event_Datetime__c = isWebinar ? input.eventDatetime : null,
            Registration_URL__c = isWebinar ? requireHttps(input.registrationUrl, 'Registration URL') : null,
            Event_Duration_Minutes__c = isWebinar ? input.durationMinutes : null,
            Presenter__c = isWebinar ? input.presenter : null,
            Announce_On_Arc__c = isWebinar && input.announceOnArc == true,
            Announce_At__c = isWebinar ? input.announceAt : null
        );

        Savepoint sp = Database.setSavepoint();
        try {
            if (input.id == null) {
                insert record;
            } else {
                record.Id = input.id;
                update record;
            }
            syncRelatedArticles(record.Id, input.relatedArticleKaIds);
            syncSecondaryCategories(record.Id, input.categoryId, input.secondaryCategoryIds);
            return record.Id;
        } catch (AuraHandledException e) {
            Database.rollback(sp);
            throw e;
        } catch (DmlException e) {
            Database.rollback(sp);
            if (e.getMessage().contains('DUPLICATE_VALUE')) {
                throw auraError('That URL slug is already used by another resource — pick a different one.');
            }
            throw auraError('Could not save the resource: ' + e.getDmlMessage(0));
        }
    }

    /** Detach a file from the resource (the newest remaining link is served). */
    @AuraEnabled
    public static void removeFile(Id resourceId, Id contentDocumentId) {
        assertResourceAdmin();
        List<ContentDocumentLink> links = [
            SELECT Id FROM ContentDocumentLink
            WHERE LinkedEntityId = :resourceId AND ContentDocumentId = :contentDocumentId
            LIMIT 1
        ];
        if (links.isEmpty()) {
            return;
        }
        try {
            delete links;
        } catch (DmlException e) {
            throw auraError('Could not remove the file: ' + e.getDmlMessage(0));
        }
    }

    @AuraEnabled
    public static List<FileInfo> getFiles(Id resourceId) {
        assertResourceAdmin();
        return filesFor(resourceId);
    }

    // ---- Category reads/writes --------------------------------------------------------

    /**
     * The admin tree for c-admin-tree-editor: every category (inactive rows
     * included, flagged), any depth, own/"also shown"/subtree counts, and the
     * depth limit the editor must respect (never hard-coded client-side).
     */
    @AuraEnabled
    public static CategoryTreeService.TreeDTO getCategoryTree() {
        assertCategoryAdmin();
        return ResourceCategoryTreeProvider.load(false).toDTO();
    }

    /** Active categories, any depth, in the pickers' {name,label,children} shape. */
    @AuraEnabled
    public static List<CategoryNode> getResourceCategoryTree() {
        assertCategoryReadable();
        List<CategoryNode> roots = new List<CategoryNode>();
        // Parallel stacks: source node / destination node (iterative, any depth).
        List<CategoryTreeService.TreeNode> src = new List<CategoryTreeService.TreeNode>();
        List<CategoryNode> dst = new List<CategoryNode>();
        for (CategoryTreeService.TreeNode r : ResourceCategoryTreeProvider.load(true).roots) {
            CategoryNode node = new CategoryNode();
            node.name = r.id;
            node.label = r.label;
            roots.add(node);
            src.add(r);
            dst.add(node);
        }
        while (!src.isEmpty()) {
            CategoryTreeService.TreeNode t = src.remove(src.size() - 1);
            CategoryNode n = dst.remove(dst.size() - 1);
            for (CategoryTreeService.TreeNode c : t.children) {
                CategoryNode child = new CategoryNode();
                child.name = c.id;
                child.label = c.label;
                n.children.add(child);
                src.add(c);
                dst.add(child);
            }
        }
        return roots;
    }

    @AuraEnabled
    public static Id saveCategory(String inputJson) {
        assertCategoryAdmin();
        CategoryInput input = (CategoryInput) parseInput(inputJson, CategoryInput.class);
        if (input == null || String.isBlank(input.name) || String.isBlank(input.slug)) {
            throw auraError('Name and URL slug are required.');
        }
        // Tree rules — self, cycles, depth counting the moved subtree — checked
        // here for a clean message; the trigger re-checks every DML path.
        if (input.id != null || input.parentId != null) {
            CategoryTreeService.Tree tree = ResourceCategoryTreeProvider.load(false);
            String problem = null;
            if (input.id != null) {
                problem = tree.validateMove(String.valueOf(input.id),
                    input.parentId == null ? null : String.valueOf(input.parentId));
            } else {
                CategoryTreeService.TreeNode parent = tree.get(String.valueOf(input.parentId));
                if (parent == null) {
                    problem = CategoryTreeService.MSG_MISSING_PARENT;
                } else if (parent.depth + 1 > tree.maxDepth) {
                    problem = CategoryTreeService.depthMessage(tree.maxDepth);
                }
            }
            if (problem != null) {
                throw auraError(problem);
            }
        }
        if (input.id == null && input.displayOrder == null) {
            input.displayOrder = nextDisplayOrder(input.parentId);
        }
        Resource_Category__c record = new Resource_Category__c(
            Name = input.name.trim(),
            Slug__c = input.slug.trim(),
            Icon_Name__c = input.iconName,
            Display_Order__c = input.displayOrder,
            Parent_Category__c = input.parentId,
            Is_Active__c = input.active != false
        );
        try {
            if (input.id == null) {
                insert record;
            } else {
                record.Id = input.id;
                update record;
            }
            return record.Id;
        } catch (DmlException e) {
            if (e.getMessage().contains('DUPLICATE_VALUE')) {
                throw auraError('That URL slug is already used by another category — pick a different one.');
            }
            throw auraError('Could not save the category: ' + e.getDmlMessage(0));
        }
    }

    /**
     * Reorders the children of parentId (null/blank = top-level categories).
     * orderedIdsJson is a JSON array of the sibling record Ids — string
     * transport because non-primitive @AuraEnabled params arrive null from
     * LWC in this org. Rejects the save unless the submitted set exactly
     * matches the live siblings (all statuses — the admin pane shows both),
     * mirroring HelpTopicAdminController.reorderTopics.
     */
    @AuraEnabled
    public static void reorderCategories(String parentId, String orderedIdsJson) {
        assertCategoryAdmin();
        List<String> orderedIds;
        Id parent;
        try {
            orderedIds = String.isBlank(orderedIdsJson)
                ? null
                : (List<String>) JSON.deserialize(orderedIdsJson, List<String>.class);
            parent = String.isBlank(parentId) ? null : Id.valueOf(parentId.trim());
        } catch (Exception e) {
            throw auraError('Could not read the new order — refresh and try again.');
        }
        Map<Id, Resource_Category__c> siblings = new Map<Id, Resource_Category__c>([
            SELECT Id FROM Resource_Category__c
            WHERE Parent_Category__c = :parent
            LIMIT :LIST_LIMIT
        ]);
        Set<Id> submitted = new Set<Id>();
        if (orderedIds != null) {
            for (String catId : orderedIds) {
                try {
                    submitted.add(Id.valueOf(catId));
                } catch (Exception e) {
                    throw auraError('The category list changed while you were editing — refresh.');
                }
            }
        }
        if (orderedIds == null
            || orderedIds.size() != siblings.size()
            || !siblings.keySet().equals(submitted)) {
            throw auraError('The category list changed while you were editing — refresh.');
        }
        List<Resource_Category__c> updates = new List<Resource_Category__c>();
        Integer order = 1;
        for (String catId : orderedIds) {
            updates.add(new Resource_Category__c(Id = catId, Display_Order__c = order++));
        }
        try {
            update updates;
        } catch (DmlException e) {
            throw auraError('Could not reorder categories: ' + e.getDmlMessage(0));
        }
    }

    /**
     * Drag-and-drop move: `categoryId` (with its whole subtree) becomes a child
     * of newParentId (blank = top level) and orderedSiblingIdsJson — EVERY
     * sibling under the new parent including the moved one, in final order —
     * is written as Display_Order__c, all in one transaction. Validated against
     * the live tree (self / own subtree / depth counting the subtree's height)
     * and re-validated by the trigger; stale lists are rejected like
     * reorderCategories.
     */
    @AuraEnabled
    public static void moveCategory(String categoryId, String newParentId, String orderedSiblingIdsJson) {
        assertCategoryAdmin();
        Id moved;
        Id parent;
        List<String> orderedIds;
        try {
            moved = Id.valueOf(categoryId.trim());
            parent = String.isBlank(newParentId) ? null : Id.valueOf(newParentId.trim());
            orderedIds = String.isBlank(orderedSiblingIdsJson)
                ? null
                : (List<String>) JSON.deserialize(orderedSiblingIdsJson, List<String>.class);
        } catch (Exception e) {
            throw auraError('Could not read the move — refresh and try again.');
        }
        CategoryTreeService.Tree tree = ResourceCategoryTreeProvider.load(false);
        String problem = tree.validateMove(String.valueOf(moved), parent == null ? null : String.valueOf(parent));
        if (problem != null) {
            throw auraError(problem);
        }
        Set<Id> expected = new Set<Id>{ moved };
        for (CategoryTreeService.TreeNode s : parent == null ? tree.roots : tree.get(String.valueOf(parent)).children) {
            expected.add(Id.valueOf(s.id));
        }
        Set<Id> submitted = new Set<Id>();
        if (orderedIds != null) {
            for (String catId : orderedIds) {
                try {
                    submitted.add(Id.valueOf(catId));
                } catch (Exception e) {
                    throw auraError('The category list changed while you were editing — refresh.');
                }
            }
        }
        if (orderedIds == null || orderedIds.size() != expected.size() || !expected.equals(submitted)) {
            throw auraError('The category list changed while you were editing — refresh.');
        }
        List<Resource_Category__c> updates = new List<Resource_Category__c>();
        Integer order = 1;
        for (String catId : orderedIds) {
            Resource_Category__c row = new Resource_Category__c(Id = catId, Display_Order__c = order++);
            if (row.Id == moved) {
                row.Parent_Category__c = parent;
            }
            updates.add(row);
        }
        try {
            update updates;
        } catch (DmlException e) {
            throw auraError('Could not move the category: ' + e.getDmlMessage(0));
        }
    }

    @AuraEnabled
    public static Boolean isCategorySlugAvailable(String slug, Id excludeId) {
        assertCategoryReadable();
        if (String.isBlank(slug)) {
            return false;
        }
        for (Resource_Category__c c : [
            SELECT Id FROM Resource_Category__c WHERE Slug__c = :slug.trim() LIMIT 5
        ]) {
            if (excludeId == null || c.Id != excludeId) {
                return false;
            }
        }
        return true;
    }

    // ---- Category delete -----------------------------------------------------------

    public static final String MODE_BLOCK = 'block';
    public static final String MODE_REPARENT = 'reparent';

    /**
     * Pre-flight for the delete dialog: what blocks each mode, and where the
     * subtopics would go. Subtree counts guard "block"; own counts guard
     * "reparent" (the subtopics keep their content and move up).
     */
    public class CategoryDeleteImpactDTO {
        @AuraEnabled public String name;
        @AuraEnabled public Id parentId;               // where children go with "reparent" (null = top level)
        @AuraEnabled public String parentName;
        @AuraEnabled public Integer childCount;        // direct subtopics
        @AuraEnabled public Integer descendantCount;   // whole subtree below
        @AuraEnabled public Integer resourceCount;     // home resources in the subtree (self included)
        @AuraEnabled public Integer ownResourceCount;  // home resources on the category itself
        @AuraEnabled public Integer secondaryCount;    // "Also show in" links into the subtree
        @AuraEnabled public Integer ownSecondaryCount;
        @AuraEnabled public Integer guideOptionCount;  // help-guide options targeting any slug in the subtree
        @AuraEnabled public Integer ownGuideOptionCount;
    }

    /**
     * What deleting a category would touch. Resource__c.Category__c and
     * Resource_Category_Link__c.Category__c are Restrict lookups (DML would
     * fail anyway) and help guides target categories by slug (published
     * options and Builder drafts), so all three block. Parent_Category__c is
     * SetNull — the platform would silently promote subtopics — so a category
     * with subtopics is only deleted with an explicit choice (deleteCategory).
     */
    @AuraEnabled
    public static CategoryDeleteImpactDTO getCategoryDeleteImpact(Id categoryId) {
        assertCategoryAdmin();
        CategoryTreeService.Tree tree = ResourceCategoryTreeProvider.load(false);
        CategoryTreeService.TreeNode node = categoryId == null ? null : tree.get(String.valueOf(categoryId));
        if (node == null) {
            throw auraError('That category no longer exists — refresh.');
        }
        Set<Id> ids = new Set<Id>{ categoryId };
        Set<String> slugs = new Set<String>{ node.slug };
        for (CategoryTreeService.TreeNode d : tree.descendantsOf(node.id)) {
            ids.add(Id.valueOf(d.id));
            slugs.add(d.slug);
        }
        CategoryDeleteImpactDTO dto = new CategoryDeleteImpactDTO();
        dto.name = node.label;
        dto.parentId = node.parentId == null ? null : Id.valueOf(node.parentId);
        dto.parentName = node.parentId == null ? null : tree.get(node.parentId).label;
        dto.childCount = node.children.size();
        dto.descendantCount = ids.size() - 1;
        dto.resourceCount = 0;
        dto.ownResourceCount = 0;
        for (AggregateResult ar : [
            SELECT Category__c cat, COUNT(Id) c FROM Resource__c WHERE Category__c IN :ids GROUP BY Category__c
        ]) {
            Integer c = (Integer) ar.get('c');
            dto.resourceCount += c;
            if ((Id) ar.get('cat') == categoryId) {
                dto.ownResourceCount = c;
            }
        }
        dto.secondaryCount = 0;
        dto.ownSecondaryCount = 0;
        for (AggregateResult ar : [
            SELECT Category__c cat, COUNT(Id) c FROM Resource_Category_Link__c
            WHERE Category__c IN :ids GROUP BY Category__c
        ]) {
            Integer c = (Integer) ar.get('c');
            dto.secondaryCount += c;
            if ((Id) ar.get('cat') == categoryId) {
                dto.ownSecondaryCount = c;
            }
        }
        dto.guideOptionCount = 0;
        dto.ownGuideOptionCount = 0;
        List<String> targets = new List<String>();
        for (Help_Guide_Option__mdt opt : [
            SELECT Target_Value__c FROM Help_Guide_Option__mdt
            WHERE Target_Type__c = 'category' AND Active__c = true AND Target_Value__c IN :slugs
        ]) {
            targets.add(opt.Target_Value__c);
        }
        for (Help_Guide_Option_Draft__c opt : [
            SELECT Target_Value__c FROM Help_Guide_Option_Draft__c
            WHERE Target_Type__c = 'category' AND Target_Value__c IN :slugs
        ]) {
            targets.add(opt.Target_Value__c);
        }
        for (String target : targets) {
            dto.guideOptionCount++;
            if (target == node.slug) {
                dto.ownGuideOptionCount++;
            }
        }
        return dto;
    }

    /**
     * Deletes ONE category — never a cascade. mode 'reparent': its direct
     * subtopics move up to its parent (appended after the existing siblings,
     * their own order kept; the trigger rewrites their paths) and only the
     * category itself must be empty. mode 'block' (default): the category must
     * have no subtopics and nothing anywhere in its subtree — resources,
     * "Also show in" links, help-guide targets. Re-validates everything first.
     */
    @AuraEnabled
    public static void deleteCategory(Id categoryId, String mode) {
        assertCategoryAdmin();
        if (!Schema.sObjectType.Resource_Category__c.isDeletable()) {
            throw auraError('You do not have access to delete resource categories.');
        }
        Boolean reparent = mode == MODE_REPARENT;
        CategoryDeleteImpactDTO impact = getCategoryDeleteImpact(categoryId);
        Integer resources = reparent ? impact.ownResourceCount : impact.resourceCount;
        Integer secondary = reparent ? impact.ownSecondaryCount : impact.secondaryCount;
        Integer guides = reparent ? impact.ownGuideOptionCount : impact.guideOptionCount;
        // Content blocks regardless of mode, so report it first; the subtopic
        // rule only matters once the content question is settled.
        if (resources > 0) {
            throw auraError('Can\'t delete this category — ' + resources + ' resource'
                + (resources == 1 ? ' lives' : 's live')
                + (reparent ? ' on it' : ' under it') + '. Move or delete those resources first.');
        }
        if (secondary > 0) {
            throw auraError('Can\'t delete this category — ' + secondary + ' resource'
                + (secondary == 1 ? ' is' : 's are')
                + ' also shown in it. Remove it from those resources first.');
        }
        if (guides > 0) {
            throw auraError('Can\'t delete this category — ' + guides
                + ' help guide option' + (guides == 1 ? ' links' : 's link')
                + ' to it. Retarget or remove ' + (guides == 1 ? 'it' : 'them')
                + ' in the Help Guide Builder first.');
        }
        if (!reparent && impact.childCount > 0) {
            throw auraError('Can\'t delete this category — it has ' + impact.childCount
                + (impact.childCount == 1 ? ' subtopic' : ' subtopics')
                + '. Move them up or move them elsewhere first.');
        }
        try {
            if (reparent && impact.childCount > 0) {
                Decimal order = nextDisplayOrder(impact.parentId);
                List<Resource_Category__c> promoted = new List<Resource_Category__c>();
                for (Resource_Category__c child : [
                    SELECT Id FROM Resource_Category__c
                    WHERE Parent_Category__c = :categoryId
                    ORDER BY Display_Order__c ASC NULLS LAST, Name ASC
                    LIMIT :LIST_LIMIT
                ]) {
                    promoted.add(new Resource_Category__c(
                        Id = child.Id, Parent_Category__c = impact.parentId, Display_Order__c = order++));
                }
                update promoted;
            }
            delete new Resource_Category__c(Id = categoryId);
        } catch (DmlException e) {
            // Restrict race: a resource landed between the check and the delete.
            throw auraError('It could not be deleted: ' + e.getDmlMessage(0));
        }
    }

    // ---- Internals ----------------------------------------------------------------

    /** New categories append after their siblings, like new help topics do. */
    private static Decimal nextDisplayOrder(Id parentId) {
        AggregateResult ar = [
            SELECT MAX(Display_Order__c) mx FROM Resource_Category__c
            WHERE Parent_Category__c = :parentId
        ];
        Decimal mx = (Decimal) ar.get('mx');
        return mx == null ? 1 : mx + 1;
    }

    private static List<ArticleLink> relatedArticlesFor(Id resourceId) {
        List<ArticleLink> out = new List<ArticleLink>();
        Map<String, ArticleLink> byKa = new Map<String, ArticleLink>();
        for (Article_Resource__c link : [
            SELECT Knowledge_Article_Id__c, Article_UrlName__c
            FROM Article_Resource__c
            WHERE Resource__c = :resourceId
            ORDER BY Display_Order__c ASC NULLS LAST
        ]) {
            ArticleLink al = new ArticleLink();
            al.kaId = link.Knowledge_Article_Id__c;
            al.urlName = link.Article_UrlName__c;
            byKa.put(al.kaId, al);
            out.add(al);
        }
        if (!byKa.isEmpty() && Schema.sObjectType.Knowledge__kav.isAccessible()) {
            for (Knowledge__kav v : [
                SELECT KnowledgeArticleId, Title, UrlName FROM Knowledge__kav
                WHERE KnowledgeArticleId IN :byKa.keySet()
                AND PublishStatus = 'Online' AND IsLatestVersion = true AND Language = :LANG
            ]) {
                ArticleLink al = byKa.get(v.KnowledgeArticleId);
                al.title = v.Title;
                al.urlName = v.UrlName;
            }
        }
        return out;
    }

    private static List<Id> secondaryCategoryIdsFor(Id resourceId) {
        List<Id> out = new List<Id>();
        for (Resource_Category_Link__c link : [
            SELECT Category__c FROM Resource_Category_Link__c
            WHERE Resource__c = :resourceId
            ORDER BY Category__r.Name ASC
        ]) {
            out.add(link.Category__c);
        }
        return out;
    }

    /**
     * "Also show in" sync: null = untouched (only a link that now equals the
     * home category is dropped); otherwise the home is stripped, the rest are
     * validated to exist, and the junction is diffed — delete removed, insert new.
     */
    private static void syncSecondaryCategories(Id resourceId, Id homeCategoryId,
            List<String> categoryIds) {
        Set<Id> wanted = new Set<Id>();
        if (categoryIds != null) {
            for (String raw : categoryIds) {
                if (String.isBlank(raw)) {
                    continue;
                }
                try {
                    wanted.add(Id.valueOf(raw.trim()));
                } catch (Exception e) {
                    throw auraError('One of the "Also show in" categories no longer exists — refresh and re-pick.');
                }
            }
            wanted.remove(homeCategoryId);
            if (!wanted.isEmpty()
                && [SELECT COUNT() FROM Resource_Category__c WHERE Id IN :wanted] != wanted.size()) {
                throw auraError('One of the "Also show in" categories no longer exists — refresh and re-pick.');
            }
        }

        List<Resource_Category_Link__c> existing = [
            SELECT Id, Category__c FROM Resource_Category_Link__c
            WHERE Resource__c = :resourceId
        ];
        if (categoryIds == null) {
            // Untouched — but a home change must not leave a self-link behind.
            List<Resource_Category_Link__c> stale = new List<Resource_Category_Link__c>();
            for (Resource_Category_Link__c link : existing) {
                if (link.Category__c == homeCategoryId) {
                    stale.add(link);
                }
            }
            if (!stale.isEmpty()) {
                assertLinkWritable();
                delete stale;
            }
            return;
        }

        Set<Id> kept = new Set<Id>();
        List<Resource_Category_Link__c> toDelete = new List<Resource_Category_Link__c>();
        for (Resource_Category_Link__c link : existing) {
            if (wanted.contains(link.Category__c) && !kept.contains(link.Category__c)) {
                kept.add(link.Category__c);
            } else {
                toDelete.add(link); // removed, now the home, or a duplicate
            }
        }
        List<Resource_Category_Link__c> toInsert = new List<Resource_Category_Link__c>();
        for (Id catId : wanted) {
            if (!kept.contains(catId)) {
                toInsert.add(new Resource_Category_Link__c(Resource__c = resourceId, Category__c = catId));
            }
        }
        if (toDelete.isEmpty() && toInsert.isEmpty()) {
            return;
        }
        assertLinkWritable();
        if (!toDelete.isEmpty()) {
            delete toDelete;
        }
        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
    }

    private static void assertLinkWritable() {
        if (!Schema.sObjectType.Resource_Category_Link__c.isCreateable()
            || !Schema.sObjectType.Resource_Category_Link__c.isDeletable()) {
            throw auraError('You do not have access to manage category placements.');
        }
    }

    /**
     * Resource-side junction sync: null = untouched; otherwise delete removed
     * rows and insert new ones with the UrlName resolved server-side.
     */
    private static void syncRelatedArticles(Id resourceId, List<String> kaIds) {
        if (kaIds == null) {
            return;
        }
        if (!Schema.sObjectType.Article_Resource__c.isCreateable()
            || !Schema.sObjectType.Article_Resource__c.isDeletable()) {
            throw auraError('You do not have access to manage article-resource links.');
        }

        Set<String> wanted = new Set<String>();
        for (String kaId : kaIds) {
            if (String.isNotBlank(kaId)) {
                wanted.add(kaId.trim());
            }
        }

        Map<String, String> urlNames = new Map<String, String>();
        if (!wanted.isEmpty()) {
            for (Knowledge__kav v : [
                SELECT KnowledgeArticleId, UrlName FROM Knowledge__kav
                WHERE KnowledgeArticleId IN :wanted
                AND PublishStatus = 'Online' AND IsLatestVersion = true AND Language = :LANG
            ]) {
                urlNames.put(v.KnowledgeArticleId, v.UrlName);
            }
            for (String kaId : wanted) {
                if (!urlNames.containsKey(kaId)) {
                    throw auraError('One of the picked articles is no longer published — refresh and re-pick.');
                }
            }
        }

        Set<String> existing = new Set<String>();
        List<Article_Resource__c> toDelete = new List<Article_Resource__c>();
        for (Article_Resource__c link : [
            SELECT Id, Knowledge_Article_Id__c FROM Article_Resource__c
            WHERE Resource__c = :resourceId
        ]) {
            if (wanted.contains(link.Knowledge_Article_Id__c)) {
                existing.add(link.Knowledge_Article_Id__c);
            } else {
                toDelete.add(link);
            }
        }
        List<Article_Resource__c> toInsert = new List<Article_Resource__c>();
        for (String kaId : wanted) {
            if (!existing.contains(kaId)) {
                toInsert.add(new Article_Resource__c(
                    Resource__c = resourceId,
                    Knowledge_Article_Id__c = kaId,
                    Article_UrlName__c = urlNames.get(kaId)
                ));
            }
        }
        if (!toDelete.isEmpty()) {
            delete toDelete;
        }
        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
    }

    private static List<FileInfo> filesFor(Id resourceId) {
        List<FileInfo> out = new List<FileInfo>();
        for (ContentDocumentLink link : [
            SELECT ContentDocumentId, ContentDocument.Title,
                   ContentDocument.FileExtension, ContentDocument.CreatedDate
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :resourceId
            ORDER BY ContentDocument.CreatedDate DESC
        ]) {
            FileInfo f = new FileInfo();
            f.contentDocumentId = link.ContentDocumentId;
            f.title = link.ContentDocument.Title;
            f.extension = link.ContentDocument.FileExtension;
            f.createdDate = link.ContentDocument.CreatedDate;
            f.isCurrent = out.isEmpty(); // newest-by-CreatedDate is what gets served
            out.add(f);
        }
        return out;
    }

    /**
     * Form payloads cross the LWC→Apex boundary as JSON strings: custom-Apex-type
     * @AuraEnabled parameters arrive null/blank from LWC in this org, so wrapper
     * inputs must never be method parameter types themselves.
     */
    private static Object parseInput(String inputJson, System.Type dtoType) {
        if (String.isBlank(inputJson)) {
            return null;
        }
        try {
            return JSON.deserialize(inputJson, dtoType);
        } catch (Exception e) {
            throw auraError('Could not read the form — refresh and try again.');
        }
    }

    /**
     * The detail page iframes this value directly; YouTube/Vimeo refuse to frame
     * their page URLs, so convert the common ones to their embeddable form.
     */
    @TestVisible
    private static String normalizeVideoUrl(String url) {
        if (String.isBlank(url)) {
            return null;
        }
        String clean = url.trim();
        Matcher watch = Pattern.compile(
            '(?i)^https://(?:www\\.|m\\.)?youtube\\.com/watch\\?(?:.*&)?v=([\\w\\-]+).*$').matcher(clean);
        if (watch.matches()) {
            return 'https://www.youtube.com/embed/' + watch.group(1);
        }
        Matcher shortUrl = Pattern.compile(
            '(?i)^https://youtu\\.be/([\\w\\-]+).*$').matcher(clean);
        if (shortUrl.matches()) {
            return 'https://www.youtube.com/embed/' + shortUrl.group(1);
        }
        Matcher vimeo = Pattern.compile(
            '(?i)^https://(?:www\\.)?vimeo\\.com/(\\d+).*$').matcher(clean);
        if (vimeo.matches()) {
            return 'https://player.vimeo.com/video/' + vimeo.group(1);
        }
        if (!clean.startsWithIgnoreCase('https://')) {
            throw auraError('Video Embed URL must start with https://.');
        }
        return clean;
    }

    /** Trimmed https URL, null when blank; anything else is rejected by name. */
    @TestVisible
    private static String requireHttps(String url, String label) {
        if (String.isBlank(url)) {
            return null;
        }
        String clean = url.trim();
        if (!clean.startsWithIgnoreCase('https://')) {
            throw auraError(label + ' must start with https://.');
        }
        return clean;
    }

    private static void assertResourceAdmin() {
        if (!Schema.sObjectType.Resource__c.isCreateable()
            || !Schema.sObjectType.Resource__c.isUpdateable()) {
            throw auraError('You do not have access to manage resources.');
        }
    }

    private static void assertCategoryAdmin() {
        if (!Schema.sObjectType.Resource_Category__c.isCreateable()
            || !Schema.sObjectType.Resource_Category__c.isUpdateable()) {
            throw auraError('You do not have access to manage resource categories.');
        }
    }

    private static void assertCategoryReadable() {
        if (!Schema.sObjectType.Resource_Category__c.isAccessible()) {
            throw auraError('You do not have access to resource categories.');
        }
    }

    /** AuraHandledException whose message survives into logs and test output. */
    private static AuraHandledException auraError(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}