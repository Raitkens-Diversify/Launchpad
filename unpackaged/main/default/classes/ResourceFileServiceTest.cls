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
    static void contentDistributionStrategyFallsBack() {
        ResourceFileService.strategyOverride = new ResourceFileService.ContentDistributionStrategy();
        String url = ResourceFileService.buildDownloadUrl(FAKE_CD);
        Assert.isTrue(url.startsWith('/sfc/servlet.shepherd/document/download/'),
            'The stub falls back to the authenticated URL until wired up.');
    }
}