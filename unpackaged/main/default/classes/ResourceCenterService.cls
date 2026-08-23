/**
 * ResourceCenterService
 *
 * Read API for the Nexus Resource Center. Context-agnostic: the same methods
 * back both the dedicated LWR Experience Cloud surface and the internal core
 * Lightning App surface.
 *
 * Conventions (mirrors NexSKnowledgeController):
 *  - `with sharing` + explicit isAccessible() guards so we never surface
 *    records the running user can't read.
 *  - Reads are @AuraEnabled(cacheable=true) and return inner DTO wrappers, never
 *    raw SObjects with relationship fields the LWC would have to parse.
 *  - Published/active-only: Is_Active__c = true everywhere user-facing.
 *  - SOSL input is sanitized to an [a-zA-Z0-9 ] allow-list before it is inlined
 *    into a FIND clause, so there is nothing to inject with.
 *  - Knowledge junctions store the version-stable KnowledgeArticleId (KA Id).
 *    getResourcesForArticle receives a Knowledge__kav *version* Id and resolves
 *    it to the KA Id first (versions change on every republish; the KA Id does
 *    not). getRelatedArticlesForResource resolves KA Ids back to the latest
 *    published version for its title/UrlName.
 *  - Bulk-safe: no SOQL inside loops.
 */
public with sharing class ResourceCenterService {

    private static final Integer MAX_SEARCH_RESULTS = 50;
    // Same threshold as NexSKnowledgeController.MIN_PREFIX_LEN — the two search
    // engines should treat short fragments identically; change both together.
    private static final Integer MIN_PREFIX_LEN = 3;
    /** Trailing section order for direct-filed resources (mirrors the Help
        Center's FALLBACK_ORDER_BASE so fallback groups always sort last). */
    // Same "sorts after all real taxonomy" sentinel as the Help Center's
    // nexsArticleBrowser FALLBACK_ORDER_BASE (900) — keep them aligned.
    private static final Integer GENERAL_SECTION_ORDER = 900;
    /** URL name of the Experience Builder page hosting c:resourceCenter. */
    private static final String RESOURCES_PAGE_PATH = 'resources';

    // ---- Wrappers exposed to LWC --------------------------------------------

    public class CategoryTile {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String slug;
        @AuraEnabled public String description;
        @AuraEnabled public String iconName;
        @AuraEnabled public Integer displayOrder;
        @AuraEnabled public Integer subcategoryCount;
        @AuraEnabled public Integer resourceCount;
    }

    public class CategoryDetail {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String slug;
        @AuraEnabled public String description;
        @AuraEnabled public String iconName;
        @AuraEnabled public String parentSlug;
        @AuraEnabled public String parentName;
        @AuraEnabled public List<CategoryTile> subcategories;
        @AuraEnabled public List<ResourceCard> resources;
        @AuraEnabled public List<ResourceSection> sections;
    }

    /**
     * A subtopic grouping on the category page (Help-Center-style section):
     * one per active subcategory with resources, in subcategory order, plus a
     * trailing "General resources" section for resources filed directly on the
     * category — mirroring the Help Center's fallback-after-named convention.
     */
    public class ResourceSection {
        @AuraEnabled public String key;           // subcategory slug, or 'general'
        @AuraEnabled public String title;         // subcategory name, or 'General resources'
        @AuraEnabled public Integer displayOrder; // subcategory position; 900 = trailing General
        @AuraEnabled public List<ResourceCard> resources = new List<ResourceCard>();
    }

    /** Sidebar taxonomy node: a main topic with its non-empty subtopics. */
    public class NavTopic {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String slug;
        @AuraEnabled public String iconName;
        @AuraEnabled public List<NavChild> children = new List<NavChild>();
    }

    public class NavChild {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String slug;
    }

    public class ResourceCard {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String slug;
        @AuraEnabled public String resourceType;
        @AuraEnabled public String description;
        @AuraEnabled public Integer displayOrder;
        @AuraEnabled public Boolean featured;
        @AuraEnabled public String categorySlug;
        @AuraEnabled public String externalUrl;
        @AuraEnabled public String videoEmbedUrl;
        @AuraEnabled public Id contentDocumentId;
        @AuraEnabled public String downloadUrl;
    }

    public class ResourceDetail {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String slug;
        @AuraEnabled public String resourceType;
        @AuraEnabled public String description;
        @AuraEnabled public String videoEmbedUrl;
        @AuraEnabled public String externalUrl;
        @AuraEnabled public Decimal downloadCount;
        @AuraEnabled public String categorySlug;
        @AuraEnabled public String categoryName;
        /** Grandparent crumb segment — null when the category is top-level. */
        @AuraEnabled public String categoryParentSlug;
        @AuraEnabled public String categoryParentName;
        @AuraEnabled public FileInfo file;
        @AuraEnabled public List<RelatedArticle> relatedArticles;
    }

    public class FileInfo {
        @AuraEnabled public Id contentDocumentId;
        @AuraEnabled public String title;
        @AuraEnabled public String fileType;
        @AuraEnabled public Decimal fileSize;      // bytes
        @AuraEnabled public String fileSizeLabel;  // human-readable, e.g. "1.2 MB"
        @AuraEnabled public String downloadUrl;
        /** Per-page SVGZ rendition base (client appends &page=n) — serves inline,
            unlike downloadUrl which is Content-Disposition: attachment. */
        @AuraEnabled public String previewUrl;
        /** Single-image THUMB720BY480 rendition — fallback for plain images. */
        @AuraEnabled public String imagePreviewUrl;
    }

    public class RelatedArticle {
        @AuraEnabled public String knowledgeArticleId;
        @AuraEnabled public String title;
        @AuraEnabled public String urlName;
    }

    /** Unified search row for the combined search bar. */
    public class CombinedResult {
        @AuraEnabled public String type;         // 'resource' | 'article'
        @AuraEnabled public Id id;
        @AuraEnabled public String title;
        @AuraEnabled public String subtitle;
        @AuraEnabled public String slug;         // resource slug (type=resource)
        @AuraEnabled public String urlName;      // article UrlName (type=article)
        @AuraEnabled public String resourceType; // PDF/Form/Video/... (type=resource)
    }

    // ---- Public API: categories ---------------------------------------------

    /** Active top-level categories (Parent = null), ordered, with counts. */
    @AuraEnabled(cacheable=true)
    public static List<CategoryTile> getTopLevelCategories() {
        assertCategoriesReadable();

        // Reference data is small — load every active category once and compute
        // counts in memory rather than firing per-tile aggregates.
        List<Resource_Category__c> all = [
            SELECT Id, Name, Slug__c, Description__c, Icon_Name__c, Display_Order__c, Parent_Category__c
            FROM Resource_Category__c
            WHERE Is_Active__c = true
            ORDER BY Display_Order__c NULLS LAST, Name ASC
        ];

        Map<Id, Integer> childCount = new Map<Id, Integer>();
        List<Resource_Category__c> topLevel = new List<Resource_Category__c>();
        for (Resource_Category__c cat : all) {
            if (cat.Parent_Category__c == null) {
                topLevel.add(cat);
            } else {
                childCount.put(cat.Parent_Category__c,
                    (childCount.containsKey(cat.Parent_Category__c) ? childCount.get(cat.Parent_Category__c) : 0) + 1);
            }
        }

        // Map each category to its top-level ancestor so a resource filed under a
        // subcategory still counts toward the top-level tile.
        Map<Id, Id> topAncestor = new Map<Id, Id>();
        Map<Id, Resource_Category__c> byId = new Map<Id, Resource_Category__c>(all);
        for (Resource_Category__c cat : all) {
            Resource_Category__c cursor = cat;
            Integer guard = 0;
            while (cursor.Parent_Category__c != null && byId.containsKey(cursor.Parent_Category__c) && guard < 10) {
                cursor = byId.get(cursor.Parent_Category__c);
                guard++;
            }
            topAncestor.put(cat.Id, cursor.Id);
        }

        Map<Id, Integer> resourceCount = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Category__c cat, COUNT(Id) c
            FROM Resource__c
            WHERE Is_Active__c = true AND Category__c IN :byId.keySet()
            GROUP BY Category__c
        ]) {
            Id cat = (Id) ar.get('cat');
            Id top = topAncestor.containsKey(cat) ? topAncestor.get(cat) : cat;
            Integer c = (Integer) ar.get('c');
            resourceCount.put(top, (resourceCount.containsKey(top) ? resourceCount.get(top) : 0) + c);
        }

        List<CategoryTile> tiles = new List<CategoryTile>();
        for (Resource_Category__c cat : topLevel) {
            CategoryTile t = toTile(cat);
            t.subcategoryCount = childCount.containsKey(cat.Id) ? childCount.get(cat.Id) : 0;
            t.resourceCount = resourceCount.containsKey(cat.Id) ? resourceCount.get(cat.Id) : 0;
            tiles.add(t);
        }
        return tiles;
    }

    /**
     * Sidebar taxonomy for the public topic nav: every active top-level
     * category (always listed, even when empty), each with its active
     * subcategories that hold at least one active resource — empty subtopics
     * stay out of the public nav. Both levels in Display_Order__c order.
     */
    @AuraEnabled(cacheable=true)
    public static List<NavTopic> getCategoryNav() {
        assertCategoriesReadable();
        List<Resource_Category__c> all = [
            SELECT Id, Name, Slug__c, Icon_Name__c, Parent_Category__c
            FROM Resource_Category__c
            WHERE Is_Active__c = true
            ORDER BY Display_Order__c NULLS LAST, Name ASC
        ];
        Set<Id> allIds = new Map<Id, Resource_Category__c>(all).keySet();
        Set<Id> hasResources = new Set<Id>();
        for (AggregateResult ar : [
            SELECT Category__c cat
            FROM Resource__c
            WHERE Is_Active__c = true AND Category__c IN :allIds
            GROUP BY Category__c
        ]) {
            hasResources.add((Id) ar.get('cat'));
        }

        Map<Id, NavTopic> topById = new Map<Id, NavTopic>();
        List<NavTopic> topics = new List<NavTopic>();
        for (Resource_Category__c cat : all) {
            if (cat.Parent_Category__c == null) {
                NavTopic t = new NavTopic();
                t.id = cat.Id;
                t.name = cat.Name;
                t.slug = cat.Slug__c;
                t.iconName = cat.Icon_Name__c;
                topById.put(cat.Id, t);
                topics.add(t);
            }
        }
        for (Resource_Category__c cat : all) {
            if (cat.Parent_Category__c == null || !hasResources.contains(cat.Id)) {
                continue;
            }
            NavTopic parent = topById.get(cat.Parent_Category__c);
            if (parent == null) {
                continue; // orphan/deep nesting — not part of the two-level nav
            }
            NavChild child = new NavChild();
            child.id = cat.Id;
            child.name = cat.Name;
            child.slug = cat.Slug__c;
            parent.children.add(child);
        }
        return topics;
    }

    /** A category by slug, with its active subcategories and its own resources. */
    @AuraEnabled(cacheable=true)
    public static CategoryDetail getCategoryBySlug(String slug) {
        assertCategoriesReadable();
        if (String.isBlank(slug)) {
            throw new AuraHandledException('No category specified.');
        }
        List<Resource_Category__c> cats = [
            SELECT Id, Name, Slug__c, Description__c, Icon_Name__c, Display_Order__c,
                   Parent_Category__c, Parent_Category__r.Name, Parent_Category__r.Slug__c
            FROM Resource_Category__c
            WHERE Slug__c = :slug AND Is_Active__c = true
            LIMIT 1
        ];
        if (cats.isEmpty()) {
            throw new AuraHandledException('Category not found.');
        }
        Resource_Category__c cat = cats[0];

        CategoryDetail detail = new CategoryDetail();
        detail.id = cat.Id;
        detail.name = cat.Name;
        detail.slug = cat.Slug__c;
        detail.description = cat.Description__c;
        detail.iconName = cat.Icon_Name__c;
        detail.parentSlug = cat.Parent_Category__r != null ? cat.Parent_Category__r.Slug__c : null;
        detail.parentName = cat.Parent_Category__r != null ? cat.Parent_Category__r.Name : null;

        detail.subcategories = new List<CategoryTile>();
        for (Resource_Category__c child : [
            SELECT Id, Name, Slug__c, Description__c, Icon_Name__c, Display_Order__c
            FROM Resource_Category__c
            WHERE Parent_Category__c = :cat.Id AND Is_Active__c = true
            ORDER BY Display_Order__c NULLS LAST, Name ASC
        ]) {
            detail.subcategories.add(toTile(child));
        }

        // One query covers the category's own resources and its subcategories'
        // (inactive subcategories stay hidden, like everywhere user-facing).
        List<Resource__c> resources = [
            SELECT Id, Name, Slug__c, Resource_Type__c, Description__c, Display_Order__c,
                   Is_Featured__c, External_URL__c, Video_Embed_URL__c,
                   Category__c, Category__r.Slug__c
            FROM Resource__c
            WHERE (Category__c = :cat.Id OR Category__r.Parent_Category__c = :cat.Id)
            AND Is_Active__c = true AND Category__r.Is_Active__c = true
            ORDER BY Display_Order__c NULLS LAST, Name ASC
        ];
        List<ResourceCard> allCards = toCards(resources);
        Map<Id, Id> categoryByResource = new Map<Id, Id>();
        for (Resource__c r : resources) {
            categoryByResource.put(r.Id, r.Category__c);
        }

        List<ResourceCard> direct = new List<ResourceCard>();
        Map<Id, List<ResourceCard>> cardsBySubcategory = new Map<Id, List<ResourceCard>>();
        for (ResourceCard card : allCards) {
            Id resourceCat = categoryByResource.get(card.id);
            if (resourceCat == cat.Id) {
                direct.add(card);
            } else {
                if (!cardsBySubcategory.containsKey(resourceCat)) {
                    cardsBySubcategory.put(resourceCat, new List<ResourceCard>());
                }
                cardsBySubcategory.get(resourceCat).add(card);
            }
        }
        detail.resources = direct;

        // Sections: one per subcategory with resources (in subcategory order),
        // then direct-filed resources trail in "General resources".
        detail.sections = new List<ResourceSection>();
        Integer position = 0;
        for (CategoryTile sub : detail.subcategories) {
            position++;
            List<ResourceCard> subCards = cardsBySubcategory.get(sub.id);
            if (subCards == null || subCards.isEmpty()) {
                continue;
            }
            ResourceSection section = new ResourceSection();
            section.key = sub.slug;
            section.title = sub.name;
            section.displayOrder = position;
            section.resources = subCards;
            detail.sections.add(section);
        }
        if (!direct.isEmpty()) {
            ResourceSection general = new ResourceSection();
            general.key = 'general';
            general.title = 'General resources';
            general.displayOrder = GENERAL_SECTION_ORDER;
            general.resources = direct;
            detail.sections.add(general);
        }
        return detail;
    }

    // ---- Public API: resources ----------------------------------------------

    /** Active featured resources for the landing-page strip, ordered. */
    @AuraEnabled(cacheable=true)
    public static List<ResourceCard> getFeaturedResources() {
        assertResourcesReadable();
        return toCards([
            SELECT Id, Name, Slug__c, Resource_Type__c, Description__c, Display_Order__c,
                   Is_Featured__c, External_URL__c, Video_Embed_URL__c, Category__r.Slug__c
            FROM Resource__c
            WHERE Is_Featured__c = true AND Is_Active__c = true
            ORDER BY Display_Order__c NULLS LAST, Name ASC
            LIMIT 12
        ]);
    }

    /** Full resource detail incl. attached file info and related articles. */
    @AuraEnabled(cacheable=true)
    public static ResourceDetail getResourceBySlug(String slug) {
        assertResourcesReadable();
        if (String.isBlank(slug)) {
            throw new AuraHandledException('No resource specified.');
        }
        List<Resource__c> rows = [
            SELECT Id, Name, Slug__c, Resource_Type__c, Description__c, Video_Embed_URL__c,
                   External_URL__c, Download_Count__c, Category__r.Name, Category__r.Slug__c,
                   Category__r.Parent_Category__r.Name, Category__r.Parent_Category__r.Slug__c
            FROM Resource__c
            WHERE Slug__c = :slug AND Is_Active__c = true
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new AuraHandledException('Resource not found.');
        }
        Resource__c r = rows[0];

        ResourceDetail d = new ResourceDetail();
        d.id = r.Id;
        d.name = r.Name;
        d.slug = r.Slug__c;
        d.resourceType = r.Resource_Type__c;
        d.description = r.Description__c;
        d.videoEmbedUrl = r.Video_Embed_URL__c;
        d.externalUrl = r.External_URL__c;
        d.downloadCount = r.Download_Count__c;
        d.categoryName = r.Category__r != null ? r.Category__r.Name : null;
        d.categorySlug = r.Category__r != null ? r.Category__r.Slug__c : null;
        if (r.Category__r != null && r.Category__r.Parent_Category__r != null) {
            d.categoryParentName = r.Category__r.Parent_Category__r.Name;
            d.categoryParentSlug = r.Category__r.Parent_Category__r.Slug__c;
        }
        d.file = fileInfoByResource(new Set<Id>{ r.Id }).get(r.Id);
        d.relatedArticles = getRelatedArticlesForResource(r.Id);
        return d;
    }

    /**
     * Resources linked to a Knowledge article. Accepts the Knowledge__kav
     * *version* Id (what the article page holds) and resolves it to the stable
     * KnowledgeArticleId before querying the junction.
     */
    @AuraEnabled(cacheable=true)
    public static List<ResourceCard> getResourcesForArticle(Id knowledgeArticleVersionId) {
        assertResourcesReadable();
        String kaId = resolveKnowledgeArticleId(knowledgeArticleVersionId);
        if (kaId == null) {
            return new List<ResourceCard>();
        }
        List<Id> resourceIds = new List<Id>();
        Map<Id, Decimal> orderById = new Map<Id, Decimal>();
        for (Article_Resource__c link : [
            SELECT Resource__c, Display_Order__c
            FROM Article_Resource__c
            WHERE Knowledge_Article_Id__c = :kaId AND Resource__r.Is_Active__c = true
            ORDER BY Display_Order__c NULLS LAST
        ]) {
            resourceIds.add(link.Resource__c);
            orderById.put(link.Resource__c, link.Display_Order__c);
        }
        if (resourceIds.isEmpty()) {
            return new List<ResourceCard>();
        }
        List<Resource__c> resources = [
            SELECT Id, Name, Slug__c, Resource_Type__c, Description__c, Display_Order__c,
                   Is_Featured__c, External_URL__c, Video_Embed_URL__c, Category__r.Slug__c
            FROM Resource__c
            WHERE Id IN :resourceIds AND Is_Active__c = true
            ORDER BY Name ASC
        ];
        return toCards(resources);
    }

    /**
     * Articles linked to a resource (reverse direction). Resolves each stored KA
     * Id to its latest published version for the title + UrlName.
     */
    @AuraEnabled(cacheable=true)
    public static List<RelatedArticle> getRelatedArticlesForResource(Id resourceId) {
        List<RelatedArticle> out = new List<RelatedArticle>();
        if (resourceId == null || !Schema.sObjectType.Article_Resource__c.isAccessible()) {
            return out;
        }
        Set<String> kaIds = new Set<String>();
        Map<String, String> fallbackUrlName = new Map<String, String>();
        for (Article_Resource__c link : [
            SELECT Knowledge_Article_Id__c, Article_UrlName__c
            FROM Article_Resource__c
            WHERE Resource__c = :resourceId
            ORDER BY Display_Order__c NULLS LAST
        ]) {
            if (String.isNotBlank(link.Knowledge_Article_Id__c)) {
                kaIds.add(link.Knowledge_Article_Id__c);
                fallbackUrlName.put(link.Knowledge_Article_Id__c, link.Article_UrlName__c);
            }
        }
        if (kaIds.isEmpty() || !Schema.sObjectType.Knowledge__kav.isAccessible()) {
            return out;
        }
        Set<String> resolved = new Set<String>();
        for (Knowledge__kav kav : [
            SELECT KnowledgeArticleId, Title, UrlName
            FROM Knowledge__kav
            WHERE KnowledgeArticleId IN :kaIds
            AND PublishStatus = 'Online' AND IsLatestVersion = true AND Language = 'en_US'
        ]) {
            RelatedArticle a = new RelatedArticle();
            a.knowledgeArticleId = kav.KnowledgeArticleId;
            a.title = kav.Title;
            a.urlName = kav.UrlName;
            out.add(a);
            resolved.add(kav.KnowledgeArticleId);
        }
        return out;
    }

    // ---- Public API: search --------------------------------------------------

    /** SOSL across resource name/description. Active resources only. */
    @AuraEnabled(cacheable=true)
    public static List<ResourceCard> searchResources(String term) {
        assertResourcesReadable();
        String findExpr = buildFind(term);
        if (findExpr == null) {
            return new List<ResourceCard>();
        }
        String sosl =
            'FIND \'' + findExpr + '\' IN ALL FIELDS RETURNING Resource__c(' +
            'Id, Name, Slug__c, Resource_Type__c, Description__c, Display_Order__c, ' +
            'Is_Featured__c, External_URL__c, Video_Embed_URL__c, Category__r.Slug__c ' +
            'WHERE Is_Active__c = true) LIMIT ' + MAX_SEARCH_RESULTS;
        List<List<SObject>> results = Search.query(sosl);
        List<Resource__c> rows = results.isEmpty()
            ? new List<Resource__c>()
            : (List<Resource__c>) results[0];
        return toCards(rows);
    }

    /**
     * Lightweight typeahead for the search bar — SOQL-only (no scoring, no file
     * lookup) so it stays cheap per keystroke. Matches active resources by Name.
     */
    @AuraEnabled(cacheable=true)
    public static List<ResourceCard> typeahead(String term) {
        assertResourcesReadable();
        String clean = term == null ? '' : term.replaceAll('[^a-zA-Z0-9 ]', ' ').trim();
        if (String.isBlank(clean)) {
            return new List<ResourceCard>();
        }
        String pattern = '%' + clean + '%';
        List<ResourceCard> out = new List<ResourceCard>();
        for (Resource__c r : [
            SELECT Id, Name, Slug__c, Resource_Type__c
            FROM Resource__c
            WHERE Is_Active__c = true AND Name LIKE :pattern
            ORDER BY Name ASC
            LIMIT 7
        ]) {
            ResourceCard c = new ResourceCard();
            c.id = r.Id;
            c.name = r.Name;
            c.slug = r.Slug__c;
            c.resourceType = r.Resource_Type__c;
            out.add(c);
        }
        return out;
    }

    /**
     * Combined article + resource search for the Resource Center search bar.
     * Resources open in-site; articles deep-link to the Help Center. If the
     * running user has no Knowledge access, the article side is skipped quietly.
     */
    @AuraEnabled(cacheable=true)
    public static List<CombinedResult> searchAll(String term) {
        List<CombinedResult> out = new List<CombinedResult>();

        for (ResourceCard card : searchResources(term)) {
            CombinedResult cr = new CombinedResult();
            cr.type = 'resource';
            cr.id = card.id;
            cr.title = card.name;
            cr.subtitle = card.description;
            cr.slug = card.slug;
            cr.resourceType = card.resourceType;
            out.add(cr);
        }

        try {
            NexSKnowledgeController.SearchResult sr =
                NexSKnowledgeController.searchRanked(term, null, false);
            if (sr != null && sr.articles != null) {
                for (NexSKnowledgeController.ArticleSummary a : sr.articles) {
                    CombinedResult cr = new CombinedResult();
                    cr.type = 'article';
                    cr.id = a.id;
                    cr.title = a.title;
                    cr.subtitle = a.summary;
                    cr.urlName = a.urlName;
                    out.add(cr);
                }
            }
        } catch (Exception e) {
            // No Knowledge access on this surface — resources-only results.
        }
        return out;
    }

    // ---- Public API: download tracking --------------------------------------

    /**
     * Fire-and-forget download counter. Never throws and never blocks the
     * download — the client navigates to the file URL regardless of the result.
     */
    @AuraEnabled
    public static void trackDownload(Id resourceId) {
        if (resourceId == null) {
            return;
        }
        try {
            System.enqueueJob(new ResourceDownloadTracker(resourceId));
        } catch (Exception e) {
            // Queue limits or similar — analytics-grade, safe to drop.
        }
    }

    // ---- Public API: shareable links -----------------------------------------

    /**
     * Absolute base URL of the Resources page on the Help Center LWR site,
     * e.g. https://…/help/resources — the page hosting c:resourceCenter, which
     * routes on ?rcview/&rcslug. Shared by the Admin Console's "Copy link"
     * actions and the article rail's resource links. Returns null when the site
     * (or its Resources page prefix) can't be resolved; callers fall back
     * gracefully (no copy button / direct file download).
     *
     * The site's URL path prefix comes from Resource_Center_Setting__mdt so the
     * link survives a site rename without a code change.
     */
    @AuraEnabled(cacheable=true)
    public static String getResourceLinkBase() {
        String root = getSiteBaseUrl();
        return root == null ? null : root + '/' + RESOURCES_PAGE_PATH;
    }

    /**
     * Help Center deep-link base — the shared site's root (its home page
     * renders the Help Center). Article links append /?article=<UrlName>;
     * the site has no /article/ route, so nexsLanding resolves the param.
     */
    @AuraEnabled(cacheable=true)
    public static String getHelpCenterLinkBase() {
        return getSiteBaseUrl();
    }

    /** Root SecureUrl of the shared LWR site, or null when unresolvable. */
    private static String getSiteBaseUrl() {
        try {
            Resource_Center_Setting__mdt setting = Resource_Center_Setting__mdt.getInstance('Default');
            String prefix = setting == null || String.isBlank(setting.Site_Url_Path_Prefix__c)
                ? 'help'
                : setting.Site_Url_Path_Prefix__c.trim();
            // LWR Experience sites are SiteType ChatterNetworkPicasso; the
            // sibling ChatterNetwork row is the legacy vforcesite shell.
            List<Site> sites = [
                SELECT Id FROM Site
                WHERE UrlPathPrefix = :prefix AND SiteType = 'ChatterNetworkPicasso'
                LIMIT 1
            ];
            if (sites.isEmpty()) {
                return null;
            }
            List<SiteDetail> details = [
                SELECT SecureUrl FROM SiteDetail WHERE DurableId = :sites[0].Id LIMIT 1
            ];
            if (details.isEmpty() || String.isBlank(details[0].SecureUrl)) {
                return null;
            }
            return details[0].SecureUrl.removeEnd('/');
        } catch (Exception e) {
            return null;
        }
    }

    // ---- Internals -----------------------------------------------------------

    /** Re-query the version Id under the published filter → stable KA Id. */
    private static String resolveKnowledgeArticleId(Id versionId) {
        if (versionId == null || !Schema.sObjectType.Knowledge__kav.isAccessible()) {
            return null;
        }
        List<Knowledge__kav> rows = [
            SELECT KnowledgeArticleId
            FROM Knowledge__kav
            WHERE Id = :versionId AND PublishStatus = 'Online' AND IsLatestVersion = true
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0].KnowledgeArticleId;
    }

    private static CategoryTile toTile(Resource_Category__c cat) {
        CategoryTile t = new CategoryTile();
        t.id = cat.Id;
        t.name = cat.Name;
        t.slug = cat.Slug__c;
        t.description = cat.Description__c;
        t.iconName = cat.Icon_Name__c;
        t.displayOrder = cat.Display_Order__c == null ? null : Integer.valueOf(cat.Display_Order__c);
        t.subcategoryCount = 0;
        t.resourceCount = 0;
        return t;
    }

    private static List<ResourceCard> toCards(List<Resource__c> rows) {
        List<ResourceCard> cards = new List<ResourceCard>();
        if (rows.isEmpty()) {
            return cards;
        }
        Set<Id> ids = new Set<Id>();
        for (Resource__c r : rows) {
            ids.add(r.Id);
        }
        Map<Id, FileInfo> files = fileInfoByResource(ids);
        for (Resource__c r : rows) {
            ResourceCard c = new ResourceCard();
            c.id = r.Id;
            c.name = r.Name;
            c.slug = r.Slug__c;
            c.resourceType = r.Resource_Type__c;
            c.description = r.Description__c;
            c.displayOrder = r.Display_Order__c == null ? null : Integer.valueOf(r.Display_Order__c);
            c.featured = r.Is_Featured__c;
            c.categorySlug = r.Category__r != null ? r.Category__r.Slug__c : null;
            c.externalUrl = r.External_URL__c;
            c.videoEmbedUrl = r.Video_Embed_URL__c;
            FileInfo fi = files.get(r.Id);
            if (fi != null) {
                c.contentDocumentId = fi.contentDocumentId;
                c.downloadUrl = fi.downloadUrl;
            }
            cards.add(c);
        }
        return cards;
    }

    /** Latest attached file per resource, keyed by resource Id. */
    private static Map<Id, FileInfo> fileInfoByResource(Set<Id> resourceIds) {
        Map<Id, FileInfo> out = new Map<Id, FileInfo>();
        Map<Id, Datetime> latestByResource = new Map<Id, Datetime>();
        if (resourceIds == null || resourceIds.isEmpty()) {
            return out;
        }
        for (ContentDocumentLink link : [
            SELECT LinkedEntityId, ContentDocumentId, ContentDocument.Title,
                   ContentDocument.FileExtension, ContentDocument.ContentSize,
                   ContentDocument.CreatedDate, ContentDocument.LatestPublishedVersionId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :resourceIds
        ]) {
            Datetime created = link.ContentDocument.CreatedDate;
            if (latestByResource.containsKey(link.LinkedEntityId)
                && latestByResource.get(link.LinkedEntityId) >= created) {
                continue;
            }
            latestByResource.put(link.LinkedEntityId, created);

            FileInfo fi = new FileInfo();
            fi.contentDocumentId = link.ContentDocumentId;
            fi.title = link.ContentDocument.Title;
            fi.fileType = link.ContentDocument.FileExtension;
            fi.fileSize = link.ContentDocument.ContentSize;
            fi.fileSizeLabel = humanSize(link.ContentDocument.ContentSize);
            fi.downloadUrl = ResourceFileService.buildDownloadUrl(link.ContentDocumentId);
            Id versionId = link.ContentDocument.LatestPublishedVersionId;
            if (versionId != null) {
                fi.previewUrl = '/sfc/servlet.shepherd/version/renditionDownload'
                    + '?rendition=SVGZ&versionId=' + versionId;
                fi.imagePreviewUrl = '/sfc/servlet.shepherd/version/renditionDownload'
                    + '?rendition=THUMB720BY480&versionId=' + versionId;
            }
            out.put(link.LinkedEntityId, fi);
        }
        return out;
    }

    private static String humanSize(Decimal bytes) {
        if (bytes == null) {
            return null;
        }
        if (bytes < 1024) {
            return bytes.setScale(0) + ' B';
        }
        Decimal kb = bytes / 1024;
        if (kb < 1024) {
            return kb.setScale(0) + ' KB';
        }
        Decimal mb = kb / 1024;
        return mb.setScale(1) + ' MB';
    }

    /** Sanitize + tokenize into a SOSL FIND expression, or null when empty. */
    private static String buildFind(String input) {
        String clean = input == null ? '' : input.replaceAll('[^a-zA-Z0-9 ]', ' ').trim();
        if (String.isBlank(clean)) {
            return null;
        }
        List<String> parts = new List<String>();
        for (String token : clean.split('\\s+')) {
            if (String.isBlank(token)) {
                continue;
            }
            parts.add(token.length() >= MIN_PREFIX_LEN ? token + '*' : token);
        }
        return parts.isEmpty() ? null : String.join(parts, ' OR ');
    }

    private static void assertCategoriesReadable() {
        if (!Schema.sObjectType.Resource_Category__c.isAccessible()) {
            throw new AuraHandledException('You do not have access to resource categories.');
        }
    }

    private static void assertResourcesReadable() {
        if (!Schema.sObjectType.Resource__c.isAccessible()) {
            throw new AuraHandledException('You do not have access to resources.');
        }
    }
}