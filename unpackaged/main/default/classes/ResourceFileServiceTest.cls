@isTest
private class ResourceFileServiceTest {

    // Fabricated ContentDocument Id (069 prefix) — buildDownloadUrl only formats.
    private static final Id FAKE_CD = '069000000000001AAA';

    @isTest
    static void nullReturnsNull() {
        Assert.isNull(ResourceFileService.buildDownloadUrl(null), 'Null id -> null url.');
    }

    @isTest
    static void defaultModeIsShepherd() {
        String url = ResourceFileService.buildDownloadUrl(FAKE_CD);
        Assert.isTrue(url.startsWith('/sfc/servlet.shepherd/document/download/'),
            'Default (or missing) setting resolves to the Shepherd URL.');
        Assert.isTrue(url.endsWith(FAKE_CD), 'The ContentDocumentId is appended.');
    }

    @isTest
    static void shepherdStrategyDirect() {
        ResourceFileService.ShepherdUrlStrategy s = new ResourceFileService.ShepherdUrlStrategy();
        Assert.areEqual('/sfc/servlet.shepherd/document/download/' + FAKE_CD, s.buildDownloadUrl(FAKE_CD));
    }

    @isTest
    static void resolvePublicDownloadUrlShepherdModeUsesAuthenticatedUrl() {
        // Default delivery mode is Shepherd: no ContentDistribution is minted,
        // the click-time resolver hands back the same authenticated URL.
        Assert.isNull(ResourceFileService.resolvePublicDownloadUrl(null), 'Null id -> null url.');
        String url = ResourceFileService.resolvePublicDownloadUrl(FAKE_CD);
        Assert.areEqual(ResourceFileService.buildDownloadUrl(FAKE_CD), url,
            'Shepherd mode resolves to the authenticated download URL.');
        Assert.areEqual(0, [SELECT COUNT() FROM ContentDistribution],
            'No public link is created outside ContentDistribution mode.');
    }

    @isTest
    static void resolvePublicDownloadUrlContentDistributionModeMintsOnce() {
        ContentVersion cv = new ContentVersion(
            Title = 'Flyer', PathOnClient = 'flyer.pdf', VersionData = Blob.valueOf('flyer'));
        insert cv;
        cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
        ResourceFileService.deliveryModeOverride = 'ContentDistribution';

        Test.startTest();
        String first = ResourceFileService.resolvePublicDownloadUrl(cv.ContentDocumentId);
        String second = ResourceFileService.resolvePublicDownloadUrl(cv.ContentDocumentId);
        Test.stopTest();

        // Either the public link (content deliveries on) or the authenticated
        // fallback (off) — never blank, and a second click reuses the first.
        Assert.isTrue(String.isNotBlank(first), 'A download URL always comes back.');
        Assert.areEqual(first, second, 'A second click reuses the same link.');
        Assert.isTrue([SELECT COUNT() FROM ContentDistribution WHERE ContentVersionId = :cv.Id] <= 1,
            'At most one public link is minted per version.');
        // No version behind the id: the authenticated URL is the answer.
        Assert.areEqual(ResourceFileService.buildDownloadUrl(FAKE_CD),
            ResourceFileService.resolvePublicDownloadUrl(FAKE_CD),
            'Unknown documents fall back to the Shepherd URL.');
    }

    @isTest
    static void contentDistributionStrategyFallsBack() {
        ResourceFileService.strategyOverride = new ResourceFileService.ContentDistributionStrategy();
        String url = ResourceFileService.buildDownloadUrl(FAKE_CD);
        Assert.isTrue(url.startsWith('/sfc/servlet.shepherd/document/download/'),
            'The stub falls back to the authenticated URL until wired up.');
    }
}