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

    @isTest
    static void relatedArticlesForResourceResolveLatestVersion() {
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
        List<ResourceCenterService.CombinedResult> combined = ResourceCenterService.searchAll('flyer');
        Test.stopTest();
        Boolean sawResource = false;
        for (ResourceCenterService.CombinedResult r : combined) {
            if (r.type == 'resource' && r.slug == 'brand-flyer') {
                sawResource = true;
            }
        }
        Assert.isTrue(sawResource, 'Combined results include the resource row.');
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
}