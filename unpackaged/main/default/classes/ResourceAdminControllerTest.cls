@IsTest
private class ResourceAdminControllerTest {

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

        List<ResourceAdminController.CategoryRow> rows = ResourceAdminController.listCategories();
        System.assert(rows.size() >= 2);

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

    @IsTest
    static void saveCategoryEnforcesDepthAndChildren() {
        Id topId = makeCategory('Depth Top', 'depth-top', null);
        Id subId = makeCategory('Depth Sub', 'depth-sub', topId);

        // A subtopic cannot be a parent (depth 2 max).
        ResourceAdminController.CategoryInput grandchild = new ResourceAdminController.CategoryInput();
        grandchild.name = 'Depth Grandchild';
        grandchild.slug = 'depth-grandchild';
        grandchild.parentId = subId;
        try {
            ResourceAdminController.saveCategory(JSON.serialize(grandchild));
            System.assert(false, 'Nesting under a subtopic must be rejected');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('top-level'), e.getMessage());
        }

        // A category with subtopics must stay top-level.
        Id otherTopId = makeCategory('Depth Other', 'depth-other', null);
        ResourceAdminController.CategoryInput demote = new ResourceAdminController.CategoryInput();
        demote.id = topId;
        demote.name = 'Depth Top';
        demote.slug = 'depth-top';
        demote.parentId = otherTopId;
        try {
            ResourceAdminController.saveCategory(JSON.serialize(demote));
            System.assert(false, 'A parent with subtopics must stay top-level');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('has subtopics'), e.getMessage());
        }

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