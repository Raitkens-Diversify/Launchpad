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
        List<ResourceCenterService.NavTopic> nav = ResourceCenterService.getCategoryNav();
        Test.stopTest();

        Map<String, ResourceCenterService.NavTopic> bySlug =
            new Map<String, ResourceCenterService.NavTopic>();
        for (ResourceCenterService.NavTopic t : nav) {
            bySlug.put(t.slug, t);
        }
        Assert.isTrue(bySlug.containsKey('marketing'), 'Marketing is a nav topic.');
        Assert.isTrue(bySlug.containsKey('empty-top'),
            'A main topic with no resources still shows in the nav.');
        Assert.isFalse(bySlug.containsKey('hidden'), 'Inactive categories never show.');

        ResourceCenterService.NavTopic marketing = bySlug.get('marketing');
        Assert.areEqual(1, marketing.children.size(),
            'Only Flyers qualifies — the empty subcategory is hidden from the nav.');
        Assert.areEqual('flyers', marketing.children[0].slug);
        Assert.areEqual(0, bySlug.get('empty-top').children.size());
    }

    @isTest
    static void resourceBySlugCarriesCategoryParent() {
        Test.startTest();
        ResourceCenterService.ResourceDetail nested = ResourceCenterService.getResourceBySlug('brand-flyer');
        ResourceCenterService.ResourceDetail direct = ResourceCenterService.getResourceBySlug('partner-site');
        Test.stopTest();

        Assert.areEqual('marketing', nested.categoryParentSlug,
            'A subtopic-filed resource reports its main topic for the crumb.');
        Assert.areEqual('Marketing', nested.categoryParentName);
        Assert.isNull(direct.categoryParentSlug,
            'A resource filed directly on a main topic has no parent crumb segment.');
        Assert.isNull(direct.categoryParentName);
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
        List<ResourceCenterService.ResourceCard> hits = ResourceCenterService.searchResources('flyer');
        Test.stopTest();
        Assert.areEqual(1, hits.size(), 'Fixed SOSL result returned.');
        Assert.areEqual('brand-flyer', hits[0].slug, 'Matched the flyer.');
    }

    @isTest
    static void typeaheadMatchesByName() {
        Test.startTest();
        List<ResourceCenterService.ResourceCard> hits = ResourceCenterService.typeahead('Brand');
        List<ResourceCenterService.ResourceCard> none = ResourceCenterService.typeahead('   ');
        Test.stopTest();
        Assert.areEqual(1, hits.size(), 'Brand Flyer matches "Brand".');
        Assert.areEqual('brand-flyer', hits[0].slug, 'Typeahead carries the slug for selection.');
        Assert.areEqual(0, none.size(), 'Blank term returns nothing.');
    }

    @isTest
    static void searchResourcesBlankTermIsEmpty() {
        Assert.areEqual(0, ResourceCenterService.searchResources('   ').size(),
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
    static void resourceLinkBaseIsWellFormedOrNull() {
        // Site/SiteDetail can't be created in tests, so assert the contract:
        // never throws; when the org has the configured LWR site, the base is
        // the site's secure URL plus the Resources page path.
        Test.startTest();
        String base = ResourceCenterService.getResourceLinkBase();
        Test.stopTest();
        if (base != null) {
            Assert.isTrue(base.startsWith('https://'), 'Absolute URL expected: ' + base);
            Assert.isTrue(base.endsWith('/resources'), 'Resources page path expected: ' + base);
            Assert.isFalse(base.contains('//resources'), 'No double slash before the page path: ' + base);
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
        // with the real ARC row shape (customMetadata/Help_Surface.ARC).
        ResourceCenterService.surfaceOverride = 'ARC';
        ResourceCenterService.surfaceRows = new Map<String, Help_Surface__mdt>{
            'ARC' => new Help_Surface__mdt(
                Network_Name__c = 'ARC', Home_Path__c = 'help-center', Article_Path__c = 'article',
                Resources_Path__c = 'learning', Events_Path__c = 'events')
        };
        ResourceCenterService.siteBaseOverride.put('ARC', 'https://x.my.site.com/ARC');

        Test.startTest();
        ResourceCenterService.LinkContext ctx = ResourceCenterService.getLinkContext();
        Test.stopTest();

        Assert.areEqual('ARC', ctx.surface);
        Assert.areEqual('https://x.my.site.com/ARC', ctx.helpBase, 'The CURRENT site root, not /help');
        Assert.areEqual('https://x.my.site.com/ARC/help-center', ctx.homeBase);
        Assert.areEqual('https://x.my.site.com/ARC/article', ctx.articleBase);
        Assert.areEqual('https://x.my.site.com/ARC/learning', ctx.resourceBase);
        Assert.areEqual('https://x.my.site.com/ARC/events', ctx.eventsBase);
    }

    @isTest
    static void linkContextBlankPathsMeanRootAndDefaults() {
        ResourceCenterService.surfaceOverride = 'Diversify Help Center';
        ResourceCenterService.surfaceRows = new Map<String, Help_Surface__mdt>{
            'Diversify Help Center' => new Help_Surface__mdt(Network_Name__c = 'Diversify Help Center')
        };
        ResourceCenterService.siteBaseOverride.put('Diversify Help Center', 'https://x.my.site.com/help');

        ResourceCenterService.LinkContext ctx = ResourceCenterService.getLinkContext();

        Assert.areEqual('https://x.my.site.com/help', ctx.homeBase, 'Blank home = the site root');
        Assert.areEqual('https://x.my.site.com/help/article', ctx.articleBase);
        Assert.areEqual('https://x.my.site.com/help/resources', ctx.resourceBase);
        Assert.areEqual('https://x.my.site.com/help/events', ctx.eventsBase);
    }

    @isTest
    static void linkContextFallsBackToTheSharedSiteForUnmappedNetworks() {
        // No row for this network: the pre-table behavior — the shared Help
        // Center site with the default page names (or null bases when even
        // that can't be resolved; Site/SiteDetail can't be created in tests).
        ResourceCenterService.surfaceOverride = 'Some Other Site';
        ResourceCenterService.surfaceRows = new Map<String, Help_Surface__mdt>();

        Test.startTest();
        ResourceCenterService.LinkContext ctx = ResourceCenterService.getLinkContext();
        String shared = ResourceCenterService.getHelpCenterLinkBase();
        Test.stopTest();

        Assert.areEqual('Some Other Site', ctx.surface);
        Assert.areEqual(shared, ctx.helpBase, 'Unmapped network → the shared site root');
        if (ctx.helpBase != null) {
            Assert.areEqual(ctx.helpBase, ctx.homeBase);
            Assert.areEqual(ctx.helpBase + '/article', ctx.articleBase);
            Assert.areEqual(ctx.helpBase + '/resources', ctx.resourceBase);
            Assert.areEqual(ctx.helpBase + '/events', ctx.eventsBase);
        } else {
            Assert.isNull(ctx.resourceBase, 'No site, no bases');
        }
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
            Assert.areEqual(helpBase, ctx.helpBase, 'Same help base either way');
            Assert.areEqual(resourceBase, ctx.resourceBase, 'Same resource base either way');
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
            Assert.areEqual(base + '/resources', resourcesBase,
                'Resources base is the site root plus the page path');
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

    // ---- Link bases are site-relative ON the Help Center site ----------------

    @isTest
    static void linkBasesAreSiteRelativeOnTheHelpSite() {
        // Running on the shared site itself: a link built from the base must be
        // a same-site hop, not a host-absolute one.
        ResourceCenterService.surfaceOverride = 'Diversify Help Center';
        ResourceCenterService.helpSiteLabelOverride = 'Diversify Help Center';

        Test.startTest();
        String helpBase = ResourceCenterService.getHelpCenterLinkBase();
        String resourceBase = ResourceCenterService.getResourceLinkBase();
        Test.stopTest();

        Assert.areEqual('/help', helpBase, 'Site-relative root on the help site');
        Assert.areEqual('/help/resources', resourceBase);
    }

    @isTest
    static void linkBasesStayAbsoluteOffTheHelpSite() {
        // Another site (ARC's sidebar links to the Help Center) still needs the
        // full URL of the OTHER site — never a relative path.
        ResourceCenterService.surfaceOverride = 'ARC';
        ResourceCenterService.helpSiteLabelOverride = 'Diversify Help Center';

        Test.startTest();
        String helpBase = ResourceCenterService.getHelpCenterLinkBase();
        Test.stopTest();

        if (helpBase != null) {
            Assert.isTrue(helpBase.startsWith('https://'), 'Absolute off-site: ' + helpBase);
        }
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
}