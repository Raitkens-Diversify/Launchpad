/**
 * ResourceCenterServiceTest
 *
 * Prerequisites (as in NexSKnowledgeControllerTest): Lightning Knowledge enabled
 * in the org so Knowledge__kav can be created and published.
 */
@isTest
private class ResourceCenterServiceTest {

    @TestSetup
    static void setup() {
        HelpCenterTestDataFactory.grantAdminToRunningUser();
        Resource_Category__c marketing = new Resource_Category__c(
            Name = 'Marketing', Slug__c = 'marketing', Description__c = 'Marketing assets',
            Icon_Name__c = 'utility:campaign', Display_Order__c = 1, Is_Active__c = true);
        insert marketing;

        Resource_Category__c flyers = new Resource_Category__c(
            Name = 'Flyers', Slug__c = 'flyers', Parent_Category__c = marketing.Id,
            Display_Order__c = 1, Is_Active__c = true);
        Resource_Category__c inactive = new Resource_Category__c(
            Name = 'Hidden', Slug__c = 'hidden', Is_Active__c = false);
        insert new List<Resource_Category__c>{ flyers, inactive };

        Resource__c pdf = new Resource__c(
            Name = 'Brand Flyer', Slug__c = 'brand-flyer', Category__c = flyers.Id,
            Resource_Type__c = 'PDF', Description__c = 'A printable flyer',
            Is_Featured__c = true, Is_Active__c = true, Display_Order__c = 1);
        Resource__c link = new Resource__c(
            Name = 'Partner Site', Slug__c = 'partner-site', Category__c = marketing.Id,
            Resource_Type__c = 'External Link', External_URL__c = 'https://example.com',
            Is_Active__c = true, Display_Order__c = 2);
        insert new List<Resource__c>{ pdf, link };

        // Attach a file to the PDF resource via ContentDocumentLink.
        ContentVersion cv = new ContentVersion(
            Title = 'Brand Flyer.pdf', PathOnClient = 'Brand Flyer.pdf',
            VersionData = Blob.valueOf('%PDF-1.4 fake'));
        insert cv;
        Id cdId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
        insert new ContentDocumentLink(
            LinkedEntityId = pdf.Id, ContentDocumentId = cdId, ShareType = 'V', Visibility = 'AllUsers');
    }

    private static Id resourceId(String slug) {
        return [SELECT Id FROM Resource__c WHERE Slug__c = :slug LIMIT 1].Id;
    }

    /** The real ARC row shape, flagged default, on a seeded site root. */
    private static Help_Surface__mdt arcRow(Boolean isDefault) {
        return new Help_Surface__mdt(
            DeveloperName = 'ARC', Network_Name__c = 'Arc', Is_Default__c = isDefault,
            Home_Path__c = 'help-center', Article_Path__c = 'article',
            Resources_Path__c = 'learning', Events_Path__c = 'events');
    }
    private static void seedArcAsDefault() {
        ResourceCenterService.surfaceRows = new Map<String, Help_Surface__mdt>{
            ResourceCenterService.surfaceKey('Arc') => arcRow(true)
        };
        ResourceCenterService.siteBaseOverride.put('Arc', 'https://arc.example');
    }

    /**
     * Knowledge__kav DML and KbManagement.PublishingService calls require the
     * Knowledge User feature license, which no admin in this org carries.
     * Run the whole test as a dedicated user who has it. Insert happens inside
     * runAs(currentUser()) so the setup-object DML (User) doesn't mix with the
     * @TestSetup data already committed in this test.
     */
    private static User makeKnowledgeUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        User u = new User(
            Alias = 'kbuser', Email = 'kbuser@example.com', EmailEncodingKey = 'UTF-8',
            LastName = 'Knowledge', LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US',
            ProfileId = p.Id, TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'kbuser.' + Datetime.now().getTime() + Math.round(Math.random() * 100000) + '@example.com',
            UserPermissionsKnowledgeUser = true
        );
        System.runAs(HelpCenterTestDataFactory.currentUser()) {
            insert u;
        }
        return u;
    }

    @isTest
    static void topLevelCategoriesRollUpCounts() {
        Test.startTest();
        List<ResourceCenterService.CategoryTile> tiles = ResourceCenterService.getTopLevelCategories();
        Test.stopTest();

        Assert.areEqual(1, tiles.size(), 'Only Marketing is top-level and active.');
        ResourceCenterService.CategoryTile marketing = tiles[0];
        Assert.areEqual('marketing', marketing.slug, 'Expected the marketing tile.');
        Assert.areEqual(1, marketing.subcategoryCount, 'Flyers is its one active child.');
        Assert.areEqual(2, marketing.resourceCount,
            'One resource in Marketing + one in its Flyers subcategory roll up to 2.');
    }

    @isTest
    static void categoryBySlugReturnsChildrenAndResources() {
        Test.startTest();
        ResourceCenterService.CategoryDetail marketing = ResourceCenterService.getCategoryBySlug('marketing');
        ResourceCenterService.CategoryDetail flyers = ResourceCenterService.getCategoryBySlug('flyers');
        Test.stopTest();

        Assert.areEqual(1, marketing.subcategories.size(), 'Flyers is a subcategory of Marketing.');
        Assert.areEqual(1, marketing.resources.size(), 'The External Link sits directly under Marketing.');
        Assert.areEqual('marketing', flyers.parentSlug, 'Flyers reports Marketing as parent.');
        Assert.areEqual(1, flyers.resources.size(), 'The PDF sits under Flyers.');
    }

    @isTest
    static void categoryNavListsTopicsAndNonEmptyChildren() {
        Id marketingId = [SELECT Id FROM Resource_Category__c WHERE Slug__c = 'marketing'].Id;
        // Empty active subcategory: hidden from the nav. Empty active top-level:
        // still listed (main topics always show).
        insert new List<Resource_Category__c>{
            new Resource_Category__c(
                Name = 'Empty Sub', Slug__c = 'empty-sub', Parent_Category__c = marketingId,
                Display_Order__c = 2, Is_Active__c = true),
            new Resource_Category__c(
                Name = 'Empty Top', Slug__c = 'empty-top', Display_Order__c = 9, Is_Active__c = true)
        };

        Test.startTest();
        CategoryTreeService.TreeDTO tree = ResourceCenterService.getCategoryTree();
        Test.stopTest();

        Map<String, CategoryTreeService.TreeNode> bySlug = rootsBySlug(tree);
        Assert.isTrue(bySlug.containsKey('marketing'), 'Marketing is a nav topic.');
        Assert.isTrue(bySlug.containsKey('empty-top'),
            'A main topic with no resources still shows in the nav.');
        Assert.isFalse(bySlug.containsKey('hidden'), 'Inactive categories never show.');
        Assert.isTrue(tree.maxDepth >= 2, 'The limit travels with the tree.');

        CategoryTreeService.TreeNode marketing = bySlug.get('marketing');
        Assert.areEqual(1, marketing.children.size(),
            'Only Flyers qualifies — the empty subcategory is hidden from the nav.');
        Assert.areEqual('flyers', marketing.children[0].slug);
        Assert.areEqual(2, marketing.children[0].depth);
        Assert.areEqual(2, marketing.descendantItemCount, 'Counts roll up to the topic.');
        Assert.areEqual(0, bySlug.get('empty-top').children.size());
        Assert.isFalse(bySlug.get('empty-top').hasChildren);
    }

    private static Map<String, CategoryTreeService.TreeNode> rootsBySlug(CategoryTreeService.TreeDTO tree) {
        Map<String, CategoryTreeService.TreeNode> bySlug = new Map<String, CategoryTreeService.TreeNode>();
        for (CategoryTreeService.TreeNode t : tree.roots) {
            bySlug.put(t.slug, t);
        }
        return bySlug;
    }

    private static List<String> childSlugs(CategoryTreeService.TreeNode node) {
        List<String> out = new List<String>();
        for (CategoryTreeService.TreeNode c : node.children) {
            out.add(c.slug);
        }
        return out;
    }

    @isTest
    static void deepCategoryPagesGroupDescendantsAndScopeSearch() {
        Id flyersId = categoryId('flyers');
        Id printId = makeSub('Print', 'print', flyersId, 1);       // depth 3
        insert new Resource__c(
            Name = 'Deep Poster', Slug__c = 'deep-poster', Category__c = printId,
            Resource_Type__c = 'PDF', Is_Active__c = true, Display_Order__c = 5);

        Test.setFixedSearchResults(new List<Id>{ resourceId('brand-flyer'), resourceId('partner-site'), resourceId('deep-poster') });
        Test.startTest();
        ResourceCenterService.CategoryDetail marketing = ResourceCenterService.getCategoryBySlug('marketing');
        ResourceCenterService.CategoryDetail flyers = ResourceCenterService.getCategoryBySlug('flyers');
        ResourceCenterService.CategoryDetail print = ResourceCenterService.getCategoryBySlug('print');
        ResourceCenterService.ResourceDetail poster = ResourceCenterService.getResourceBySlug('deep-poster');
        List<ResourceCenterService.ResourceCard> scoped = ResourceCenterService.searchResources('x', 'flyers');
        List<ResourceCenterService.ResourceCard> unscoped = ResourceCenterService.searchResources('x', null);
        List<ResourceCenterService.ResourceCard> ahead = ResourceCenterService.typeahead('e', 'flyers');
        Test.stopTest();

        // Marketing page: the Flyers section holds the whole Flyers subtree.
        Assert.areEqual(new List<String>{ 'brand-flyer', 'deep-poster' }, slugs(marketing.sections[0].resources),
            'A grandchild resource groups under the child it hangs from.');
        Assert.areEqual(1, marketing.subcategories.size(), 'Tiles stay direct children only.');
        Assert.areEqual(2, marketing.subcategories[0].resourceCount, 'Tile count covers the subtree.');
        Assert.isTrue(marketing.hasChildren);
        Assert.areEqual(1, marketing.depth);

        // Flyers page: now a branch — Print section + General for its own resource.
        Assert.isTrue(flyers.hasChildren);
        Assert.areEqual(2, flyers.depth);
        Assert.areEqual(new List<String>{ 'print', 'general' },
            new List<String>{ flyers.sections[0].key, flyers.sections[1].key });
        Assert.areEqual(1, flyers.ancestors.size());
        Assert.areEqual('marketing', flyers.ancestors[0].slug);
        Assert.areEqual('marketing', flyers.parentSlug, 'Nearest ancestor still exposed.');

        // Print page: leaf at depth 3 with the full crumb chain.
        Assert.isFalse(print.hasChildren);
        Assert.areEqual(3, print.depth);
        Assert.areEqual(new List<String>{ 'marketing', 'flyers' },
            new List<String>{ print.ancestors[0].slug, print.ancestors[1].slug });
        Assert.areEqual('flyers', print.parentSlug);
        Assert.areEqual(new List<String>{ 'deep-poster' }, slugs(print.resources));

        // Resource detail carries the home category's ancestors, root-first.
        Assert.areEqual('print', poster.categorySlug);
        Assert.areEqual(2, poster.categoryAncestors.size());
        Assert.areEqual('marketing', poster.categoryAncestors[0].slug);
        Assert.areEqual('Flyers', poster.categoryAncestors[1].name);

        // Search scoped to a mid-level node returns its descendants' items only.
        Assert.areEqual(new Set<String>{ 'brand-flyer', 'deep-poster' }, new Set<String>(slugs(scoped)),
            'Scoped search keeps the subtree, drops the sibling branch.');
        Assert.areEqual(3, unscoped.size(), 'No scope = everything.');
        Assert.areEqual(new Set<String>{ 'brand-flyer', 'deep-poster' }, new Set<String>(slugs(ahead)),
            'Typeahead honours the same scope.');
        Assert.areEqual(0, ResourceCenterService.searchResources('x', 'no-such-slug').size(),
            'An unknown scope matches nothing.');
    }

    @isTest
    static void resourceBySlugCarriesCategoryParent() {
        Test.startTest();
        ResourceCenterService.ResourceDetail nested = ResourceCenterService.getResourceBySlug('brand-flyer');
        ResourceCenterService.ResourceDetail direct = ResourceCenterService.getResourceBySlug('partner-site');
        Test.stopTest();

        Assert.areEqual(1, nested.categoryAncestors.size(),
            'A subtopic-filed resource reports its main topic for the crumb.');
        Assert.areEqual('marketing', nested.categoryAncestors[0].slug);
        Assert.areEqual('Marketing', nested.categoryAncestors[0].name);
        Assert.areEqual(0, direct.categoryAncestors.size(),
            'A resource filed directly on a main topic has no ancestor crumb segments.');
    }

    @isTest
    static void categoryBySlugBuildsSections() {
        // An empty active subcategory gets no section; an inactive subcategory
        // hides its resources entirely.
        Id marketingId = [SELECT Id FROM Resource_Category__c WHERE Slug__c = 'marketing'].Id;
        Resource_Category__c emptySub = new Resource_Category__c(
            Name = 'Empty Sub', Slug__c = 'empty-sub', Parent_Category__c = marketingId,
            Display_Order__c = 2, Is_Active__c = true);
        Resource_Category__c hiddenSub = new Resource_Category__c(
            Name = 'Hidden Sub', Slug__c = 'hidden-sub', Parent_Category__c = marketingId,
            Display_Order__c = 3, Is_Active__c = false);
        insert new List<Resource_Category__c>{ emptySub, hiddenSub };
        insert new Resource__c(
            Name = 'Hidden Doc', Slug__c = 'hidden-doc', Category__c = hiddenSub.Id,
            Resource_Type__c = 'PDF', Is_Active__c = true);

        Test.startTest();
        ResourceCenterService.CategoryDetail marketing = ResourceCenterService.getCategoryBySlug('marketing');
        ResourceCenterService.CategoryDetail flyers = ResourceCenterService.getCategoryBySlug('flyers');
        Test.stopTest();

        Assert.areEqual(2, marketing.sections.size(),
            'One Flyers section + trailing General; empty and inactive subcategories get none.');
        Assert.areEqual('flyers', marketing.sections[0].key, 'Named sections key on the subcategory slug.');
        Assert.areEqual('Flyers', marketing.sections[0].title, 'Named sections use the subcategory name.');
        Assert.areEqual(1, marketing.sections[0].resources.size(), 'The PDF groups under Flyers.');
        Assert.areEqual('brand-flyer', marketing.sections[0].resources[0].slug);
        Assert.areEqual('general', marketing.sections[1].key, 'Direct-filed resources trail in General.');
        Assert.areEqual(900, marketing.sections[1].displayOrder, 'General always sorts after named sections.');
        Assert.areEqual('partner-site', marketing.sections[1].resources[0].slug);
        Assert.areEqual(1, marketing.resources.size(),
            'The direct-filed list keeps its original meaning alongside sections.');

        Assert.areEqual(1, flyers.sections.size(),
            'A subcategory page carries its own resources as a single General section.');
        Assert.areEqual('general', flyers.sections[0].key);
        Assert.areEqual(1, flyers.resources.size(), 'Subcategory direct list unchanged.');
    }

    @isTest
    static void featuredResourcesReturned() {
        Test.startTest();
        List<ResourceCenterService.ResourceCard> featured = ResourceCenterService.getFeaturedResources();
        Test.stopTest();
        Assert.areEqual(1, featured.size(), 'Only the Brand Flyer is featured.');
        Assert.areEqual('brand-flyer', featured[0].slug, 'Featured flyer returned.');
    }

    @isTest
    static void categoryNotFoundThrows() {
        try {
            ResourceCenterService.getCategoryBySlug('nope');
            Assert.fail('Expected AuraHandledException for unknown slug.');
        } catch (AuraHandledException e) {
            // expected
        }
    }

    @isTest
    static void resourceBySlugIncludesFileAndDownloadUrl() {
        Test.startTest();
        ResourceCenterService.ResourceDetail d = ResourceCenterService.getResourceBySlug('brand-flyer');
        Test.stopTest();

        Assert.areEqual('PDF', d.resourceType, 'Type carried through.');
        Assert.isNotNull(d.file, 'The PDF has an attached file.');
        Assert.isTrue(d.file.downloadUrl.startsWith('/sfc/servlet.shepherd/document/download/'),
            'Default delivery is the authenticated Shepherd URL.');
        Assert.isTrue(d.file.previewUrl != null
            && d.file.previewUrl.contains('renditionDownload?rendition=SVGZ&versionId='),
            'Inline preview uses the SVGZ rendition URL: ' + d.file.previewUrl);
        Assert.isTrue(d.file.imagePreviewUrl != null
            && d.file.imagePreviewUrl.contains('rendition=THUMB720BY480'),
            'Image fallback uses the thumbnail rendition URL.');
        Assert.areEqual('flyers', d.categorySlug, 'Category slug carried through.');
    }

    @isTest
    static void resourcesForArticleSurviveRepublish() {
        // Publish an article, link a resource to its KA Id, then republish and
        // confirm the junction still resolves through the NEW version Id.
        // Knowledge__kav DML/publish needs the Knowledge User feature license —
        // no admin in this org has it — so the whole test runs as a user who does.
        System.runAs(makeKnowledgeUser()) {
            Knowledge__kav kav = new Knowledge__kav(
                Title = 'How to brand', UrlName = 'how-to-brand', Language = 'en_US', Summary = 's');
            insert kav;
            Id v1 = kav.Id;
            String kaId = [SELECT KnowledgeArticleId FROM Knowledge__kav WHERE Id = :v1].KnowledgeArticleId;
            KbManagement.PublishingService.publishArticle(kaId, true);

            insert new Article_Resource__c(
                Resource__c = resourceId('brand-flyer'), Knowledge_Article_Id__c = kaId,
                Article_UrlName__c = 'how-to-brand', Display_Order__c = 1);

            Test.startTest();
            List<ResourceCenterService.ResourceCard> before =
                ResourceCenterService.getResourcesForArticle(v1);

            // Republish: creates a new draft version, publish again → new version Id.
            KbManagement.PublishingService.editOnlineArticle(kaId, false);
            Id v2 = [
                SELECT Id FROM Knowledge__kav
                WHERE KnowledgeArticleId = :kaId AND PublishStatus = 'Draft' LIMIT 1
            ].Id;
            KbManagement.PublishingService.publishArticle(kaId, true);
            List<ResourceCenterService.ResourceCard> after =
                ResourceCenterService.getResourcesForArticle(v2);
            Test.stopTest();

            Assert.areEqual(1, before.size(), 'Resource resolves through the original version Id.');
            Assert.areEqual(1, after.size(),
                'Resource still resolves through the new version Id — junction keyed on the stable KA Id.');
            Assert.areEqual('brand-flyer', after[0].slug, 'Same resource after republish.');
        }
    }

    @isTest
    static void relatedArticlesForResourceResolveLatestVersion() {
        System.runAs(makeKnowledgeUser()) {
            Knowledge__kav kav = new Knowledge__kav(
                Title = 'Brand guide', UrlName = 'brand-guide', Language = 'en_US', Summary = 's');
            insert kav;
            String kaId = [SELECT KnowledgeArticleId FROM Knowledge__kav WHERE Id = :kav.Id].KnowledgeArticleId;
            KbManagement.PublishingService.publishArticle(kaId, true);

            Id rId = resourceId('brand-flyer');
            insert new Article_Resource__c(
                Resource__c = rId, Knowledge_Article_Id__c = kaId, Article_UrlName__c = 'brand-guide');

            Test.startTest();
            List<ResourceCenterService.RelatedArticle> related =
                ResourceCenterService.getRelatedArticlesForResource(rId);
            Test.stopTest();

            Assert.areEqual(1, related.size(), 'One linked article.');
            Assert.areEqual('brand-guide', related[0].urlName, 'Latest published UrlName resolved.');
            Assert.areEqual('Brand guide', related[0].title, 'Latest published title resolved.');
        }
    }

    @isTest
    static void searchResourcesReturnsActive() {
        Test.setFixedSearchResults(new List<Id>{ resourceId('brand-flyer') });
        Test.startTest();
        List<ResourceCenterService.ResourceCard> hits = ResourceCenterService.searchResources('flyer', null);
        Test.stopTest();
        Assert.areEqual(1, hits.size(), 'Fixed SOSL result returned.');
        Assert.areEqual('brand-flyer', hits[0].slug, 'Matched the flyer.');
    }

    @isTest
    static void typeaheadMatchesByName() {
        Test.startTest();
        List<ResourceCenterService.ResourceCard> hits = ResourceCenterService.typeahead('Brand', null);
        List<ResourceCenterService.ResourceCard> none = ResourceCenterService.typeahead('   ', null);
        Test.stopTest();
        Assert.areEqual(1, hits.size(), 'Brand Flyer matches "Brand".');
        Assert.areEqual('brand-flyer', hits[0].slug, 'Typeahead carries the slug for selection.');
        Assert.areEqual(0, none.size(), 'Blank term returns nothing.');
    }

    @isTest
    static void searchResourcesBlankTermIsEmpty() {
        Assert.areEqual(0, ResourceCenterService.searchResources('   ', null).size(),
            'Blank term yields no SOSL and an empty list.');
    }

    @isTest
    static void searchAllMergesResources() {
        Test.setFixedSearchResults(new List<Id>{ resourceId('brand-flyer') });
        Test.startTest();
        ResourceCenterService.CombinedSearch combined = ResourceCenterService.searchAll('flyer');
        Test.stopTest();
        Boolean sawResource = false;
        for (ResourceCenterService.CombinedResult r : combined.results) {
            if (r.type == 'resource' && r.slug == 'brand-flyer') {
                sawResource = true;
            }
        }
        Assert.isTrue(sawResource, 'Combined results include the resource row.');
        Assert.isFalse(combined.resourcesDegraded,
            'Resource side succeeded — not degraded.');
        Assert.isFalse(combined.articlesDegraded,
            'Article side ran (empty is fine) — not degraded.');
    }

    @isTest
    static void trackDownloadIncrementsCount() {
        Id rId = resourceId('brand-flyer');
        Test.startTest();
        ResourceCenterService.trackDownload(rId);
        Test.stopTest(); // runs the queueable
        Decimal count = [SELECT Download_Count__c FROM Resource__c WHERE Id = :rId].Download_Count__c;
        Assert.areEqual(1, count, 'Download counter incremented by the queueable.');
    }

    @isTest
    static void trackDownloadNullIsNoop() {
        Test.startTest();
        ResourceCenterService.trackDownload(null); // must not throw
        Test.stopTest();
        Assert.isTrue(true, 'Null resource id is a safe no-op.');
    }

    @isTest
    static void linkBasesResolveTheDefaultSurfaceInTheCoreApp() {
        // No network in a test context (the Admin Console's Copy link runs in
        // Lightning): both accessors resolve the Is_Default__c row's site —
        // Arc — absolute, with that row's page names.
        seedArcAsDefault();

        Test.startTest();
        String helpBase = ResourceCenterService.getHelpCenterLinkBase();
        String resourceBase = ResourceCenterService.getResourceLinkBase();
        Test.stopTest();

        Assert.areEqual('https://arc.example/help-center', helpBase);
        Assert.areEqual('https://arc.example/learning', resourceBase,
            'The Resource Center page is /learning on Arc, never /resources');
    }

    @isTest
    static void linkBasesAreNullWithoutADefaultSurface() {
        // No row flagged default and no site context: nothing to link to —
        // callers hide the copy button / fall back to a direct download.
        ResourceCenterService.surfaceRows = new Map<String, Help_Surface__mdt>{
            ResourceCenterService.surfaceKey('Arc') => arcRow(false)
        };

        Test.startTest();
        String helpBase = ResourceCenterService.getHelpCenterLinkBase();
        String resourceBase = ResourceCenterService.getResourceLinkBase();
        Test.stopTest();

        Assert.isNull(helpBase);
        Assert.isNull(resourceBase);
        Assert.isNull(ResourceCenterService.defaultSurface());
    }

    @isTest
    static void resourceLinkBaseIsWellFormedOrNull() {
        // Site/SiteDetail can't be created in tests, so assert the contract
        // against whatever the org has: never throws; when it resolves, it is
        // absolute and ends in the default row's Resources page path.
        Test.startTest();
        String base = ResourceCenterService.getResourceLinkBase();
        Test.stopTest();
        if (base != null) {
            Assert.isTrue(base.startsWith('https://'), 'Absolute URL expected: ' + base);
            Help_Surface__mdt dflt = ResourceCenterService.defaultSurface();
            String page = dflt == null || String.isBlank(dflt.Resources_Path__c) ? 'resources' : dflt.Resources_Path__c;
            Assert.isTrue(base.endsWith('/' + page), 'Resources page path expected: ' + base);
            Assert.isFalse(base.contains('//' + page), 'No double slash before the page path: ' + base);
        }
    }

    @isTest
    static void linkContextIsInternalInTheCoreApp() {
        // Apex tests run outside any Experience Cloud site, so
        // Network.getNetworkId() is null — the core-app branch. Both bases must
        // come back null: that is c/contextNav's signal to navigate with
        // NavigationMixin instead of leaving for *.my.site.com.
        Test.startTest();
        ResourceCenterService.LinkContext ctx = ResourceCenterService.getLinkContext();
        Test.stopTest();

        Assert.isNotNull(ctx, 'getLinkContext never returns null');
        Assert.areEqual('Internal', ctx.surface, 'No network in a test context');
        Assert.isNull(ctx.helpBase, 'Internal surface carries no site base');
        Assert.isNull(ctx.resourceBase, 'Internal surface carries no site base');
    }

    @isTest
    static void linkContextMapsTheCurrentNetworkToItsOwnPages() {
        // A network with a Help_Surface__mdt row gets ITS site's pages — the
        // reason the table exists: ARC hosts the Help & Resources components on
        // its own pages (help-center / article / learning / events), and a
        // link to the shared /help site would be a different login. Seeded
        // with the real ARC row shape (customMetadata/Help_Surface.ARC). The
        // network is named "Arc" while the row says "ARC": the lookup must be
        // case-insensitive (prod regression 2026-09-06 — a login page).
        ResourceCenterService.surfaceOverride = 'Arc';
        ResourceCenterService.surfaceRows = new Map<String, Help_Surface__mdt>{
            ResourceCenterService.surfaceKey('ARC') => new Help_Surface__mdt(
                Network_Name__c = 'ARC', Home_Path__c = 'help-center', Article_Path__c = 'article',
                Resources_Path__c = 'learning', Events_Path__c = 'events')
        };
        ResourceCenterService.siteBaseOverride.put('Arc', 'https://x.my.site.com/ARC');

        Test.startTest();
        ResourceCenterService.LinkContext ctx = ResourceCenterService.getLinkContext();
        Test.stopTest();

        Assert.areEqual('Arc', ctx.surface);
        Assert.areEqual('https://x.my.site.com/ARC', ctx.helpBase, 'The CURRENT site root, not /help');
        Assert.areEqual('https://x.my.site.com/ARC/help-center', ctx.homeBase);
        Assert.areEqual('https://x.my.site.com/ARC/article', ctx.articleBase);
        Assert.areEqual('https://x.my.site.com/ARC/learning', ctx.resourceBase);
        Assert.areEqual('https://x.my.site.com/ARC/events', ctx.eventsBase);
    }

    @isTest
    static void eventsUrlForResolvesANetworkWithoutASiteContext() {
        // The scheduled announcement sweep has no Network context: it names
        // the network and gets that site's Events page (row path + SecureUrl).
        ResourceCenterService.surfaceRows = new Map<String, Help_Surface__mdt>{
            ResourceCenterService.surfaceKey('Arc') => new Help_Surface__mdt(
                Network_Name__c = 'Arc', Events_Path__c = 'events')
        };
        ResourceCenterService.siteBaseOverride.put('Arc', 'https://arc.example');
        ResourceCenterService.siteBaseOverride.put('Bare', 'https://bare.example');

        Assert.areEqual('https://arc.example/events', ResourceCenterService.eventsUrlFor('Arc'));
        // (The site seam is keyed exactly; the row lookup is case-folded and a
        // real Site query matches MasterLabel case-insensitively anyway.)
        Assert.areEqual('https://bare.example/events', ResourceCenterService.eventsUrlFor('Bare'),
            'No row → the default page name on the resolved site');
        Assert.isNull(ResourceCenterService.eventsUrlFor('No Such Network'),
            'Unresolvable site → null, never a throw');
        Assert.isNull(ResourceCenterService.eventsUrlFor(' '));
    }

    @isTest
    static void linkContextBlankPathsMeanRootAndDefaults() {
        ResourceCenterService.surfaceOverride = 'Diversify Help Center';
        ResourceCenterService.surfaceRows = new Map<String, Help_Surface__mdt>{
            ResourceCenterService.surfaceKey('Diversify Help Center') => new Help_Surface__mdt(Network_Name__c = 'Diversify Help Center')
        };
        ResourceCenterService.siteBaseOverride.put('Diversify Help Center', 'https://x.my.site.com/help');

        ResourceCenterService.LinkContext ctx = ResourceCenterService.getLinkContext();

        Assert.areEqual('https://x.my.site.com/help', ctx.homeBase, 'Blank home = the site root');
        Assert.areEqual('https://x.my.site.com/help/article', ctx.articleBase);
        Assert.areEqual('https://x.my.site.com/help/resources', ctx.resourceBase);
        Assert.areEqual('https://x.my.site.com/help/events', ctx.eventsBase);
    }

    @isTest
    static void linkContextFallsBackToTheDefaultSurfaceForUnmappedNetworks() {
        // No row for this network: the default surface (Arc) with ITS page
        // names — never the retired /help site.
        ResourceCenterService.surfaceOverride = 'Some Other Site';
        seedArcAsDefault();

        Test.startTest();
        ResourceCenterService.LinkContext ctx = ResourceCenterService.getLinkContext();
        String helpBase = ResourceCenterService.getHelpCenterLinkBase();
        String resourceBase = ResourceCenterService.getResourceLinkBase();
        Test.stopTest();

        Assert.areEqual('Some Other Site', ctx.surface);
        Assert.areEqual('https://arc.example', ctx.helpBase, 'Unmapped network → the default site root');
        Assert.areEqual('https://arc.example/help-center', ctx.homeBase);
        Assert.areEqual('https://arc.example/article', ctx.articleBase);
        Assert.areEqual('https://arc.example/learning', ctx.resourceBase);
        Assert.areEqual('https://arc.example/events', ctx.eventsBase);
        Assert.areEqual(ctx.homeBase, helpBase, 'The standalone accessors agree');
        Assert.areEqual(ctx.resourceBase, resourceBase);
    }

    @isTest
    static void linkContextHasNoBasesWhenNothingResolves() {
        ResourceCenterService.surfaceOverride = 'Some Other Site';
        ResourceCenterService.surfaceRows = new Map<String, Help_Surface__mdt>();

        Test.startTest();
        ResourceCenterService.LinkContext ctx = ResourceCenterService.getLinkContext();
        Test.stopTest();

        Assert.areEqual('Some Other Site', ctx.surface);
        Assert.isNull(ctx.helpBase, 'No row, no default → in-app');
        Assert.isNull(ctx.resourceBase);
    }

    @isTest
    static void defaultSurfaceIsTheFlaggedRowFirstByDeveloperName() {
        Help_Surface__mdt other = new Help_Surface__mdt(
            DeveloperName = 'Zeta', Network_Name__c = 'Zeta Site', Is_Default__c = true);
        ResourceCenterService.surfaceRows = new Map<String, Help_Surface__mdt>{
            ResourceCenterService.surfaceKey('Zeta Site') => other,
            ResourceCenterService.surfaceKey('Arc') => arcRow(true),
            ResourceCenterService.surfaceKey('Diversify Help Center') =>
                new Help_Surface__mdt(DeveloperName = 'Help_Center', Network_Name__c = 'Diversify Help Center')
        };
        Assert.areEqual('ARC', ResourceCenterService.defaultSurface().DeveloperName,
            'Two flagged rows → the first by DeveloperName');
    }

    @isTest
    static void linkContextAgreesWithTheStandaloneAccessors() {
        // The two legacy accessors stay site-absolute on every surface (the
        // Admin Console's Copy link depends on it). Wherever getLinkContext
        // does return bases, they must be the same strings.
        Test.startTest();
        ResourceCenterService.LinkContext ctx = ResourceCenterService.getLinkContext();
        String helpBase = ResourceCenterService.getHelpCenterLinkBase();
        String resourceBase = ResourceCenterService.getResourceLinkBase();
        Test.stopTest();

        if (ctx.helpBase != null) {
            Assert.areEqual(helpBase, ctx.homeBase, 'Same home page either way');
            Assert.areEqual(resourceBase, ctx.resourceBase, 'Same resource page either way');
        }
    }

    @isTest
    static void helpCenterLinkBaseIsSiteRootOrNull() {
        // Same contract as the resources base, minus the page path: the Help
        // Center base is the shared site's root (article deep links append
        // /?article=<UrlName>).
        Test.startTest();
        String base = ResourceCenterService.getHelpCenterLinkBase();
        String resourcesBase = ResourceCenterService.getResourceLinkBase();
        Test.stopTest();
        if (base != null) {
            Assert.isTrue(base.startsWith('https://'), 'Absolute URL expected: ' + base);
            Assert.isFalse(base.endsWith('/'), 'No trailing slash: ' + base);
            Assert.isTrue(resourcesBase.startsWith('https://'), 'Resources base is absolute too: ' + resourcesBase);
        }
    }

    // ---- getWebinars() ---------------------------------------------------------

    private static Resource__c webinar(String name, String slug, Id catId, Datetime eventAt,
                                       String embedUrl, String registrationUrl) {
        return new Resource__c(
            Name = name, Slug__c = slug, Category__c = catId, Resource_Type__c = 'Webinar',
            Event_Datetime__c = eventAt, Video_Embed_URL__c = embedUrl,
            Registration_URL__c = registrationUrl, Is_Active__c = true);
    }

    private static void attachFile(Id resourceId, String title) {
        ContentVersion cv = new ContentVersion(
            Title = title, PathOnClient = title, VersionData = Blob.valueOf('fake bytes'));
        insert cv;
        Id cdId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
        insert new ContentDocumentLink(
            LinkedEntityId = resourceId, ContentDocumentId = cdId, ShareType = 'V', Visibility = 'AllUsers');
    }

    @isTest
    static void webinarAgendaSplitsSortsAndDerivesStatus() {
        Id catId = [SELECT Id FROM Resource_Category__c WHERE Slug__c = 'marketing'].Id;
        Datetime now = System.now();
        Resource__c oldTalk = webinar('Old Talk', 'old-talk', catId, now.addDays(-10), null, null);
        Resource__c fileTalk = webinar('File Talk', 'file-talk', catId, now.addDays(-5), null, null);
        Resource__c embedTalk = webinar('Embed Talk', 'embed-talk', catId, now.addDays(-2),
            'https://www.youtube.com/embed/x', null);
        Resource__c later = webinar('Later Talk', 'later-talk', catId, now.addDays(7), null,
            'https://example.com/register-later');
        Resource__c soon = webinar('Soon Talk', 'soon-talk', catId, now.addDays(1), null,
            'https://example.com/register-soon');
        Resource__c hidden = webinar('Hidden Talk', 'hidden-talk', catId, now.addDays(3), null,
            'https://example.com/register-hidden');
        hidden.Is_Active__c = false;
        insert new List<Resource__c>{ oldTalk, fileTalk, embedTalk, later, soon, hidden };
        attachFile(fileTalk.Id, 'replay.mp4'); // recording via the newest attached file
        ResourceCenterService.webinarAgendaEnabledOverride = true;

        Test.startTest();
        ResourceCenterService.WebinarAgenda agenda = ResourceCenterService.getWebinars();
        Test.stopTest();

        Assert.areEqual(2, agenda.upcoming.size(), 'Two active future webinars (inactive hidden).');
        Assert.areEqual('soon-talk', agenda.upcoming[0].slug, 'Upcoming is soonest-first.');
        Assert.areEqual('later-talk', agenda.upcoming[1].slug);
        Assert.areEqual(WebinarLifecycle.UPCOMING, agenda.upcoming[0].status);
        Assert.isFalse(agenda.upcoming[0].watchable, 'Upcoming is never watchable.');
        Assert.areEqual('https://example.com/register-soon', agenda.upcoming[0].registrationUrl);

        Assert.areEqual(3, agenda.recent.size(), 'Every past webinar is recent, recorded or not.');
        Assert.areEqual('embed-talk', agenda.recent[0].slug, 'Recent is most-recent-first.');
        Assert.areEqual('file-talk', agenda.recent[1].slug);
        Assert.areEqual('old-talk', agenda.recent[2].slug);
        Assert.areEqual(WebinarLifecycle.RECORDED, agenda.recent[0].status, 'Embed URL = recorded.');
        Assert.areEqual(WebinarLifecycle.RECORDED, agenda.recent[1].status, 'Attached file = recorded.');
        Assert.areEqual(WebinarLifecycle.PAST, agenda.recent[2].status, 'No recording yet.');
        Assert.isTrue(agenda.recent[0].watchable);
        Assert.isTrue(agenda.recent[1].watchable);
        Assert.isFalse(agenda.recent[2].watchable);
    }

    @isTest
    static void webinarAgendaCapsEachSection() {
        Id catId = [SELECT Id FROM Resource_Category__c WHERE Slug__c = 'marketing'].Id;
        Datetime now = System.now();
        List<Resource__c> rows = new List<Resource__c>();
        for (Integer i = 1; i <= 3; i++) {
            rows.add(webinar('Up ' + i, 'up-' + i, catId, now.addDays(i), null, 'https://example.com/r' + i));
            rows.add(webinar('Past ' + i, 'past-' + i, catId, now.addDays(-i), null, null));
        }
        insert rows;
        ResourceCenterService.webinarAgendaEnabledOverride = true;
        ResourceCenterService.webinarAgendaLimitOverride = 2;

        Test.startTest();
        ResourceCenterService.WebinarAgenda agenda = ResourceCenterService.getWebinars();
        Test.stopTest();

        Assert.areEqual(2, agenda.upcoming.size(), 'Capped by the configured limit.');
        Assert.areEqual('up-1', agenda.upcoming[0].slug, 'The soonest survive the cap.');
        Assert.areEqual('up-2', agenda.upcoming[1].slug);
        Assert.areEqual(2, agenda.recent.size());
        Assert.areEqual('past-1', agenda.recent[0].slug, 'The most recent survive the cap.');
        Assert.areEqual('past-2', agenda.recent[1].slug);
    }

    @isTest
    static void webinarAgendaHiddenWhenDisabledByConfig() {
        Id catId = [SELECT Id FROM Resource_Category__c WHERE Slug__c = 'marketing'].Id;
        insert webinar('Soon Talk', 'soon-talk', catId, System.now().addDays(1), null,
            'https://example.com/register');
        ResourceCenterService.webinarAgendaEnabledOverride = false;

        Test.startTest();
        ResourceCenterService.WebinarAgenda agenda = ResourceCenterService.getWebinars();
        Test.stopTest();

        Assert.areEqual(0, agenda.upcoming.size(), 'Disabled panel: nothing, even with data.');
        Assert.areEqual(0, agenda.recent.size());
    }

    @isTest
    static void webinarAgendaDegradesToEmptyForBareUser() {
        Id catId = [SELECT Id FROM Resource_Category__c WHERE Slug__c = 'marketing'].Id;
        insert webinar('Soon Talk', 'soon-talk', catId, System.now().addDays(1), null,
            'https://example.com/register');
        User bare;
        System.runAs(HelpCenterTestDataFactory.currentUser()) {
            // Standard User, auto-assigned permsets stripped: no Resource__c read.
            bare = HelpCenterTestDataFactory.createUser('rcbare', null);
        }
        ResourceCenterService.webinarAgendaEnabledOverride = true;

        Test.startTest();
        ResourceCenterService.WebinarAgenda agenda;
        System.runAs(bare) {
            agenda = ResourceCenterService.getWebinars(); // must not throw
        }
        Test.stopTest();

        Assert.areEqual(0, agenda.upcoming.size(), 'No access degrades to an empty agenda.');
        Assert.areEqual(0, agenda.recent.size());
    }

    // ---- getEvents() -----------------------------------------------------------

    @isTest
    static void eventsFeedSplitsSortsAndFlagsRecordings() {
        Id catId = [SELECT Id FROM Resource_Category__c WHERE Slug__c = 'marketing'].Id;
        Datetime now = System.now();
        Resource__c noReplay = webinar('No Replay', 'no-replay', catId, now.addDays(-10), null, null);
        Resource__c fileTalk = webinar('File Talk', 'file-talk', catId, now.addDays(-5), null, null);
        Resource__c embedTalk = webinar('Embed Talk', 'embed-talk', catId, now.addDays(-2),
            'https://www.youtube.com/embed/x', null);
        Resource__c later = webinar('Later Talk', 'later-talk', catId, now.addDays(7), null,
            'https://example.com/register-later');
        Resource__c soon = webinar('Soon Talk', 'soon-talk', catId, now.addDays(1), null,
            'https://example.com/register-soon');
        insert new List<Resource__c>{ noReplay, fileTalk, embedTalk, later, soon };
        attachFile(fileTalk.Id, 'replay.mp4'); // recording via the newest attached file

        Test.startTest();
        ResourceCenterService.EventsFeed feed = ResourceCenterService.getEvents();
        Test.stopTest();

        Assert.areEqual(2, feed.upcoming.size());
        Assert.areEqual('soon-talk', feed.upcoming[0].slug, 'Upcoming is soonest-first.');
        Assert.areEqual('later-talk', feed.upcoming[1].slug);
        Assert.areEqual(WebinarLifecycle.UPCOMING, feed.upcoming[0].status);

        Assert.areEqual(3, feed.past.size(),
            'Past keeps every past webinar (the calendar shows them all); watchable flags recordings.');
        Assert.areEqual('embed-talk', feed.past[0].slug, 'Past is most-recent-first; embed URL counts.');
        Assert.areEqual('file-talk', feed.past[1].slug, 'Attached file counts as a recording.');
        Assert.areEqual('no-replay', feed.past[2].slug, 'Unrecorded past rows are kept, last.');
        Assert.isTrue(feed.past[0].watchable);
        Assert.isTrue(feed.past[1].watchable);
        Assert.isFalse(feed.past[2].watchable, 'No recording: the list hides it, the calendar shows it.');
        Assert.areEqual(WebinarLifecycle.RECORDED, feed.past[0].status);
        Assert.areEqual(WebinarLifecycle.PAST, feed.past[2].status);
    }

    @isTest
    static void eventsFeedIgnoresAgendaFlagAndCap() {
        // The agenda flag/limit gate the landing panel only — the routed events
        // page must not vanish or truncate with them.
        Id catId = [SELECT Id FROM Resource_Category__c WHERE Slug__c = 'marketing'].Id;
        Datetime now = System.now();
        List<Resource__c> rows = new List<Resource__c>();
        for (Integer i = 1; i <= 3; i++) {
            rows.add(webinar('Up ' + i, 'up-' + i, catId, now.addDays(i), null, 'https://example.com/r' + i));
        }
        insert rows;
        ResourceCenterService.webinarAgendaEnabledOverride = false;
        ResourceCenterService.webinarAgendaLimitOverride = 2;

        Test.startTest();
        ResourceCenterService.EventsFeed feed = ResourceCenterService.getEvents();
        Test.stopTest();

        Assert.areEqual(3, feed.upcoming.size(),
            'Disabled panel + agenda cap 2: the feed still returns all 3.');
    }

    @isTest
    static void eventsFeedDegradesToEmptyForBareUser() {
        Id catId = [SELECT Id FROM Resource_Category__c WHERE Slug__c = 'marketing'].Id;
        insert webinar('Soon Talk', 'soon-talk', catId, System.now().addDays(1), null,
            'https://example.com/register');
        User bare;
        System.runAs(HelpCenterTestDataFactory.currentUser()) {
            // Standard User, auto-assigned permsets stripped: no Resource__c read.
            bare = HelpCenterTestDataFactory.createUser('evbare', null);
        }

        Test.startTest();
        ResourceCenterService.EventsFeed feed;
        System.runAs(bare) {
            feed = ResourceCenterService.getEvents(); // must not throw
        }
        Test.stopTest();

        Assert.areEqual(0, feed.upcoming.size(), 'No access degrades to an empty feed.');
        Assert.areEqual(0, feed.past.size());
    }

    @isTest
    static void webinarDetailAndCardsCarryLifecycle() {
        Id catId = [SELECT Id FROM Resource_Category__c WHERE Slug__c = 'marketing'].Id;
        Datetime now = System.now();
        Resource__c upcoming = webinar('Soon Talk', 'soon-talk', catId, now.addDays(1), null,
            'https://example.com/register');
        upcoming.Is_Featured__c = true;
        upcoming.Event_Duration_Minutes__c = 45;
        upcoming.Presenter__c = 'Jane Doe';
        Resource__c recorded = webinar('Replay', 'replay', catId, now.addDays(-1), null, null);
        insert new List<Resource__c>{ upcoming, recorded };
        attachFile(recorded.Id, 'replay.mp4');

        Test.startTest();
        ResourceCenterService.ResourceDetail up = ResourceCenterService.getResourceBySlug('soon-talk');
        ResourceCenterService.ResourceDetail rec = ResourceCenterService.getResourceBySlug('replay');
        ResourceCenterService.ResourceDetail pdf = ResourceCenterService.getResourceBySlug('brand-flyer');
        List<ResourceCenterService.ResourceCard> featured = ResourceCenterService.getFeaturedResources();
        Test.stopTest();

        Assert.areEqual(WebinarLifecycle.UPCOMING, up.webinarStatus);
        Assert.areEqual('https://example.com/register', up.registrationUrl);
        Assert.areEqual(45, up.durationMinutes);
        Assert.areEqual('Jane Doe', up.presenter);
        Assert.isNotNull(up.eventDatetime);
        Assert.areEqual(WebinarLifecycle.RECORDED, rec.webinarStatus,
            'The newest attached file is the recording.');
        Assert.isNotNull(rec.file, 'The recording file rides the existing file path.');
        Assert.isNull(pdf.webinarStatus, 'Non-webinars carry no lifecycle.');

        ResourceCenterService.ResourceCard card;
        for (ResourceCenterService.ResourceCard c : featured) {
            if (c.slug == 'soon-talk') {
                card = c;
            }
        }
        Assert.isNotNull(card, 'Featured webinar appears in the featured strip.');
        Assert.areEqual(WebinarLifecycle.UPCOMING, card.webinarStatus);
        Assert.areEqual('https://example.com/register', card.registrationUrl);
    }

    // ---- Link bases ON a site use that site's own row ---------------------------

    @isTest
    static void linkBasesUseTheCurrentSurfaceRowOnASite() {
        // Running on a mapped site: its own pages, absolute (a same-site hop
        // is contextNav's job, not these accessors'). The /help row keeps its
        // shape while the site exists; Arc is the default beside it.
        ResourceCenterService.surfaceOverride = 'Diversify Help Center';
        ResourceCenterService.surfaceRows = new Map<String, Help_Surface__mdt>{
            ResourceCenterService.surfaceKey('Diversify Help Center') => new Help_Surface__mdt(
                DeveloperName = 'Help_Center', Network_Name__c = 'Diversify Help Center',
                Article_Path__c = 'article', Resources_Path__c = 'resources', Events_Path__c = 'events'),
            ResourceCenterService.surfaceKey('Arc') => arcRow(true)
        };
        ResourceCenterService.siteBaseOverride.put('Diversify Help Center', 'https://x.my.site.com/help');
        ResourceCenterService.siteBaseOverride.put('Arc', 'https://arc.example');

        Test.startTest();
        String helpBase = ResourceCenterService.getHelpCenterLinkBase();
        String resourceBase = ResourceCenterService.getResourceLinkBase();
        Test.stopTest();

        Assert.areEqual('https://x.my.site.com/help', helpBase, 'Blank Home_Path__c = the site root');
        Assert.areEqual('https://x.my.site.com/help/resources', resourceBase);
    }

    @isTest
    static void linkBasesFallToTheDefaultWhenTheCurrentSiteHasNoRow() {
        ResourceCenterService.surfaceOverride = 'Some Other Site';
        seedArcAsDefault();

        Test.startTest();
        String helpBase = ResourceCenterService.getHelpCenterLinkBase();
        Test.stopTest();

        Assert.areEqual('https://arc.example/help-center', helpBase, 'Absolute, the default surface');
    }

    // ---- ARC bridge (c/helpReturnLink) ---------------------------------------

    @isTest
    static void arcBridgeUsesTheSeams() {
        // Site / NetworkMember rows can't be created in tests; the seams stand
        // in for "the ARC site resolved and the viewer is a member".
        ResourceCenterService.arcSiteBaseOverride = 'https://x.my.site.com/ARC';
        ResourceCenterService.arcMemberOverride = true;

        Test.startTest();
        ResourceCenterService.ArcBridge bridge = ResourceCenterService.getArcBridge();
        Test.stopTest();

        Assert.areEqual('https://x.my.site.com/ARC', bridge.siteUrl);
        Assert.isTrue(bridge.isMember);
    }

    @isTest
    static void arcBridgeNeverThrowsAndDefaultsToNoLink() {
        // No seams: whatever the org has, the call must come back with a
        // well-formed answer — a null site or a non-member simply hides the link.
        Test.startTest();
        ResourceCenterService.ArcBridge bridge = ResourceCenterService.getArcBridge();
        Test.stopTest();

        Assert.isNotNull(bridge);
        Assert.isNotNull(bridge.isMember, 'Membership is always a definite boolean');
        if (bridge.siteUrl != null) {
            Assert.isTrue(bridge.siteUrl.startsWith('https://'), 'Absolute site root: ' + bridge.siteUrl);
            Assert.isFalse(bridge.siteUrl.endsWith('/'), 'No trailing slash: ' + bridge.siteUrl);
        }
    }

    // ---- "Also show in" (Resource_Category_Link__c) ------------------------------

    private static Id categoryId(String slug) {
        return [SELECT Id FROM Resource_Category__c WHERE Slug__c = :slug LIMIT 1].Id;
    }

    private static void link(String resourceSlug, Id catId) {
        insert new Resource_Category_Link__c(Resource__c = resourceId(resourceSlug), Category__c = catId);
    }

    private static Id makeTopLevel(String name, String slug, Integer order, Boolean active) {
        Resource_Category__c c = new Resource_Category__c(
            Name = name, Slug__c = slug, Display_Order__c = order, Is_Active__c = active);
        insert c;
        return c.Id;
    }

    private static Id makeSub(String name, String slug, Id parentId, Integer order) {
        Resource_Category__c c = new Resource_Category__c(
            Name = name, Slug__c = slug, Parent_Category__c = parentId,
            Display_Order__c = order, Is_Active__c = true);
        insert c;
        return c.Id;
    }

    private static List<String> slugs(List<ResourceCenterService.ResourceCard> cards) {
        List<String> out = new List<String>();
        for (ResourceCenterService.ResourceCard c : cards) {
            out.add(c.slug);
        }
        return out;
    }

    @isTest
    static void secondaryPlacementCountsDistinctOnTiles() {
        Id compliance = makeTopLevel('Compliance', 'compliance', 2, true);
        link('brand-flyer', compliance);              // shown under a second top-level
        link('partner-site', categoryId('flyers'));   // also shown under its own top-level's subtopic

        Test.startTest();
        List<ResourceCenterService.CategoryTile> tiles = ResourceCenterService.getTopLevelCategories();
        Test.stopTest();

        Map<String, Integer> countBySlug = new Map<String, Integer>();
        for (ResourceCenterService.CategoryTile t : tiles) {
            countBySlug.put(t.slug, t.resourceCount);
        }
        Assert.areEqual(2, countBySlug.get('marketing'),
            'A resource placed twice under one tile still counts once.');
        Assert.areEqual(1, countBySlug.get('compliance'),
            'A secondary placement counts toward the other tile.');
    }

    @isTest
    static void secondaryPlacementSurfacesEmptySubtopicInNav() {
        Id templates = makeSub('Templates', 'templates', categoryId('marketing'), 2);
        link('partner-site', templates);

        Test.startTest();
        CategoryTreeService.TreeDTO tree = ResourceCenterService.getCategoryTree();
        Test.stopTest();

        Assert.areEqual(new List<String>{ 'flyers', 'templates' }, childSlugs(rootsBySlug(tree).get('marketing')),
            'A subtopic populated only through Also show in joins the nav.');
    }

    @isTest
    static void categoryPageListsSecondaryInEverySectionNeverTwiceInGeneral() {
        Id templates = makeSub('Templates', 'templates', categoryId('marketing'), 2);
        link('brand-flyer', templates);              // Flyers (home) + Templates
        link('partner-site', categoryId('flyers'));  // home Marketing itself + Flyers

        Test.startTest();
        ResourceCenterService.CategoryDetail marketing = ResourceCenterService.getCategoryBySlug('marketing');
        Test.stopTest();

        List<String> keys = new List<String>();
        for (ResourceCenterService.ResourceSection s : marketing.sections) {
            keys.add(s.key);
        }
        Assert.areEqual(new List<String>{ 'flyers', 'templates' }, keys,
            'Named sections only: every direct-filed resource already landed in a section.');
        Assert.areEqual(new List<String>{ 'brand-flyer', 'partner-site' }, slugs(marketing.sections[0].resources),
            'Flyers lists its home resource and the one also shown there, in display order.');
        Assert.areEqual(new List<String>{ 'brand-flyer' }, slugs(marketing.sections[1].resources),
            'Templates lists the resource also shown there.');
        Assert.areEqual(0, marketing.resources.size(),
            'General is empty: the direct-filed resource is already in a named section.');
    }

    @isTest
    static void categoryPageSecondaryOnTopicLandsInGeneralOnce() {
        Id compliance = makeTopLevel('Compliance', 'compliance', 2, true);
        insert new Resource__c(
            Name = 'Policy', Slug__c = 'policy', Category__c = compliance,
            Resource_Type__c = 'PDF', Is_Active__c = true, Display_Order__c = 1);
        link('policy', categoryId('marketing'));       // foreign resource shown on the topic itself
        link('brand-flyer', categoryId('marketing'));  // already in Flyers: must not repeat in General

        Test.startTest();
        ResourceCenterService.CategoryDetail marketing = ResourceCenterService.getCategoryBySlug('marketing');
        Test.stopTest();

        Assert.areEqual(2, marketing.sections.size(), 'Flyers + General.');
        Assert.areEqual(new List<String>{ 'brand-flyer' }, slugs(marketing.sections[0].resources));
        Assert.areEqual('general', marketing.sections[1].key);
        Assert.areEqual(new List<String>{ 'policy', 'partner-site' }, slugs(marketing.sections[1].resources),
            'General carries the topic-level placements once each, in display order.');
        Assert.areEqual(new List<String>{ 'policy', 'partner-site' }, slugs(marketing.resources));
    }

    @isTest
    static void secondaryPlacementIgnoresInactiveCategories() {
        Id hidden = categoryId('hidden');
        insert new Resource__c(
            Name = 'Hidden Home', Slug__c = 'hidden-home', Category__c = hidden,
            Resource_Type__c = 'PDF', Is_Active__c = true);
        link('partner-site', hidden);                       // link INTO an inactive category
        link('hidden-home', categoryId('marketing'));       // link FROM a resource whose home is inactive

        Test.startTest();
        List<ResourceCenterService.CategoryTile> tiles = ResourceCenterService.getTopLevelCategories();
        ResourceCenterService.CategoryDetail marketing = ResourceCenterService.getCategoryBySlug('marketing');
        CategoryTreeService.TreeDTO tree = ResourceCenterService.getCategoryTree();
        Test.stopTest();

        Assert.areEqual(1, tiles.size(), 'The inactive category is still no tile.');
        Assert.areEqual(2, tiles[0].resourceCount, 'A resource homed in an inactive category never counts.');
        Assert.areEqual(new List<String>{ 'partner-site' }, slugs(marketing.resources),
            'The inactive-home resource is not shown even when linked here.');
        Assert.isFalse(rootsBySlug(tree).containsKey('hidden'), 'Inactive categories never enter the nav.');
    }

    @isTest
    static void resourceBySlugBreadcrumbStaysHome() {
        Id compliance = makeTopLevel('Compliance', 'compliance', 2, true);
        link('brand-flyer', compliance);

        Test.startTest();
        ResourceCenterService.ResourceDetail d = ResourceCenterService.getResourceBySlug('brand-flyer');
        Test.stopTest();

        Assert.areEqual('flyers', d.categorySlug, 'Breadcrumb and link always use the home category.');
        Assert.areEqual('marketing', d.categoryAncestors[0].slug);
    }

    // ---- Rich-text description (2026-09-07) -----------------------------------

    @isTest
    static void plainTextFlattensRichTextForListSurfaces() {
        Assert.isNull(ResourceCenterService.plainText(null));
        Assert.isNull(ResourceCenterService.plainText('   '));
        Assert.areEqual('Plain words', ResourceCenterService.plainText('  Plain words '),
            'Plain text passes through trimmed');
        Assert.areEqual('Logging in; Arc navigation: side menu; Search',
            ResourceCenterService.plainText(
                '<ul><li>Logging in</li><li>Arc navigation: side menu</li><li>Search</li></ul>'),
            'Bullets join with "; " and the last separator is dropped');
        Assert.areEqual('Part 2 of 2. Bring questions & notes',
            ResourceCenterService.plainText('<p>Part 2 of 2.</p><p>Bring&nbsp;questions &amp; notes</p>'),
            'Paragraphs join with a space; entities are decoded');
        Assert.areEqual('a b', ResourceCenterService.plainText('a<br>b'));
        Assert.isNull(ResourceCenterService.plainText('<p></p><ul><li></li></ul>'), 'Markup only → null');

        Assert.areEqual(new List<String>{ 'Lite users', 'Full users' },
            ResourceCenterService.splitMulti('Lite users;Full users'));
        Assert.isTrue(ResourceCenterService.splitMulti(null).isEmpty());
        Assert.isTrue(ResourceCenterService.splitMulti(';').isEmpty());
    }

    @isTest
    static void detailCarriesTheAuthoredHtmlAndListsCarryPlainText() {
        Id catId = [SELECT Id FROM Resource_Category__c WHERE Slug__c = 'marketing'].Id;
        Resource__c w = webinar('Arc Basics', 'arc-basics', catId, System.now().addDays(3), null,
            'https://example.com/register');
        w.Description__c = '<ul><li>Logging in</li><li>Search</li></ul>';
        w.Summary__c = 'The essentials of Arc for Lite users.';
        w.Audience__c = 'Lite users;Full users';
        insert w;

        ResourceCenterService.ResourceDetail d = ResourceCenterService.getResourceBySlug('arc-basics');
        Assert.areEqual('<ul><li>Logging in</li><li>Search</li></ul>', d.descriptionHtml,
            'The detail page renders the markup');
        Assert.areEqual('Logging in; Search', d.description, 'and still carries the plain form');
        Assert.areEqual('The essentials of Arc for Lite users.', d.summary);
        Assert.areEqual(new List<String>{ 'Lite users', 'Full users' }, d.audience);

        ResourceCenterService.EventsFeed feed = ResourceCenterService.getEvents();
        ResourceCenterService.WebinarItem item;
        for (ResourceCenterService.WebinarItem i : feed.upcoming) {
            if (i.slug == 'arc-basics') {
                item = i;
            }
        }
        Assert.isNotNull(item);
        Assert.areEqual('Logging in; Search', item.description, 'Feed rows never carry markup');
        Assert.areEqual('The essentials of Arc for Lite users.', item.summary);
        Assert.areEqual(2, item.audience.size());

        Boolean found = false;
        for (ResourceCenterService.ResourceCard c : ResourceCenterService.getCategoryBySlug('marketing').resources) {
            if (c.slug == 'arc-basics') {
                found = true;
                Assert.areEqual('Logging in; Search', c.description);
                Assert.areEqual('The essentials of Arc for Lite users.', c.summary);
            }
        }
        Assert.isTrue(found, 'The card grid lists the webinar');

        // A resource with no summary keeps its plain description as the subtitle.
        ResourceCenterService.ResourceDetail pdf = ResourceCenterService.getResourceBySlug('brand-flyer');
        Assert.areEqual('A printable flyer', pdf.description);
        Assert.areEqual('A printable flyer', pdf.descriptionHtml);
        Assert.isNull(pdf.summary);
        Assert.isTrue(pdf.audience.isEmpty());
    }
}