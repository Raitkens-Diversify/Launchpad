@IsTest
private class ResourceAdminControllerTest {

    /** The deployer's own access is not enough in production; see HelpCenterTestDataFactory. */
    @TestSetup
    static void grantAccess() {
        HelpCenterTestDataFactory.grantAdminToRunningUser();
    }

    private static Id makeCategory(String name, String slug, Id parentId) {
        Resource_Category__c c = new Resource_Category__c(
            Name = name, Slug__c = slug, Parent_Category__c = parentId, Is_Active__c = true);
        insert c;
        return c.Id;
    }

    private static ResourceAdminController.ResourceInput input(String name, String slug, Id catId) {
        ResourceAdminController.ResourceInput r = new ResourceAdminController.ResourceInput();
        r.name = name;
        r.slug = slug;
        r.resourceType = 'PDF';
        r.categoryId = catId;
        r.active = true;
        return r;
    }

    private static String publishArticle(String title, String urlName) {
        Knowledge__kav kav = new Knowledge__kav(
            Title = title, UrlName = urlName, Summary = 'About ' + title);
        insert kav;
        kav = [SELECT KnowledgeArticleId FROM Knowledge__kav WHERE Id = :kav.Id];
        KbManagement.PublishingService.publishArticle(kav.KnowledgeArticleId, true);
        return kav.KnowledgeArticleId;
    }

    @IsTest
    static void categoryCrudAndTree() {
        Id topId = makeCategory('Top Cat', 'top-cat', null);
        Id childId = makeCategory('Child Cat', 'child-cat', topId);

        CategoryTreeService.TreeDTO adminTree = ResourceAdminController.getCategoryTree();
        System.assert(adminTree.nodeCount >= 2);
        System.assert(adminTree.maxDepth >= 2, 'The limit travels with the tree');

        List<ResourceAdminController.CategoryNode> tree =
            ResourceAdminController.getResourceCategoryTree();
        ResourceAdminController.CategoryNode top;
        for (ResourceAdminController.CategoryNode n : tree) {
            if (n.name == String.valueOf(topId)) {
                top = n;
            }
        }
        System.assertNotEquals(null, top, 'Top-level category is a root node');
        System.assertEquals(1, top.children.size(), 'Child nests under its parent');
        System.assertEquals(String.valueOf(childId), top.children[0].name);

        // Re-parent + rename via saveCategory.
        ResourceAdminController.CategoryInput edit = new ResourceAdminController.CategoryInput();
        edit.id = childId;
        edit.name = 'Child Cat Renamed';
        edit.slug = 'child-cat';
        edit.parentId = null;
        edit.active = true;
        ResourceAdminController.saveCategory(JSON.serialize(edit));
        System.assertEquals(null, [
            SELECT Parent_Category__c FROM Resource_Category__c WHERE Id = :childId
        ].Parent_Category__c, 'Re-parent to top level');
    }

    @IsTest
    static void categoryGuards() {
        Id catId = makeCategory('Guard Cat', 'guard-cat', null);

        System.assertEquals(false,
            ResourceAdminController.isCategorySlugAvailable('guard-cat', null));
        System.assertEquals(true,
            ResourceAdminController.isCategorySlugAvailable('guard-cat', catId),
            'A category keeps its own slug');

        ResourceAdminController.CategoryInput selfParent = new ResourceAdminController.CategoryInput();
        selfParent.id = catId;
        selfParent.name = 'Guard Cat';
        selfParent.slug = 'guard-cat';
        selfParent.parentId = catId;
        try {
            ResourceAdminController.saveCategory(JSON.serialize(selfParent));
            System.assert(false, 'Self-parenting must be rejected');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('own parent'), e.getMessage());
        }
    }

    private static Id saveCat(String name, String slug, Id parentId) {
        ResourceAdminController.CategoryInput c = new ResourceAdminController.CategoryInput();
        c.name = name;
        c.slug = slug;
        c.parentId = parentId;
        return ResourceAdminController.saveCategory(JSON.serialize(c));
    }

    @IsTest
    static void saveCategoryNestsToTheLimitAndRefusesCycles() {
        CategoryTreeService.maxDepthOverride = 5;
        Id l1 = saveCat('Level 1', 'level-1', null);
        Id l2 = saveCat('Level 2', 'level-2', l1);
        Id l3 = saveCat('Level 3', 'level-3', l2);
        Id l4 = saveCat('Level 4', 'level-4', l3);
        Id l5 = saveCat('Level 5', 'level-5', l4);
        System.assertEquals(5, [SELECT Depth__c FROM Resource_Category__c WHERE Id = :l5].Depth__c,
            'Five levels nest through the console');

        try {
            saveCat('Level 6', 'level-6', l5);
            System.assert(false, 'A sixth level must be rejected');
        } catch (AuraHandledException e) {
            System.assertEquals(CategoryTreeService.depthMessage(5), e.getMessage());
        }

        // Moving a category into its own subtree is a cycle.
        ResourceAdminController.CategoryInput cycle = new ResourceAdminController.CategoryInput();
        cycle.id = l2;
        cycle.name = 'Level 2';
        cycle.slug = 'level-2';
        cycle.parentId = l4;
        try {
            ResourceAdminController.saveCategory(JSON.serialize(cycle));
            System.assert(false, 'A category cannot move under its own descendant');
        } catch (AuraHandledException e) {
            System.assertEquals(CategoryTreeService.MSG_DESCENDANT, e.getMessage());
        }

        // Moving a 4-tall subtree under a depth-2 node would reach level 6.
        Id otherTop = saveCat('Other Top', 'other-top', null);
        Id otherSub = saveCat('Other Sub', 'other-sub', otherTop);
        ResourceAdminController.CategoryInput tooDeep = new ResourceAdminController.CategoryInput();
        tooDeep.id = l2;
        tooDeep.name = 'Level 2';
        tooDeep.slug = 'level-2';
        tooDeep.parentId = otherSub;
        try {
            ResourceAdminController.saveCategory(JSON.serialize(tooDeep));
            System.assert(false, 'A subtree taller than the remaining depth must be rejected');
        } catch (AuraHandledException e) {
            System.assertEquals(CategoryTreeService.depthMessage(5), e.getMessage());
        }
        System.assertEquals(l1, [SELECT Parent_Category__c FROM Resource_Category__c WHERE Id = :l2].Parent_Category__c,
            'Rejected saves leave the tree alone');

        // A vanished parent gets the friendly refresh message.
        Id goneId = makeCategory('Depth Gone', 'depth-gone', null);
        delete [SELECT Id FROM Resource_Category__c WHERE Id = :goneId];
        ResourceAdminController.CategoryInput orphan = new ResourceAdminController.CategoryInput();
        orphan.name = 'Depth Orphan';
        orphan.slug = 'depth-orphan';
        orphan.parentId = goneId;
        try {
            ResourceAdminController.saveCategory(JSON.serialize(orphan));
            System.assert(false, 'A deleted parent must be rejected');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('no longer exists'), e.getMessage());
        }
    }

    @IsTest
    static void saveCategoryAppendsDisplayOrder() {
        Id topId = makeCategory('Append Top', 'append-top', null);
        update new Resource_Category__c(Id = topId, Display_Order__c = 7);

        // Create with no explicit order → lands after the max sibling.
        ResourceAdminController.CategoryInput fresh = new ResourceAdminController.CategoryInput();
        fresh.name = 'Append Next';
        fresh.slug = 'append-next';
        Id freshId = ResourceAdminController.saveCategory(JSON.serialize(fresh));
        System.assertEquals(8, [
            SELECT Display_Order__c FROM Resource_Category__c WHERE Id = :freshId
        ].Display_Order__c, 'New top-level category appends after its siblings');

        // Subtopic ordering is scoped within its parent.
        ResourceAdminController.CategoryInput sub = new ResourceAdminController.CategoryInput();
        sub.name = 'Append Sub';
        sub.slug = 'append-sub';
        sub.parentId = topId;
        Id subId = ResourceAdminController.saveCategory(JSON.serialize(sub));
        System.assertEquals(1, [
            SELECT Display_Order__c FROM Resource_Category__c WHERE Id = :subId
        ].Display_Order__c, 'First subtopic starts its own sequence');
    }

    @IsTest
    static void reorderCategoriesWritesSequentialOrder() {
        Id topA = makeCategory('Reorder A', 'reorder-a', null);
        Id topB = makeCategory('Reorder B', 'reorder-b', null);
        Id topC = makeCategory('Reorder C', 'reorder-c', null);
        Id subA = makeCategory('Reorder Sub A', 'reorder-sub-a', topA);
        Id subB = makeCategory('Reorder Sub B', 'reorder-sub-b', topA);

        ResourceAdminController.reorderCategories(
            null, JSON.serialize(new List<Id>{ topC, topA, topB }));
        Map<Id, Resource_Category__c> tops = new Map<Id, Resource_Category__c>([
            SELECT Display_Order__c FROM Resource_Category__c WHERE Parent_Category__c = null
        ]);
        System.assertEquals(1, tops.get(topC).Display_Order__c);
        System.assertEquals(2, tops.get(topA).Display_Order__c);
        System.assertEquals(3, tops.get(topB).Display_Order__c);

        // Subtopics reorder within their parent only.
        ResourceAdminController.reorderCategories(
            String.valueOf(topA), JSON.serialize(new List<Id>{ subB, subA }));
        Map<Id, Resource_Category__c> subs = new Map<Id, Resource_Category__c>([
            SELECT Display_Order__c FROM Resource_Category__c WHERE Parent_Category__c = :topA
        ]);
        System.assertEquals(1, subs.get(subB).Display_Order__c);
        System.assertEquals(2, subs.get(subA).Display_Order__c);
        System.assertEquals(1, [
            SELECT Display_Order__c FROM Resource_Category__c WHERE Id = :topC
        ].Display_Order__c, 'Reordering subtopics leaves top-level order alone');
    }

    @IsTest
    static void moveCategoryReparentsWithOrderAndRejectsBadTargets() {
        CategoryTreeService.maxDepthOverride = 5;
        Id a = makeCategory('Move A', 'move-a', null);
        Id a1 = makeCategory('Move A1', 'move-a1', a);
        Id a1x = makeCategory('Move A1x', 'move-a1x', a1);
        Id b = makeCategory('Move B', 'move-b', null);
        Id b1 = makeCategory('Move B1', 'move-b1', b);

        // a1 (with a1x) moves under b, placed before b1.
        Test.startTest();
        ResourceAdminController.moveCategory(a1, b, JSON.serialize(new List<Id>{ a1, b1 }));
        Test.stopTest();

        Map<Id, Resource_Category__c> rows = new Map<Id, Resource_Category__c>([
            SELECT Parent_Category__c, Display_Order__c, Path__c, Depth__c FROM Resource_Category__c
        ]);
        System.assertEquals(b, rows.get(a1).Parent_Category__c, 'Reparented');
        System.assertEquals(1, rows.get(a1).Display_Order__c, 'Placed first among the new siblings');
        System.assertEquals(2, rows.get(b1).Display_Order__c);
        System.assertEquals('/' + b + '/' + a1 + '/', rows.get(a1x).Path__c, 'The subtree travelled');
        System.assertEquals(3, rows.get(a1x).Depth__c);

        // Into its own descendant, and with a stale sibling list.
        try {
            ResourceAdminController.moveCategory(b, a1x, JSON.serialize(new List<Id>{ b }));
            System.assert(false, 'Moving into a descendant must be rejected');
        } catch (AuraHandledException e) {
            System.assertEquals(CategoryTreeService.MSG_DESCENDANT, e.getMessage());
        }
        try {
            // b's live children are a1 and b1; a list naming only the mover is stale.
            ResourceAdminController.moveCategory(a1x, b, JSON.serialize(new List<Id>{ a1x }));
            System.assert(false, 'A list missing live siblings must be rejected');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('changed'), e.getMessage());
        }
        try {
            ResourceAdminController.moveCategory('not-an-id', null, '[]');
            System.assert(false, 'Malformed input must fail cleanly');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('refresh'), e.getMessage());
        }
        System.assertEquals(a1, [SELECT Parent_Category__c FROM Resource_Category__c WHERE Id = :a1x].Parent_Category__c,
            'Rejected moves write nothing');
    }

    @IsTest
    static void reorderCategoriesRejectsStaleList() {
        Id topA = makeCategory('Stale A', 'stale-a', null);
        Id topB = makeCategory('Stale B', 'stale-b', null);

        // Missing a live sibling.
        try {
            ResourceAdminController.reorderCategories(
                null, JSON.serialize(new List<Id>{ topA }));
            System.assert(false, 'A submitted list missing a sibling must be rejected');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('changed'), e.getMessage());
        }

        // Foreign Id in place of a sibling.
        Id subId = makeCategory('Stale Sub', 'stale-sub', topA);
        try {
            ResourceAdminController.reorderCategories(
                null, JSON.serialize(new List<Id>{ topA, subId }));
            System.assert(false, 'A submitted list with a non-sibling must be rejected');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('changed'), e.getMessage());
        }

        // Malformed JSON gets the friendly transport error.
        try {
            ResourceAdminController.reorderCategories(null, '{not json');
            System.assert(false, 'Malformed JSON must fail cleanly');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('refresh'), e.getMessage());
        }

        System.assertEquals(null, [
            SELECT Display_Order__c FROM Resource_Category__c WHERE Id = :topB
        ].Display_Order__c, 'Rejected reorders write nothing');
    }

    @IsTest
    static void resourceSaveValidatesByType() {
        Id catId = makeCategory('Val Cat', 'val-cat', null);

        ResourceAdminController.ResourceInput video = input('A Video', 'a-video', catId);
        video.resourceType = 'Video';
        try {
            ResourceAdminController.saveResource(JSON.serialize(video));
            System.assert(false, 'Video without embed URL must fail');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Video Embed URL'), e.getMessage());
        }

        ResourceAdminController.ResourceInput ext = input('A Link', 'a-link', catId);
        ext.resourceType = 'External Link';
        try {
            ResourceAdminController.saveResource(JSON.serialize(ext));
            System.assert(false, 'External Link without URL must fail');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('External URL'), e.getMessage());
        }

        ResourceAdminController.ResourceInput noCat = input('No Cat', 'no-cat', null);
        try {
            ResourceAdminController.saveResource(JSON.serialize(noCat));
            System.assert(false, 'Missing category must fail');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('category'), e.getMessage());
        }
    }

    @IsTest
    static void summaryAndAudienceRoundTripAndTheSummaryIsCapped() {
        Id catId = makeCategory('Sum Cat', 'sum-cat', null);

        ResourceAdminController.ResourceInput r = input('Arc Basics', 'arc-basics', catId);
        r.description = '<ul><li>Logging in</li><li>Search</li></ul>';
        r.summary = '  The essentials of Arc for Lite users.  ';
        r.audience = new List<String>{ 'Lite users', ' ', 'Full users' };
        Id resId = ResourceAdminController.saveResource(JSON.serialize(r));

        Resource__c saved = [
            SELECT Description__c, Summary__c, Audience__c FROM Resource__c WHERE Id = :resId
        ];
        System.assertEquals('<ul><li>Logging in</li><li>Search</li></ul>', saved.Description__c,
            'Rich text is stored as authored');
        System.assertEquals('The essentials of Arc for Lite users.', saved.Summary__c, 'Trimmed');
        System.assertEquals('Lite users;Full users', saved.Audience__c, 'Blank selections drop out');

        ResourceAdminController.ResourceDetail d = ResourceAdminController.getResource(resId);
        System.assertEquals('The essentials of Arc for Lite users.', d.summary);
        System.assertEquals(new List<String>{ 'Lite users', 'Full users' }, d.audience);

        // Clearing: an empty selection and a blank summary null the fields.
        r.id = resId;
        r.summary = '   ';
        r.audience = new List<String>();
        ResourceAdminController.saveResource(JSON.serialize(r));
        saved = [SELECT Summary__c, Audience__c FROM Resource__c WHERE Id = :resId];
        System.assertEquals(null, saved.Summary__c);
        System.assertEquals(null, saved.Audience__c);

        r.summary = 'x'.repeat(161);
        try {
            ResourceAdminController.saveResource(JSON.serialize(r));
            System.assert(false, 'A 161-character summary must fail');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('160'), e.getMessage());
        }
    }

    @IsTest
    static void videoUrlNormalizesAndBadJsonRejected() {
        Id catId = makeCategory('Vid Cat', 'vid-cat', null);

        // Page URLs are stored in their embeddable form — the detail page iframes
        // the value directly and YouTube/Vimeo refuse to frame page URLs.
        ResourceAdminController.ResourceInput video = input('Embed Me', 'embed-me', catId);
        video.resourceType = 'Video';
        video.videoEmbedUrl = 'https://www.youtube.com/watch?v=QwZT7T-TXT0';
        Id resId = ResourceAdminController.saveResource(JSON.serialize(video));
        System.assertEquals('https://www.youtube.com/embed/QwZT7T-TXT0', [
            SELECT Video_Embed_URL__c FROM Resource__c WHERE Id = :resId
        ].Video_Embed_URL__c, 'watch URL converts to embed URL');

        System.assertEquals('https://www.youtube.com/embed/abc123XYZ_-',
            ResourceAdminController.normalizeVideoUrl('https://youtu.be/abc123XYZ_-?t=10'));
        System.assertEquals('https://player.vimeo.com/video/76979871',
            ResourceAdminController.normalizeVideoUrl('https://vimeo.com/76979871'));
        System.assertEquals('https://www.youtube.com/embed/already',
            ResourceAdminController.normalizeVideoUrl('https://www.youtube.com/embed/already'),
            'already-embeddable URLs pass through unchanged');
        try {
            ResourceAdminController.normalizeVideoUrl('http://insecure.example.com/v');
            System.assert(false, 'non-https must be rejected');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('https'), e.getMessage());
        }

        // Malformed JSON gets the friendly transport error, not a raw JSONException.
        try {
            ResourceAdminController.saveResource('{not json');
            System.assert(false, 'Malformed JSON must fail cleanly');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('refresh'), e.getMessage());
        }
    }

    @IsTest
    static void resourceSaveAndSlugChecks() {
        Id catId = makeCategory('Save Cat', 'save-cat', null);
        Id resId = ResourceAdminController.saveResource(JSON.serialize(input('Brand Flyer', 'brand-flyer', catId)));

        Resource__c saved = [
            SELECT Slug__c, Resource_Type__c, Is_Active__c FROM Resource__c WHERE Id = :resId
        ];
        System.assertEquals('brand-flyer', saved.Slug__c);
        System.assertEquals(true, saved.Is_Active__c);

        System.assertEquals(false, ResourceAdminController.isSlugAvailable('brand-flyer', null));
        System.assertEquals(true, ResourceAdminController.isSlugAvailable('brand-flyer', resId));

        try {
            ResourceAdminController.saveResource(JSON.serialize(input('Dup Flyer', 'brand-flyer', catId)));
            System.assert(false, 'Duplicate slug must fail with a friendly message');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('slug'), e.getMessage());
        }
    }

    @IsTest
    static void relatedArticleSyncFromResourceSide() {
        Id catId = makeCategory('Link Cat', 'link-cat', null);
        String ka1 = publishArticle('Linked One', 'linked-one');
        String ka2 = publishArticle('Linked Two', 'linked-two');

        ResourceAdminController.ResourceInput r = input('Linked Guide', 'linked-guide', catId);
        r.relatedArticleKaIds = new List<String>{ ka1, ka2 };
        Id resId = ResourceAdminController.saveResource(JSON.serialize(r));

        List<Article_Resource__c> links = [
            SELECT Knowledge_Article_Id__c, Article_UrlName__c
            FROM Article_Resource__c WHERE Resource__c = :resId
        ];
        System.assertEquals(2, links.size());
        for (Article_Resource__c link : links) {
            System.assert(String.isNotBlank(link.Article_UrlName__c),
                'UrlName resolved server-side');
        }

        // Drop one on the next save.
        r.id = resId;
        r.relatedArticleKaIds = new List<String>{ ka2 };
        ResourceAdminController.saveResource(JSON.serialize(r));
        links = [SELECT Knowledge_Article_Id__c FROM Article_Resource__c WHERE Resource__c = :resId];
        System.assertEquals(1, links.size());
        System.assertEquals(ka2, links[0].Knowledge_Article_Id__c);

        // Bogus KA Id â†’ friendly failure (the picker never produces one, but the
        // server must not trust the client).
        r.relatedArticleKaIds = new List<String>{ 'kA0000000000000AAA' };
        try {
            ResourceAdminController.saveResource(JSON.serialize(r));
            System.assert(false, 'Unpublished/unknown KA Id must fail');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('no longer published'), e.getMessage());
        }

        // Detail view resolves titles.
        ResourceAdminController.ResourceDetail detail = ResourceAdminController.getResource(resId);
        System.assertEquals(1, detail.relatedArticles.size());
        System.assertEquals('Linked Two', detail.relatedArticles[0].title);
    }

    @IsTest
    static void filesListAndRemove() {
        Id catId = makeCategory('File Cat', 'file-cat', null);
        Id resId = ResourceAdminController.saveResource(JSON.serialize(input('File Guide', 'file-guide', catId)));

        ContentVersion cv = new ContentVersion(
            Title = 'Guide v1',
            PathOnClient = 'guide.pdf',
            VersionData = Blob.valueOf('pdf-bytes'),
            FirstPublishLocationId = resId
        );
        insert cv;

        List<ResourceAdminController.FileInfo> files = ResourceAdminController.getFiles(resId);
        System.assertEquals(1, files.size());
        System.assertEquals(true, files[0].isCurrent, 'Newest link is the served file');

        ResourceAdminController.removeFile(resId, files[0].contentDocumentId);
        System.assertEquals(0, ResourceAdminController.getFiles(resId).size(),
            'Link removed; the file no longer serves for this resource');
    }

    @IsTest
    static void articlePickerReturnsKaIds() {
        String kaId = publishArticle('Pickable Link Article', 'pickable-link-article');

        List<ResourceAdminController.PickItem> items =
            ResourceAdminController.searchArticlesForLink('Pickable Link');
        System.assertEquals(1, items.size());
        System.assertEquals(kaId, items[0].value, 'Picker value is the stable KA Id');
        System.assertEquals(0,
            ResourceAdminController.searchArticlesForLink('x').size(),
            'Sub-2-character terms return nothing');
    }

    @IsTest
    static void minimalUserIsRejected() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1];
        User u = new User(
            Alias = 'resmin',
            Email = 'res.min@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'ResMin',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Denver',
            UserName = 'res.min.' + System.currentTimeMillis() + '@example.com.cosmosdev'
        );
        insert u;
        System.runAs(u) {
            try {
                ResourceAdminController.listResources();
                System.assert(false, 'Expected an access exception');
            } catch (AuraHandledException e) {
                System.assert(true);
            }
            try {
                ResourceAdminController.reorderCategories(null, '[]');
                System.assert(false, 'Expected an access exception from reorderCategories');
            } catch (AuraHandledException e) {
                System.assert(true);
            }
            try {
                ResourceAdminController.deleteCategory(null, 'block');
                System.assert(false, 'Expected an access exception from deleteCategory');
            } catch (AuraHandledException e) {
                System.assert(true);
            }
        }
    }

    // ---- Category delete -------------------------------------------------------------

    @IsTest
    static void deleteCategoryRemovesEmptyCategory() {
        Id catId = makeCategory('Lonely', 'lonely', null);

        ResourceAdminController.CategoryDeleteImpactDTO impact =
            ResourceAdminController.getCategoryDeleteImpact(catId);
        System.assertEquals('Lonely', impact.name);
        System.assertEquals(0, impact.resourceCount);
        System.assertEquals(0, impact.childCount);
        System.assertEquals(0, impact.descendantCount);
        System.assertEquals(0, impact.guideOptionCount);

        Test.startTest();
        ResourceAdminController.deleteCategory(catId, null);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Resource_Category__c WHERE Id = :catId],
            'Empty category is gone');
    }

    @IsTest
    static void deleteCategoryWithSubtopicsBlocksOrMovesThemUp() {
        Id grand = makeCategory('Grand', 'grand', null);
        Id parentId = makeCategory('Parent', 'parent', grand);
        Id subA = makeCategory('Sub A', 'sub-a', parentId);
        Id subB = makeCategory('Sub B', 'sub-b', parentId);
        Id leaf = makeCategory('Leaf', 'leaf', subB);
        update new List<Resource_Category__c>{
            new Resource_Category__c(Id = subA, Display_Order__c = 1),
            new Resource_Category__c(Id = subB, Display_Order__c = 2)
        };

        // "block" with an empty subtree: the subtopics themselves are the blocker.
        try {
            ResourceAdminController.deleteCategory(parentId, 'block');
            System.assert(false, 'A category with subtopics must not delete in block mode');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('subtopic'), e.getMessage());
        }

        insert new Resource__c(
            Name = 'Deep Doc', Slug__c = 'deep-doc', Category__c = leaf, Resource_Type__c = 'PDF');
        ResourceAdminController.CategoryDeleteImpactDTO impact =
            ResourceAdminController.getCategoryDeleteImpact(parentId);
        System.assertEquals(2, impact.childCount);
        System.assertEquals(3, impact.descendantCount);
        System.assertEquals(grand, impact.parentId, 'Children would move up to Grand');
        System.assertEquals('Grand', impact.parentName);
        System.assertEquals(1, impact.resourceCount, 'The subtree holds one resource');
        System.assertEquals(0, impact.ownResourceCount, 'Nothing lives on Parent itself');

        // "block" with content below: the content is reported first — it blocks either mode.
        try {
            ResourceAdminController.deleteCategory(parentId, 'block');
            System.assert(false, 'A category with resources below must not delete in block mode');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('resource'), e.getMessage());
        }
        System.assertEquals(5, [SELECT COUNT() FROM Resource_Category__c], 'Nothing was deleted');

        // "reparent": children move up to Grand after its existing siblings, keeping order.
        Test.startTest();
        ResourceAdminController.deleteCategory(parentId, 'reparent');
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Resource_Category__c WHERE Id = :parentId], 'Parent is gone');
        Map<Id, Resource_Category__c> rows = new Map<Id, Resource_Category__c>([
            SELECT Parent_Category__c, Display_Order__c, Path__c, Depth__c FROM Resource_Category__c
        ]);
        System.assertEquals(grand, rows.get(subA).Parent_Category__c, 'Sub A moved up');
        System.assertEquals(grand, rows.get(subB).Parent_Category__c, 'Sub B moved up');
        System.assert(rows.get(subA).Display_Order__c < rows.get(subB).Display_Order__c, 'Order kept');
        System.assertEquals('/' + grand + '/' + subB + '/', rows.get(leaf).Path__c, 'Grandchild path rewritten');
        System.assertEquals(3, rows.get(leaf).Depth__c);
        System.assertEquals(1, [SELECT COUNT() FROM Resource__c WHERE Category__c = :leaf], 'Content untouched');
    }

    @IsTest
    static void deleteCategoryBlockedByResources() {
        Id parentId = makeCategory('Busy', 'busy', null);
        Id subId = makeCategory('Busy Sub', 'busy-sub', parentId);
        insert new Resource__c(
            Name = 'In Sub', Slug__c = 'in-sub', Category__c = subId, Resource_Type__c = 'PDF');

        System.assertEquals(1,
            ResourceAdminController.getCategoryDeleteImpact(parentId).resourceCount,
            'Resources under a subtopic count against the parent');

        for (Id target : new List<Id>{ parentId, subId }) {
            try {
                ResourceAdminController.deleteCategory(target, 'block');
                System.assert(false, 'A category with resources must not delete');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('resource'), e.getMessage());
                System.assert(!e.getMessage().contains('DELETE_FAILED'),
                    'Friendly guard, not the DML error: ' + e.getMessage());
            }
        }
        System.assertEquals(2, [
            SELECT COUNT() FROM Resource_Category__c WHERE Id IN :new Set<Id>{ parentId, subId }
        ], 'Nothing was deleted');
    }

    @IsTest
    static void deleteCategoryBlockedByHelpGuideOption() {
        Id catId = makeCategory('Guide Target', 'guide-target', null);
        Id subId = makeCategory('Guide Sub', 'guide-sub', catId);
        Help_Guide_Draft__c guide = new Help_Guide_Draft__c(Guide_Key__c = 'del_probe', Label__c = 'Probe');
        insert guide;
        Help_Guide_Node_Draft__c node = new Help_Guide_Node_Draft__c(
            Guide__c = guide.Id, Is_Root__c = true, Question__c = 'Where to?');
        insert node;
        insert new Help_Guide_Option_Draft__c(
            Node__c = node.Id, Label__c = 'Go', Target_Type__c = 'category',
            Target_Value__c = 'guide-sub');

        System.assertEquals(1,
            ResourceAdminController.getCategoryDeleteImpact(catId).guideOptionCount,
            'A guide option targeting a subtopic slug counts against the parent');

        try {
            ResourceAdminController.deleteCategory(catId, 'block');
            System.assert(false, 'A guide-linked category must not delete');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Help Guide Builder'), e.getMessage());
        }
        System.assertEquals(2, [
            SELECT COUNT() FROM Resource_Category__c WHERE Id IN :new Set<Id>{ catId, subId }
        ], 'Nothing was deleted');
    }

    @IsTest
    static void deleteCategoryBlockedBySecondaryPlacement() {
        Id homeId = makeCategory('Home', 'home', null);
        Id alsoId = makeCategory('Also', 'also', null);
        Id alsoSubId = makeCategory('Also Sub', 'also-sub', alsoId);
        ResourceAdminController.ResourceInput r = input('Shared Doc', 'shared-doc', homeId);
        r.secondaryCategoryIds = new List<String>{ alsoSubId };
        ResourceAdminController.saveResource(JSON.serialize(r));

        ResourceAdminController.CategoryDeleteImpactDTO impact =
            ResourceAdminController.getCategoryDeleteImpact(alsoId);
        System.assertEquals(0, impact.resourceCount, 'No resource lives here');
        System.assertEquals(1, impact.secondaryCount, 'One resource is also shown under a subtopic');

        for (Id target : new List<Id>{ alsoId, alsoSubId }) {
            try {
                ResourceAdminController.deleteCategory(target, 'block');
                System.assert(false, 'A category with secondary placements must not delete');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('also shown in it'), e.getMessage());
            }
        }
        System.assertEquals(2, [
            SELECT COUNT() FROM Resource_Category__c WHERE Id IN :new Set<Id>{ alsoId, alsoSubId }
        ], 'Nothing was deleted');
    }

    // ---- "Also show in" (secondary categories) ------------------------------------

    @IsTest
    static void secondaryCategoriesSyncInsertReplaceClearNull() {
        Id a = makeCategory('A', 'a', null);
        Id b = makeCategory('B', 'b', null);
        Id c = makeCategory('C', 'c', null);
        ResourceAdminController.ResourceInput r = input('Multi', 'multi', a);
        r.secondaryCategoryIds = new List<String>{ b, c };
        Id resId = ResourceAdminController.saveResource(JSON.serialize(r));
        System.assertEquals(2, [SELECT COUNT() FROM Resource_Category_Link__c WHERE Resource__c = :resId]);
        System.assertEquals(new Set<Id>{ b, c },
            new Set<Id>(ResourceAdminController.getResource(resId).secondaryCategoryIds),
            'Detail echoes the placements');

        r.id = resId;
        r.secondaryCategoryIds = new List<String>{ c };
        ResourceAdminController.saveResource(JSON.serialize(r));
        System.assertEquals(new List<Id>{ c },
            ResourceAdminController.getResource(resId).secondaryCategoryIds, 'Replaced');

        r.secondaryCategoryIds = null;
        ResourceAdminController.saveResource(JSON.serialize(r));
        System.assertEquals(1, [SELECT COUNT() FROM Resource_Category_Link__c WHERE Resource__c = :resId],
            'null leaves placements untouched');

        r.secondaryCategoryIds = new List<String>();
        ResourceAdminController.saveResource(JSON.serialize(r));
        System.assertEquals(0, [SELECT COUNT() FROM Resource_Category_Link__c WHERE Resource__c = :resId],
            'Empty list clears');
    }

    @IsTest
    static void secondaryCategoriesStripHomeAndDedupe() {
        Id a = makeCategory('A', 'a', null);
        Id b = makeCategory('B', 'b', null);
        ResourceAdminController.ResourceInput r = input('Stripped', 'stripped', a);
        r.secondaryCategoryIds = new List<String>{ a, b, b };
        Id resId = ResourceAdminController.saveResource(JSON.serialize(r));
        List<Resource_Category_Link__c> links = [
            SELECT Category__c FROM Resource_Category_Link__c WHERE Resource__c = :resId
        ];
        System.assertEquals(1, links.size(), 'Home stripped, duplicate collapsed');
        System.assertEquals(b, links[0].Category__c);

        // Moving the home onto B with the list untouched drops the self-link.
        r.id = resId;
        r.categoryId = b;
        r.secondaryCategoryIds = null;
        ResourceAdminController.saveResource(JSON.serialize(r));
        System.assertEquals(0, [SELECT COUNT() FROM Resource_Category_Link__c WHERE Resource__c = :resId],
            'A placement equal to the new home is removed even when untouched');
    }

    @IsTest
    static void secondaryCategoriesRejectUnknownId() {
        Id a = makeCategory('A', 'a', null);
        for (String bad : new List<String>{ 'a0X000000000000AAA', 'nope' }) {
            ResourceAdminController.ResourceInput r = input('Bad ' + bad, 'bad-' + bad.toLowerCase(), a);
            r.secondaryCategoryIds = new List<String>{ bad };
            try {
                ResourceAdminController.saveResource(JSON.serialize(r));
                System.assert(false, 'Unknown category must be rejected: ' + bad);
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('no longer exists'), e.getMessage());
            }
        }
        System.assertEquals(0, [SELECT COUNT() FROM Resource__c WHERE Category__c = :a],
            'The save rolled back with the failed placement');
    }

    @IsTest
    static void listSurfacesSecondaryNamesAndCounts() {
        Id a = makeCategory('Alpha', 'alpha', null);
        Id b = makeCategory('Beta', 'beta', null);
        ResourceAdminController.ResourceInput r = input('Listed', 'listed', a);
        r.secondaryCategoryIds = new List<String>{ b };
        Id resId = ResourceAdminController.saveResource(JSON.serialize(r));

        ResourceAdminController.ResourceRow found;
        for (ResourceAdminController.ResourceRow row : ResourceAdminController.listResources()) {
            if (row.id == resId) {
                found = row;
            }
        }
        System.assertEquals('Alpha', found.categoryName, 'Home category');
        System.assertEquals(new List<String>{ 'Beta' }, found.secondaryCategoryNames);

        for (CategoryTreeService.TreeNode node : ResourceAdminController.getCategoryTree().roots) {
            if (node.id == String.valueOf(b)) {
                System.assertEquals(0, node.itemCount, 'Nothing lives in Beta');
                System.assertEquals(1, node.secondaryItemCount, 'One resource is also shown in Beta');
                System.assertEquals(1, node.descendantItemCount, 'Shown-here counts roll up');
            }
        }
    }

    @IsTest
    static void deleteCategoryMissingIdRejected() {
        Id catId = makeCategory('Gone', 'gone', null);
        delete new Resource_Category__c(Id = catId);
        try {
            ResourceAdminController.getCategoryDeleteImpact(catId);
            System.assert(false, 'A vanished category must be reported');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('no longer exists'), e.getMessage());
        }
    }

    // ---- Webinars ------------------------------------------------------------------

    @IsTest
    static void webinarSaveValidatesLifecycleFieldsAndRoundTrips() {
        Id catId = makeCategory('Web Cat', 'web-cat', null);
        ResourceAdminController.ResourceInput w = input('A Webinar', 'a-webinar', catId);
        w.resourceType = 'Webinar';
        try {
            ResourceAdminController.saveResource(JSON.serialize(w));
            System.assert(false, 'Webinar without an event date must fail');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('event date'), e.getMessage());
        }

        w.eventDatetime = System.now().addDays(3);
        try {
            ResourceAdminController.saveResource(JSON.serialize(w));
            System.assert(false, 'Upcoming webinar without a registration URL must fail');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('registration URL'), e.getMessage());
        }

        w.registrationUrl = 'http://insecure.example.com/register';
        try {
            ResourceAdminController.saveResource(JSON.serialize(w));
            System.assert(false, 'Non-https registration URL must fail');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('https://'), e.getMessage());
        }

        w.registrationUrl = 'https://example.com/register';
        w.durationMinutes = 1000;
        try {
            ResourceAdminController.saveResource(JSON.serialize(w));
            System.assert(false, 'Out-of-range duration must fail');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Duration'), e.getMessage());
        }

        w.durationMinutes = 45;
        w.presenter = 'Jane Doe';
        Id upId = ResourceAdminController.saveResource(JSON.serialize(w));
        Resource__c saved = [
            SELECT Event_Datetime__c, Registration_URL__c, Event_Duration_Minutes__c, Presenter__c
            FROM Resource__c WHERE Id = :upId
        ];
        System.assertEquals('https://example.com/register', saved.Registration_URL__c);
        System.assertEquals(45, saved.Event_Duration_Minutes__c.intValue());
        System.assertEquals('Jane Doe', saved.Presenter__c);
        System.assertNotEquals(null, saved.Event_Datetime__c);

        // A past webinar needs no registration URL (it is Past until a recording lands).
        ResourceAdminController.ResourceInput past = input('Past Webinar', 'past-webinar', catId);
        past.resourceType = 'Webinar';
        past.eventDatetime = System.now().addDays(-1);
        Id pastId = ResourceAdminController.saveResource(JSON.serialize(past));

        ResourceAdminController.ResourceDetail detail = ResourceAdminController.getResource(upId);
        System.assertEquals('https://example.com/register', detail.registrationUrl);
        System.assertEquals(45, detail.durationMinutes.intValue());
        System.assertEquals('Jane Doe', detail.presenter);
        System.assertNotEquals(null, detail.eventDatetime);

        Map<String, ResourceAdminController.ResourceRow> bySlug =
            new Map<String, ResourceAdminController.ResourceRow>();
        for (ResourceAdminController.ResourceRow row : ResourceAdminController.listResources()) {
            bySlug.put(row.slug, row);
        }
        System.assertEquals('Upcoming', bySlug.get('a-webinar').webinarStatus,
            'List rows carry the lifecycle chip value');
        System.assertEquals('Past', bySlug.get('past-webinar').webinarStatus,
            'A past webinar without a recording needs one');
        System.assertNotEquals(null, bySlug.get('past-webinar').eventDatetime);

        // Attaching a recording flips the list chip — no type or slug change.
        ContentVersion cv = new ContentVersion(
            Title = 'replay.mp4', PathOnClient = 'replay.mp4', VersionData = Blob.valueOf('bytes'));
        insert cv;
        Id cdId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
        insert new ContentDocumentLink(
            LinkedEntityId = pastId, ContentDocumentId = cdId, ShareType = 'V', Visibility = 'AllUsers');
        for (ResourceAdminController.ResourceRow row : ResourceAdminController.listResources()) {
            if (row.slug == 'past-webinar') {
                System.assertEquals('Recorded', row.webinarStatus, 'Recording attached');
                System.assertEquals('Webinar', row.resourceType, 'Type never flips');
            }
        }
    }

    @IsTest
    static void typeSwitchClearsWebinarFields() {
        Id catId = makeCategory('Switch Cat', 'switch-cat', null);
        ResourceAdminController.ResourceInput w = input('Was Webinar', 'was-webinar', catId);
        w.resourceType = 'Webinar';
        w.eventDatetime = System.now().addDays(-2);
        w.presenter = 'Jane Doe';
        w.durationMinutes = 30;
        Id id = ResourceAdminController.saveResource(JSON.serialize(w));

        w.id = id;
        w.resourceType = 'PDF';
        ResourceAdminController.saveResource(JSON.serialize(w));
        Resource__c saved = [
            SELECT Resource_Type__c, Event_Datetime__c, Registration_URL__c,
                   Event_Duration_Minutes__c, Presenter__c
            FROM Resource__c WHERE Id = :id
        ];
        System.assertEquals('PDF', saved.Resource_Type__c);
        System.assertEquals(null, saved.Event_Datetime__c, 'Stale event data never survives a type switch');
        System.assertEquals(null, saved.Presenter__c);
        System.assertEquals(null, saved.Event_Duration_Minutes__c);
        Resource__c flags = [SELECT Announce_On_Arc__c, Announce_At__c FROM Resource__c WHERE Id = :id];
        System.assertEquals(false, flags.Announce_On_Arc__c, 'Announcement flag clears with the type');
        System.assertEquals(null, flags.Announce_At__c);
    }

    @IsTest
    static void announcementFieldsRoundTripAndMustPrecedeTheEvent() {
        Id catId = makeCategory('Ann Cat', 'ann-cat', null);
        ResourceAdminController.ResourceInput w = input('Announced Webinar', 'announced-webinar', catId);
        w.resourceType = 'Webinar';
        w.eventDatetime = System.now().addDays(3);
        w.registrationUrl = 'https://example.com/register';
        w.announceOnArc = true;
        w.announceAt = w.eventDatetime.addMinutes(5);
        try {
            ResourceAdminController.saveResource(JSON.serialize(w));
            System.assert(false, 'Announcing after the event starts must fail');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('before the event'), e.getMessage());
        }

        w.announceAt = null; // the 8:00 AM default
        Id id = ResourceAdminController.saveResource(JSON.serialize(w));
        ResourceAdminController.ResourceDetail detail = ResourceAdminController.getResource(id);
        System.assertEquals(true, detail.announceOnArc);
        System.assertEquals(null, detail.announceAt);
        System.assertNotEquals(null, detail.effectiveAnnounceAt, 'The default time is reported');
        System.assert(detail.effectiveAnnounceAt < w.eventDatetime, 'Default precedes the event');
        System.assertEquals('Scheduled', detail.announcementStatus);

        w.id = id;
        w.announceAt = w.eventDatetime.addDays(-1);
        ResourceAdminController.saveResource(JSON.serialize(w));
        detail = ResourceAdminController.getResource(id);
        System.assertEquals(w.announceAt, detail.announceAt);
        System.assertEquals(w.announceAt, detail.effectiveAnnounceAt, 'An explicit time is the effective time');

        w.announceOnArc = false;
        ResourceAdminController.saveResource(JSON.serialize(w));
        detail = ResourceAdminController.getResource(id);
        System.assertEquals(false, detail.announceOnArc);
        System.assertEquals(null, detail.announcementStatus, 'No status line when not flagged');

        // Non-webinars never carry the flag, whatever the input says.
        ResourceAdminController.ResourceInput pdf = input('Plain', 'plain-ann', catId);
        pdf.announceOnArc = true;
        Id pdfId = ResourceAdminController.saveResource(JSON.serialize(pdf));
        System.assertEquals(false, ResourceAdminController.getResource(pdfId).announceOnArc);
    }

    @IsTest
    static void webinarValidationRulesGuardDirectDml() {
        Id catId = makeCategory('VR Cat', 'vr-cat', null);
        Resource__c noDate = new Resource__c(
            Name = 'No Date', Slug__c = 'no-date', Category__c = catId, Resource_Type__c = 'Webinar');
        try {
            insert noDate;
            System.assert(false, 'Webinar_Requires_Event_Datetime must block');
        } catch (DmlException e) {
            System.assert(e.getMessage().contains('event date'), e.getMessage());
        }

        Resource__c upcomingNoReg = new Resource__c(
            Name = 'No Reg', Slug__c = 'no-reg', Category__c = catId, Resource_Type__c = 'Webinar',
            Event_Datetime__c = System.now().addDays(1));
        try {
            insert upcomingNoReg;
            System.assert(false, 'Webinar_Upcoming_Requires_Registration must block');
        } catch (DmlException e) {
            System.assert(e.getMessage().contains('registration'), e.getMessage());
        }

        Resource__c pastNoReg = new Resource__c(
            Name = 'Past No Reg', Slug__c = 'past-no-reg', Category__c = catId,
            Resource_Type__c = 'Webinar', Event_Datetime__c = System.now().addDays(-1));
        insert pastNoReg; // past webinars do not need a registration link
        System.assertNotEquals(null, pastNoReg.Id);

        Resource__c pdf = new Resource__c(
            Name = 'Plain PDF', Slug__c = 'plain-pdf', Category__c = catId, Resource_Type__c = 'PDF');
        insert pdf; // rules are webinar-only
        System.assertNotEquals(null, pdf.Id);
    }
}