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
    // Same threshold as NexSKnowledgeController — the two search engines treat
    // short fragments identically. Single source: SearchConstants.
    private static final Integer MIN_PREFIX_LEN = SearchConstants.MIN_PREFIX_LEN;
    /** Trailing section order for direct-filed resources (mirrors the Help
        Center's FALLBACK_ORDER_BASE so fallback groups always sort last). */
    // "Sorts after all real taxonomy" sentinel — single source:
    // SearchConstants.ORDER_SENTINEL (also mirrored by the Help Center's
    // nexsArticleBrowser FALLBACK_ORDER_BASE).
    private static final Integer GENERAL_SECTION_ORDER = SearchConstants.ORDER_SENTINEL;
    /** URL name of the Experience Builder page hosting c:resourceCenter. */
    private static final String RESOURCES_PAGE_PATH = 'resources';

    /** Mirror: NexSArticleEngagementController.resolveSurface() / c/contextNav
        INTERNAL — the core-app sentinel. Change all three together. */
    @TestVisible private static final String INTERNAL_SURFACE = 'Internal';

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
        // Webinar-only (null for every other type) — derived by WebinarLifecycle.
        @AuraEnabled public String webinarStatus;
        @AuraEnabled public Datetime eventDatetime;
        @AuraEnabled public Integer durationMinutes;
        @AuraEnabled public String presenter;
        @AuraEnabled public String registrationUrl;
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
        // Webinar-only (null for every other type) — derived by WebinarLifecycle.
        @AuraEnabled public String webinarStatus;
        @AuraEnabled public Datetime eventDatetime;
        @AuraEnabled public Integer durationMinutes;
        @AuraEnabled public String presenter;
        @AuraEnabled public String registrationUrl;
    }

    /** One agenda row (landing-page panel). Status is server-derived, never re-derived in LWC. */
    public class WebinarItem {
        @AuraEnabled public Id id;
        @AuraEnabled public String slug;
        @AuraEnabled public String name;
        @AuraEnabled public String description;
        /** WebinarLifecycle.UPCOMING | PAST | RECORDED. */
        @AuraEnabled public String status;
        @AuraEnabled public Datetime eventDatetime;
        @AuraEnabled public Integer durationMinutes;
        @AuraEnabled public String presenter;
        @AuraEnabled public String registrationUrl;
        /** True only when Recorded — the agenda's "Watch" CTA keys on this. */
        @AuraEnabled public Boolean watchable;
    }

    /** getWebinars response: both lists empty = the panel hides. */
    public class WebinarAgenda {
        @AuraEnabled public List<WebinarItem> upcoming = new List<WebinarItem>();
        @AuraEnabled public List<WebinarItem> recent = new List<WebinarItem>();
    }

    /** getEvents response: the /help/events feed (also feeds the landing
        banner and nav badge). past holds EVERY past webinar, most recent
        first; `watchable` marks the recorded ones (the events list hides the
        rest, the calendar shows them all). */
    public class EventsFeed {
        @AuraEnabled public List<WebinarItem> upcoming = new List<WebinarItem>();
        @AuraEnabled public List<WebinarItem> past = new List<WebinarItem>();
    }

    /**
     * getLinkContext response — the surface the caller is running on plus the
     * link bases of the pages on THAT site (Help_Surface__mdt). Every base is
     * null in the core app, which is c/contextNav's signal to navigate
     * in-Lightning instead of leaving for a site. helpBase is the site root
     * (contextNav derives the page URLs from it when the page bases are
     * missing); the other four are full page URLs.
     */
    public class LinkContext {
        @AuraEnabled public String surface;       // 'Internal' | the Network Name
        @AuraEnabled public String helpBase;      // site root; null when internal
        @AuraEnabled public String homeBase;      // unifiedLanding page
        @AuraEnabled public String articleBase;   // helpArticlePage page (?name= / ?topic=)
        @AuraEnabled public String resourceBase;  // resourceCenter page (?rcview= …)
        @AuraEnabled public String eventsBase;    // eventsPage page
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

    /**
     * searchAll response. Either side can fail independently (missing object
     * access, a backend fault) — the other side's results still return, with
     * the failed side flagged so the client can tell "no matches" from
     * "couldn't look". Symmetric on purpose: no side is ever silently dropped
     * while the other throws.
     */
    public class CombinedSearch {
        @AuraEnabled public List<CombinedResult> results = new List<CombinedResult>();
        @AuraEnabled public Boolean articlesDegraded = false;
        @AuraEnabled public Boolean resourcesDegraded = false;
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
                   Event_Datetime__c, Registration_URL__c, Event_Duration_Minutes__c, Presenter__c,
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
                   Is_Featured__c, External_URL__c, Video_Embed_URL__c, Category__r.Slug__c,
                   Event_Datetime__c, Registration_URL__c, Event_Duration_Minutes__c, Presenter__c
            FROM Resource__c
            WHERE Is_Featured__c = true AND Is_Active__c = true
            ORDER BY Display_Order__c NULLS LAST, Name ASC
            LIMIT 12
        ]);
    }

    // ---- Public API: webinars -------------------------------------------------

    /** Per-section cap when Webinar_Agenda_Limit__c is blank or non-positive. */
    private static final Integer WEBINAR_AGENDA_DEFAULT_LIMIT = 5;
    /** Test seams: custom metadata can't be written in tests. Null = read the record. */
    @TestVisible private static Boolean webinarAgendaEnabledOverride;
    @TestVisible private static Integer webinarAgendaLimitOverride;

    /**
     * Landing-page agenda: upcoming webinars soonest-first, and recent ones
     * (past or recorded) most-recent-first, each capped by
     * Resource_Center_Setting__mdt.Webinar_Agenda_Limit__c (default 5).
     * Active webinars only.
     *
     * Graceful on every failure path — panel disabled by config, no object
     * access, or a backend fault — all return an empty agenda so the panel
     * hides, mirroring the unified search's per-side degrade: a side panel is
     * never worth an error. The isAccessible pre-check lives INSIDE the try for
     * the same reason as UnifiedSearchService.search.
     */
    @AuraEnabled(cacheable=true)
    public static WebinarAgenda getWebinars() {
        WebinarAgenda out = new WebinarAgenda();
        try {
            if (!webinarAgendaEnabled() || !Schema.sObjectType.Resource__c.isAccessible()) {
                return out;
            }
            Integer cap = webinarAgendaLimit();
            String webinarType = WebinarLifecycle.TYPE_WEBINAR;
            // One instant for both queries and the derivation (see WebinarLifecycle).
            Datetime now = System.now();
            List<Resource__c> upcoming = [
                SELECT Id, Name, Slug__c, Resource_Type__c, Description__c, Video_Embed_URL__c,
                       Event_Datetime__c, Registration_URL__c, Event_Duration_Minutes__c, Presenter__c
                FROM Resource__c
                WHERE Resource_Type__c = :webinarType AND Is_Active__c = true
                AND Event_Datetime__c > :now
                ORDER BY Event_Datetime__c ASC
                LIMIT :cap
            ];
            List<Resource__c> recent = [
                SELECT Id, Name, Slug__c, Resource_Type__c, Description__c, Video_Embed_URL__c,
                       Event_Datetime__c, Registration_URL__c, Event_Duration_Minutes__c, Presenter__c
                FROM Resource__c
                WHERE Resource_Type__c = :webinarType AND Is_Active__c = true
                AND Event_Datetime__c <= :now
                ORDER BY Event_Datetime__c DESC
                LIMIT :cap
            ];
            // Recording presence only matters for the recent side.
            Set<Id> recentIds = new Set<Id>();
            for (Resource__c r : recent) {
                recentIds.add(r.Id);
            }
            Map<Id, FileInfo> files = recentIds.isEmpty()
                ? new Map<Id, FileInfo>() : fileInfoByResource(recentIds);
            for (Resource__c r : upcoming) {
                out.upcoming.add(toWebinarItem(r, false, now));
            }
            for (Resource__c r : recent) {
                out.recent.add(toWebinarItem(r, files.containsKey(r.Id), now));
            }
            return out;
        } catch (Exception e) {
            return new WebinarAgenda();
        }
    }

    private static Boolean webinarAgendaEnabled() {
        if (webinarAgendaEnabledOverride != null) {
            return webinarAgendaEnabledOverride;
        }
        Resource_Center_Setting__mdt setting = Resource_Center_Setting__mdt.getInstance('Default');
        // Blank/unchecked hides — the house convention for every flag on this record.
        return setting != null && setting.Webinar_Agenda_Enabled__c == true;
    }

    private static Integer webinarAgendaLimit() {
        Decimal raw = webinarAgendaLimitOverride;
        if (raw == null) {
            Resource_Center_Setting__mdt setting = Resource_Center_Setting__mdt.getInstance('Default');
            raw = setting == null ? null : setting.Webinar_Agenda_Limit__c;
        }
        return (raw == null || raw <= 0) ? WEBINAR_AGENDA_DEFAULT_LIMIT : Integer.valueOf(raw);
    }

    private static WebinarItem toWebinarItem(Resource__c r, Boolean hasFile, Datetime now) {
        WebinarItem w = new WebinarItem();
        w.id = r.Id;
        w.slug = r.Slug__c;
        w.name = r.Name;
        w.description = r.Description__c;
        w.status = WebinarLifecycle.statusFor(r, hasFile, now);
        w.eventDatetime = r.Event_Datetime__c;
        w.durationMinutes = r.Event_Duration_Minutes__c == null
            ? null : Integer.valueOf(r.Event_Duration_Minutes__c);
        w.presenter = r.Presenter__c;
        w.registrationUrl = r.Registration_URL__c;
        w.watchable = (w.status == WebinarLifecycle.RECORDED);
        return w;
    }

    /** Per-side row cap for the events feed — a page, not a panel, so it is
        deliberately independent of Webinar_Agenda_Limit__c. Generous because
        the calendar view renders the whole active set client-side. */
    private static final Integer EVENTS_FEED_LIMIT = 200;

    /**
     * Events-page feed — the ONE source for every events surface: every
     * upcoming webinar soonest-first, and every past webinar most recent
     * first with `watchable` flagging the recorded ones. Feeds /help/events
     * (the Upcoming list hides unrecorded past rows client-side; the Calendar
     * view shows them all) plus the landing banner (upcoming[0]) and nav
     * badge (upcoming.size()).
     *
     * Deliberately NOT gated by Webinar_Agenda_Enabled__c — that flag hides
     * the landing side panel; a routed destination page must not vanish with
     * it. Same graceful degrade as getWebinars: any failure returns an empty
     * feed and the page shows its empty state.
     *
     * Volume note: webinars number in the tens, so the client groups the
     * whole feed by month. The upgrade path if that ever changes is a
     * range-fetching overload — getEvents(Datetime fromDt, Datetime toDt)
     * bound to the displayed month — keeping this DTO shape; not built yet
     * on purpose. The two queries stay split by side (future ASC / past
     * DESC) so each cap truncates the FAR end of its own side rather than a
     * single ascending cap truncating the future first.
     */
    @AuraEnabled(cacheable=true)
    public static EventsFeed getEvents() {
        EventsFeed out = new EventsFeed();
        try {
            if (!Schema.sObjectType.Resource__c.isAccessible()) {
                return out;
            }
            String webinarType = WebinarLifecycle.TYPE_WEBINAR;
            // One instant for both queries and the derivation (see WebinarLifecycle).
            Datetime now = System.now();
            List<Resource__c> upcoming = [
                SELECT Id, Name, Slug__c, Resource_Type__c, Description__c, Video_Embed_URL__c,
                       Event_Datetime__c, Registration_URL__c, Event_Duration_Minutes__c, Presenter__c
                FROM Resource__c
                WHERE Resource_Type__c = :webinarType AND Is_Active__c = true
                AND Event_Datetime__c > :now
                ORDER BY Event_Datetime__c ASC
                LIMIT :EVENTS_FEED_LIMIT
            ];
            List<Resource__c> past = [
                SELECT Id, Name, Slug__c, Resource_Type__c, Description__c, Video_Embed_URL__c,
                       Event_Datetime__c, Registration_URL__c, Event_Duration_Minutes__c, Presenter__c
                FROM Resource__c
                WHERE Resource_Type__c = :webinarType AND Is_Active__c = true
                AND Event_Datetime__c <= :now
                ORDER BY Event_Datetime__c DESC
                LIMIT :EVENTS_FEED_LIMIT
            ];
            Set<Id> pastIds = new Set<Id>();
            for (Resource__c r : past) {
                pastIds.add(r.Id);
            }
            Map<Id, FileInfo> files = pastIds.isEmpty()
                ? new Map<Id, FileInfo>() : fileInfoByResource(pastIds);
            for (Resource__c r : upcoming) {
                out.upcoming.add(toWebinarItem(r, false, now));
            }
            for (Resource__c r : past) {
                // Unrecorded past rows are kept: `watchable` tells the client
                // which ones have something to play.
                out.past.add(toWebinarItem(r, files.containsKey(r.Id), now));
            }
            return out;
        } catch (Exception e) {
            return new EventsFeed();
        }
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
                   Event_Datetime__c, Registration_URL__c, Event_Duration_Minutes__c, Presenter__c,
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
        d.eventDatetime = r.Event_Datetime__c;
        d.durationMinutes = r.Event_Duration_Minutes__c == null
            ? null : Integer.valueOf(r.Event_Duration_Minutes__c);
        d.presenter = r.Presenter__c;
        d.registrationUrl = r.Registration_URL__c;
        d.webinarStatus = WebinarLifecycle.statusFor(r, d.file != null, System.now());
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
        // Junction order IS the curated order — resources render in this
        // sequence, so keep it through the detail query below.
        List<Id> resourceIds = new List<Id>();
        for (Article_Resource__c link : [
            SELECT Resource__c
            FROM Article_Resource__c
            WHERE Knowledge_Article_Id__c = :kaId AND Resource__r.Is_Active__c = true
            ORDER BY Display_Order__c NULLS LAST, Resource__r.Name ASC
        ]) {
            resourceIds.add(link.Resource__c);
        }
        if (resourceIds.isEmpty()) {
            return new List<ResourceCard>();
        }
        Map<Id, Resource__c> byId = new Map<Id, Resource__c>([
            SELECT Id, Name, Slug__c, Resource_Type__c, Description__c, Display_Order__c,
                   Is_Featured__c, External_URL__c, Video_Embed_URL__c, Category__r.Slug__c,
                   Event_Datetime__c, Registration_URL__c, Event_Duration_Minutes__c, Presenter__c
            FROM Resource__c
            WHERE Id IN :resourceIds AND Is_Active__c = true
        ]);
        List<Resource__c> ordered = new List<Resource__c>();
        for (Id rid : resourceIds) {
            Resource__c r = byId.remove(rid); // remove() also dedupes double-links
            if (r != null) {
                ordered.add(r);
            }
        }
        return toCards(ordered);
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
            'Is_Featured__c, External_URL__c, Video_Embed_URL__c, Category__r.Slug__c, ' +
            'Event_Datetime__c, Registration_URL__c, Event_Duration_Minutes__c, Presenter__c ' +
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
     * DEPRECATED (2026-08-21, HC/RC unification): superseded by
     * UnifiedSearchService.search, which returns grouped + scored sides. No
     * LWC consumes this any more (resourceSearchResults repointed); kept one
     * release for any org-side caller, then remove along with CombinedSearch/
     * CombinedResult.
     *
     * Combined article + resource search. Each side degrades independently
     * (see CombinedSearch) so a user with access to only one dataset still
     * gets that dataset's results.
     */
    @AuraEnabled(cacheable=true)
    public static CombinedSearch searchAll(String term) {
        CombinedSearch out = new CombinedSearch();

        try {
            for (ResourceCard card : searchResources(term)) {
                CombinedResult cr = new CombinedResult();
                cr.type = 'resource';
                cr.id = card.id;
                cr.title = card.name;
                cr.subtitle = card.description;
                cr.slug = card.slug;
                cr.resourceType = card.resourceType;
                out.results.add(cr);
            }
        } catch (Exception e) {
            out.resourcesDegraded = true;
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
                    out.results.add(cr);
                }
            }
        } catch (Exception e) {
            out.articlesDegraded = true;
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

    /**
     * Resolves the actual download URL at click time rather than reusing the
     * one baked into the cacheable resource/detail read (which is only ever
     * an authenticated Shepherd URL — see ResourceFileService). Non-cacheable
     * because creating the ContentDistribution behind a public link is DML.
     */
    @AuraEnabled
    public static String getResourceDownloadUrl(Id contentDocumentId) {
        return ResourceFileService.resolvePublicDownloadUrl(contentDocumentId);
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
        String root = getHelpCenterLinkBase();
        return root == null ? null : root + '/' + RESOURCES_PAGE_PATH;
    }

    /**
     * Help Center deep-link base — the shared site's root (its home page
     * renders the unified landing). Article links append /article?name=<UrlName>
     * (c/rcLinkUtil.articleUrl); the legacy /?article= form still resolves via
     * the home route's shim, but is never built for new links.
     *
     * Site-absolute everywhere EXCEPT on the Help Center site itself (2026-09-04):
     * a caller running on /help gets the site-relative root ('/help'), so a
     * link built from it stays a same-site hop instead of a host-absolute one.
     * Off-site callers stay absolute on purpose — the Admin Console's "Copy
     * link" actions share these with people who may be external, and ARC's
     * sidebar (arcNavigation) needs the other site's full URL. Callers that
     * need per-page routing use getLinkContext() instead.
     */
    @AuraEnabled(cacheable=true)
    public static String getHelpCenterLinkBase() {
        if (onHelpSite()) {
            return '/' + helpPrefix().removeStart('/').removeEnd('/');
        }
        return getSiteBaseUrl();
    }

    /** Test seam: the Help Center site's MasterLabel without a real Site row. */
    @TestVisible private static String helpSiteLabelOverride;

    /** True when the CURRENT network IS the shared Help Center site
        (Network.Name == the site's MasterLabel, the same convention
        currentSiteBaseUrl relies on). Never throws. */
    private static Boolean onHelpSite() {
        String surface = surfaceOverride != null
            ? surfaceOverride
            : NexSArticleEngagementController.resolveSurface();
        if (surface == null || surface == INTERNAL_SURFACE) {
            return false;
        }
        String label = helpSiteLabelOverride;
        if (label == null) {
            try {
                String prefix = helpPrefix();
                List<Site> sites = [
                    SELECT MasterLabel FROM Site
                    WHERE UrlPathPrefix = :prefix AND SiteType = 'ChatterNetworkPicasso'
                    LIMIT 1
                ];
                label = sites.isEmpty() ? null : sites[0].MasterLabel;
            } catch (Exception e) {
                return false;
            }
        }
        return label != null && label == surface;
    }

    /**
     * Surface + link bases in one call, for c/contextNav.
     *
     * In the core app Network.getNetworkId() is null, so every base comes back
     * null and contextNav routes with NavigationMixin instead of leaving for
     * *.my.site.com.
     *
     * On an Experience Cloud site the bases are the CURRENT site's pages: the
     * network's Help_Surface__mdt row names the page segments and the site's
     * own SecureUrl is the root — so a user on ARC stays on ARC (another site
     * means another login). A network with no row, or whose site can't be
     * resolved, gets the shared Help Center site with the default page names,
     * exactly what every caller received before the table existed.
     *
     * Never throws — an unresolvable site degrades to null bases, which the
     * client already treats as "handle it in-app".
     */
    @AuraEnabled(cacheable=true)
    public static LinkContext getLinkContext() {
        LinkContext ctx = new LinkContext();
        ctx.surface = surfaceOverride != null
            ? surfaceOverride
            : NexSArticleEngagementController.resolveSurface();
        if (ctx.surface == INTERNAL_SURFACE) {
            return ctx; // bases stay null — navigate in-Lightning
        }
        Help_Surface__mdt route = surfaceRoutes().get(ctx.surface);
        String base = route == null ? null : currentSiteBaseUrl(ctx.surface);
        if (base == null) {
            route = null;               // shared site, default page names
            base = getSiteBaseUrl();
        }
        if (base == null) {
            return ctx;                 // unresolvable everywhere — in-app
        }
        ctx.helpBase = base;
        ctx.homeBase = pageUrl(base, route == null ? null : route.Home_Path__c, '');
        ctx.articleBase = pageUrl(base, route == null ? null : route.Article_Path__c, 'article');
        ctx.resourceBase = pageUrl(base, route == null ? null : route.Resources_Path__c, RESOURCES_PAGE_PATH);
        ctx.eventsBase = pageUrl(base, route == null ? null : route.Events_Path__c, 'events');
        return ctx;
    }

    /** Test seams: force the surface / a site root without a real Network. */
    @TestVisible private static String surfaceOverride;
    @TestVisible private static Map<String, String> siteBaseOverride = new Map<String, String>();
    /** Help_Surface__mdt by Network name; @TestVisible so tests can seed it. */
    @TestVisible private static Map<String, Help_Surface__mdt> surfaceRows;

    private static Map<String, Help_Surface__mdt> surfaceRoutes() {
        if (surfaceRows == null) {
            surfaceRows = new Map<String, Help_Surface__mdt>();
            for (Help_Surface__mdt row : [
                SELECT Network_Name__c, Home_Path__c, Article_Path__c, Resources_Path__c, Events_Path__c
                FROM Help_Surface__mdt
            ]) {
                if (String.isNotBlank(row.Network_Name__c)) {
                    surfaceRows.put(row.Network_Name__c.trim(), row);
                }
            }
        }
        return surfaceRows;
    }

    /** base + '/' + segment; a blank segment means the given default, and a
        blank default means the root itself. */
    private static String pageUrl(String base, String segment, String dflt) {
        String p = String.isBlank(segment) ? dflt : segment.trim();
        p = p.removeStart('/').removeEnd('/');
        return String.isBlank(p) ? base : base + '/' + p;
    }

    /**
     * Root SecureUrl of the LWR site behind the CURRENT network, or null.
     * Network.Name equals the site's MasterLabel; the LWR row is the
     * ChatterNetworkPicasso one (the ChatterNetwork sibling is the legacy
     * vforcesite shell).
     */
    private static String currentSiteBaseUrl(String networkName) {
        if (siteBaseOverride.containsKey(networkName)) {
            return siteBaseOverride.get(networkName);
        }
        try {
            List<Site> sites = [
                SELECT Id FROM Site
                WHERE MasterLabel = :networkName AND SiteType = 'ChatterNetworkPicasso'
                LIMIT 1
            ];
            return sites.isEmpty() ? null : secureUrlOf(sites[0].Id);
        } catch (Exception e) {
            return null;
        }
    }

    /** Root SecureUrl of the shared LWR site, or null when unresolvable. */
    private static String getSiteBaseUrl() {
        return siteBaseUrlForPrefix(helpPrefix());
    }

    /** URL path prefix of the shared Help Center site (Resource_Center_Setting__mdt). */
    private static String helpPrefix() {
        Resource_Center_Setting__mdt setting = Resource_Center_Setting__mdt.getInstance('Default');
        return setting == null || String.isBlank(setting.Site_Url_Path_Prefix__c)
            ? 'help'
            : setting.Site_Url_Path_Prefix__c.trim();
    }

    /** URL path prefix of the ARC site (Resource_Center_Setting__mdt); blank → 'ARC'. */
    private static String arcPrefix() {
        Resource_Center_Setting__mdt setting = Resource_Center_Setting__mdt.getInstance('Default');
        Object v = setting == null ? null : setting.getPopulatedFieldsAsMap().get('Arc_Site_Url_Path_Prefix__c');
        return v instanceof String && String.isNotBlank((String) v) ? ((String) v).trim() : 'ARC';
    }

    /** Root SecureUrl of the LWR site at `prefix`, or null when unresolvable. */
    private static String siteBaseUrlForPrefix(String prefix) {
        try {
            // LWR Experience sites are SiteType ChatterNetworkPicasso; the
            // sibling ChatterNetwork row is the legacy vforcesite shell.
            List<Site> sites = [
                SELECT Id FROM Site
                WHERE UrlPathPrefix = :prefix AND SiteType = 'ChatterNetworkPicasso'
                LIMIT 1
            ];
            return sites.isEmpty() ? null : secureUrlOf(sites[0].Id);
        } catch (Exception e) {
            return null;
        }
    }

    // ---- Public API: ARC bridge ----------------------------------------------

    /** getArcBridge response: where "Back to ARC" goes and whether the viewer
        belongs there. */
    public class ArcBridge {
        @AuraEnabled public String siteUrl;   // ARC site root; null when unresolvable
        @AuraEnabled public Boolean isMember; // viewer is a member of ARC's network
    }

    /** Test seams: the ARC site root / membership without real Site or NetworkMember rows. */
    @TestVisible private static String arcSiteBaseOverride;
    @TestVisible private static Boolean arcMemberOverride;

    /**
     * The ARC site's root URL plus whether the current user is a member of its
     * network, for c/helpReturnLink ("Back to ARC" in the /help site header).
     * The prefix comes from Resource_Center_Setting__mdt so a site rename is a
     * record edit. Never throws — no link is the safe default (a guest on the
     * login page, a blocked NetworkMember query).
     */
    @AuraEnabled(cacheable=true)
    public static ArcBridge getArcBridge() {
        ArcBridge bridge = new ArcBridge();
        bridge.isMember = false;
        try {
            String prefix = arcPrefix();
            bridge.siteUrl = arcSiteBaseOverride != null ? arcSiteBaseOverride : siteBaseUrlForPrefix(prefix);
            bridge.isMember = arcMemberOverride != null ? arcMemberOverride : isMemberOfSiteWithPrefix(prefix);
        } catch (Exception e) {
            // Leave siteUrl / isMember at their safe defaults.
        }
        return bridge;
    }

    /** Site.MasterLabel == Network.Name (the same convention currentSiteBaseUrl
        relies on), then NetworkMember for the running user. */
    private static Boolean isMemberOfSiteWithPrefix(String prefix) {
        List<Site> sites = [
            SELECT MasterLabel FROM Site
            WHERE UrlPathPrefix = :prefix AND SiteType = 'ChatterNetworkPicasso'
            LIMIT 1
        ];
        if (sites.isEmpty()) {
            return false;
        }
        List<Network> networks = [SELECT Id FROM Network WHERE Name = :sites[0].MasterLabel LIMIT 1];
        if (networks.isEmpty()) {
            return false;
        }
        Id userId = UserInfo.getUserId();
        return [SELECT COUNT() FROM NetworkMember WHERE NetworkId = :networks[0].Id AND MemberId = :userId] > 0;
    }

    private static String secureUrlOf(Id siteId) {
        List<SiteDetail> details = [
            SELECT SecureUrl FROM SiteDetail WHERE DurableId = :siteId LIMIT 1
        ];
        if (details.isEmpty() || String.isBlank(details[0].SecureUrl)) {
            return null;
        }
        return details[0].SecureUrl.removeEnd('/');
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
        Datetime now = System.now();
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
            c.eventDatetime = r.Event_Datetime__c;
            c.durationMinutes = r.Event_Duration_Minutes__c == null
                ? null : Integer.valueOf(r.Event_Duration_Minutes__c);
            c.presenter = r.Presenter__c;
            c.registrationUrl = r.Registration_URL__c;
            c.webinarStatus = WebinarLifecycle.statusFor(r, fi != null, now);
            cards.add(c);
        }
        return cards;
    }

    /**
     * Latest attached file per resource, keyed by resource Id — the ONE
     * "newest file wins" lookup. Public so ResourceAdminController and
     * UnifiedSearchService derive webinar recording presence from the same
     * rule the public pages serve.
     */
    public static Map<Id, FileInfo> fileInfoByResource(Set<Id> resourceIds) {
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