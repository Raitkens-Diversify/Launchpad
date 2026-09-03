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

    // ---- DTOs -------------------------------------------------------------------

    public class ResourceRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String slug;
        @AuraEnabled public String resourceType;
        @AuraEnabled public String categoryName;
        @AuraEnabled public Id categoryId;
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
        @AuraEnabled public String description;
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
        @AuraEnabled public List<ArticleLink> relatedArticles = new List<ArticleLink>();
        @AuraEnabled public List<FileInfo> files = new List<FileInfo>();
    }

    public class ResourceInput {
        @AuraEnabled public Id id;                   // null = create
        @AuraEnabled public String name;
        @AuraEnabled public String slug;
        @AuraEnabled public String description;
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
        @AuraEnabled public List<String> relatedArticleKaIds;
    }

    public class CategoryRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String slug;
        @AuraEnabled public String iconName;
        @AuraEnabled public Decimal displayOrder;
        @AuraEnabled public Id parentId;
        @AuraEnabled public String parentName;
        @AuraEnabled public Boolean active;
        @AuraEnabled public Integer resourceCount;
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
        Datetime now = System.now();
        for (Resource__c r : rows) {
            ResourceRow row = new ResourceRow();
            row.id = r.Id;
            row.name = r.Name;
            row.slug = r.Slug__c;
            row.resourceType = r.Resource_Type__c;
            row.categoryId = r.Category__c;
            row.categoryName = r.Category__r == null ? null : r.Category__r.Name;
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
            SELECT Id, Name, Slug__c, Description__c, Resource_Type__c, Category__c,
                   External_URL__c, Video_Embed_URL__c, Is_Featured__c, Is_Active__c,
                   Display_Order__c, Event_Datetime__c, Registration_URL__c,
                   Event_Duration_Minutes__c, Presenter__c
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
        detail.relatedArticles = relatedArticlesFor(resourceId);
        detail.files = filesFor(resourceId);
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
            throw auraError('Pick a category — resources always live in one.');
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

        Resource__c record = new Resource__c(
            Name = input.name.trim(),
            Slug__c = input.slug.trim(),
            Description__c = input.description,
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
            Presenter__c = isWebinar ? input.presenter : null
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

    @AuraEnabled
    public static List<CategoryRow> listCategories() {
        assertCategoryAdmin();
        Map<Id, Integer> counts = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Category__c cat, COUNT(Id) cnt FROM Resource__c GROUP BY Category__c
        ]) {
            counts.put((Id) ar.get('cat'), (Integer) ar.get('cnt'));
        }
        List<CategoryRow> out = new List<CategoryRow>();
        for (Resource_Category__c c : [
            SELECT Id, Name, Slug__c, Icon_Name__c, Display_Order__c,
                   Parent_Category__c, Parent_Category__r.Name, Is_Active__c
            FROM Resource_Category__c
            ORDER BY Parent_Category__c NULLS FIRST, Display_Order__c ASC NULLS LAST, Name ASC
            LIMIT :LIST_LIMIT
        ]) {
            CategoryRow row = new CategoryRow();
            row.id = c.Id;
            row.name = c.Name;
            row.slug = c.Slug__c;
            row.iconName = c.Icon_Name__c;
            row.displayOrder = c.Display_Order__c;
            row.parentId = c.Parent_Category__c;
            row.parentName = c.Parent_Category__r == null ? null : c.Parent_Category__r.Name;
            row.active = c.Is_Active__c == true;
            Integer cnt = counts.get(c.Id);
            row.resourceCount = cnt == null ? 0 : cnt;
            out.add(row);
        }
        return out;
    }

    /** Two-level tree for the single-select picker in the resource editor. */
    @AuraEnabled
    public static List<CategoryNode> getResourceCategoryTree() {
        assertCategoryReadable();
        Map<Id, CategoryNode> topByid = new Map<Id, CategoryNode>();
        List<CategoryNode> roots = new List<CategoryNode>();
        List<Resource_Category__c> all = [
            SELECT Id, Name, Parent_Category__c, Is_Active__c
            FROM Resource_Category__c
            WHERE Is_Active__c = true
            ORDER BY Display_Order__c ASC NULLS LAST, Name ASC
            LIMIT :LIST_LIMIT
        ];
        for (Resource_Category__c c : all) {
            if (c.Parent_Category__c == null) {
                CategoryNode node = new CategoryNode();
                node.name = c.Id;
                node.label = c.Name;
                topByid.put(c.Id, node);
                roots.add(node);
            }
        }
        for (Resource_Category__c c : all) {
            if (c.Parent_Category__c != null) {
                CategoryNode parent = topByid.get(c.Parent_Category__c);
                CategoryNode node = new CategoryNode();
                node.name = c.Id;
                node.label = c.Name;
                if (parent != null) {
                    parent.children.add(node);
                } else {
                    roots.add(node); // orphan/deep nesting — still selectable
                }
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
        if (input.id != null && input.parentId == input.id) {
            throw auraError('A category cannot be its own parent.');
        }
        if (input.parentId != null) {
            // Two levels only: the parent must itself be top-level, and a
            // category that has subtopics must stay top-level. Together these
            // also make parent cycles impossible.
            List<Resource_Category__c> parents = [
                SELECT Parent_Category__c FROM Resource_Category__c
                WHERE Id = :input.parentId
                LIMIT 1
            ];
            if (parents.isEmpty()) {
                throw auraError('That parent category no longer exists — refresh.');
            }
            if (parents[0].Parent_Category__c != null) {
                throw auraError('Subtopics cannot have their own subtopics — pick a top-level category as the parent.');
            }
            if (input.id != null
                && [SELECT COUNT() FROM Resource_Category__c WHERE Parent_Category__c = :input.id] > 0) {
                throw auraError('This category has subtopics, so it must stay top level.');
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