/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-20
 */
@IsTest
private class EgnyteVfEmbedControllerTest {
    private static final String RECORD_ID = '001TO000008Zp6JYAS';
    private static final String CUSTOM_DOMAIN = 'https://arc-launchpad.diversify.com';
    private static final String DEFAULT_DOMAIN = 'https://arc-launchpad.diversify.com';

    @IsTest
    static void buildVfEmbedUrl_returnsRecordIntegrationPageUrl() {
        Test.startTest();
        String url = EgnyteVfEmbedController.buildVfEmbedUrl(CUSTOM_DOMAIN, RECORD_ID);
        Test.stopTest();

        System.assertNotEquals(null, url, 'Expected a record embed URL.');
        System.assert(url.startsWith(CUSTOM_DOMAIN), url);
        System.assert(url.contains('/apex/Egnyte_integration_page'), url);
        System.assert(url.contains('id=' + RECORD_ID), url);
        System.assert(url.contains('isdtp=nv'), url);
    }

    @IsTest
    static void buildVfEmbedUrl_returnsStandaloneMyEgnyteUrl() {
        Test.startTest();
        String url = EgnyteVfEmbedController.buildVfEmbedUrl(CUSTOM_DOMAIN, null);
        Test.stopTest();

        System.assertNotEquals(null, url, 'Expected a standalone embed URL.');
        System.assert(url.startsWith(CUSTOM_DOMAIN), url);
        System.assert(url.contains('/apex/efs__MyEgnyte'), url);
        System.assert(url.contains('isdtp=nv'), url);
        System.assert(!url.contains('id='), url);
    }

    @IsTest
    static void buildVfEmbedUrl_treatsBlankRecordIdAsStandalone() {
        Test.startTest();
        String emptyUrl = EgnyteVfEmbedController.buildVfEmbedUrl(CUSTOM_DOMAIN, '');
        String whitespaceUrl = EgnyteVfEmbedController.buildVfEmbedUrl(
            CUSTOM_DOMAIN,
            '   '
        );
        Test.stopTest();

        System.assert(emptyUrl.contains('/apex/efs__MyEgnyte'), emptyUrl);
        System.assert(!emptyUrl.contains('id='), emptyUrl);
        System.assert(whitespaceUrl.contains('/apex/efs__MyEgnyte'), whitespaceUrl);
        System.assert(!whitespaceUrl.contains('id='), whitespaceUrl);
    }

    @IsTest
    static void buildVfEmbedUrl_normalizesDomainWithoutScheme() {
        Test.startTest();
        String url = EgnyteVfEmbedController.buildVfEmbedUrl(
            'arc-launchpad.diversify.com',
            RECORD_ID
        );
        Test.stopTest();

        System.assert(url.startsWith('https://arc-launchpad.diversify.com'), url);
        System.assert(url.contains('/apex/Egnyte_integration_page'), url);
    }

    @IsTest
    static void buildVfEmbedUrl_preservesHttpScheme() {
        Test.startTest();
        String url = EgnyteVfEmbedController.buildVfEmbedUrl(
            'http://arc-launchpad.diversify.com',
            RECORD_ID
        );
        Test.stopTest();

        System.assert(url.startsWith('http://arc-launchpad.diversify.com'), url);
        System.assert(!url.startsWith('https://'), url);
    }

    @IsTest
    static void buildVfEmbedUrl_stripsTrailingSlashFromDomain() {
        Test.startTest();
        String url = EgnyteVfEmbedController.buildVfEmbedUrl(
            CUSTOM_DOMAIN + '/',
            RECORD_ID
        );
        Test.stopTest();

        System.assert(url.startsWith(CUSTOM_DOMAIN + '/'), url);
        System.assert(!url.startsWith(CUSTOM_DOMAIN + '//'), url);
    }

    @IsTest
    static void buildVfEmbedUrl_usesPublishedOriginWhenDomainBlank() {
        String expectedOrigin = EgnyteVfEmbedController.resolvePublishedSiteOrigin(
            'ARC'
        );

        Test.startTest();
        String emptyUrl = EgnyteVfEmbedController.buildVfEmbedUrl('', RECORD_ID);
        String whitespaceUrl = EgnyteVfEmbedController.buildVfEmbedUrl(
            '   ',
            RECORD_ID
        );
        String nullUrl = EgnyteVfEmbedController.buildVfEmbedUrl(null, RECORD_ID);
        Test.stopTest();

        System.assert(emptyUrl.startsWith(expectedOrigin), emptyUrl);
        System.assert(whitespaceUrl.startsWith(expectedOrigin), whitespaceUrl);
        System.assert(nullUrl.startsWith(expectedOrigin), nullUrl);
        System.assert(emptyUrl.contains('/apex/Egnyte_integration_page'), emptyUrl);
    }

    @IsTest
    static void buildVfEmbedUrl_usesArcSitePathPrefixWhenAvailable() {
        List<Site> arcSites = [
            SELECT Id, UrlPathPrefix
            FROM Site
            WHERE Name = 'ARC' AND SiteType = 'ChatterNetwork'
            LIMIT 1
        ];

        if (arcSites.isEmpty()) {
            return;
        }

        String expectedPrefix = resolveExpectedVfPrefix(arcSites[0].UrlPathPrefix);

        Test.startTest();
        String url = EgnyteVfEmbedController.buildVfEmbedUrl(CUSTOM_DOMAIN, RECORD_ID);
        Test.stopTest();

        System.assert(
            url.contains('/' + expectedPrefix + '/apex/Egnyte_integration_page'),
            url
        );
    }

    @IsTest
    static void buildVfEmbedUrlInternal_returnsNullWhenPageNameBlank() {
        Test.startTest();
        String nullPage = EgnyteVfEmbedController.buildVfEmbedUrlInternal(
            null,
            CUSTOM_DOMAIN,
            RECORD_ID
        );
        String emptyPage = EgnyteVfEmbedController.buildVfEmbedUrlInternal(
            '',
            CUSTOM_DOMAIN,
            RECORD_ID
        );
        String whitespacePage = EgnyteVfEmbedController.buildVfEmbedUrlInternal(
            '   ',
            CUSTOM_DOMAIN,
            RECORD_ID
        );
        Test.stopTest();

        System.assertEquals(null, nullPage);
        System.assertEquals(null, emptyPage);
        System.assertEquals(null, whitespacePage);
    }

    @IsTest
    static void buildVfEmbedUrlInternal_passesRecordIdForNonStandalonePages() {
        Test.startTest();
        String url = EgnyteVfEmbedController.buildVfEmbedUrlInternal(
            'Some_Custom_Page',
            CUSTOM_DOMAIN,
            RECORD_ID
        );
        Test.stopTest();

        System.assert(url.contains('/apex/Some_Custom_Page'), url);
        System.assert(url.contains('id=' + RECORD_ID), url);
        System.assert(url.contains('isdtp=nv'), url);
    }

    @IsTest
    static void buildVfEmbedUrlInternal_omitsRecordIdForStandaloneMyEgnyte() {
        Test.startTest();
        String url = EgnyteVfEmbedController.buildVfEmbedUrlInternal(
            'efs__MyEgnyte',
            CUSTOM_DOMAIN,
            RECORD_ID
        );
        Test.stopTest();

        System.assert(url.contains('/apex/efs__MyEgnyte'), url);
        System.assert(url.contains('isdtp=nv'), url);
        System.assert(!url.contains('id='), url);
    }

    @IsTest
    static void buildVfEmbedUrlInternal_trimsPageNameAndRecordId() {
        Test.startTest();
        String url = EgnyteVfEmbedController.buildVfEmbedUrlInternal(
            '  Egnyte_integration_page  ',
            CUSTOM_DOMAIN,
            '  ' + RECORD_ID + '  '
        );
        Test.stopTest();

        System.assert(url.contains('/apex/Egnyte_integration_page'), url);
        System.assert(url.contains('id=' + RECORD_ID), url);
        System.assert(!url.contains('id=  '), url);
    }

    @IsTest
    static void buildApexPath_includesPrefixOnlyWhenPresent() {
        Test.startTest();
        String withoutPrefix = EgnyteVfEmbedController.buildApexPath(
            null,
            'Egnyte_integration_page'
        );
        String withBlankPrefix = EgnyteVfEmbedController.buildApexPath(
            '   ',
            'Egnyte_integration_page'
        );
        String withPrefix = EgnyteVfEmbedController.buildApexPath(
            'arc',
            '  Egnyte_integration_page  '
        );
        Test.stopTest();

        System.assertEquals('/apex/Egnyte_integration_page', withoutPrefix);
        System.assertEquals('/apex/Egnyte_integration_page', withBlankPrefix);
        System.assertEquals('/arc/apex/Egnyte_integration_page', withPrefix);
    }

    @IsTest
    static void applyOrigin_prefixesWhenOriginPresent() {
        Test.startTest();
        String withOrigin = EgnyteVfEmbedController.applyOrigin(
            CUSTOM_DOMAIN,
            '/apex/Egnyte_integration_page'
        );
        String withoutOrigin = EgnyteVfEmbedController.applyOrigin(
            '',
            '/apex/Egnyte_integration_page'
        );
        String fromNullOrigin = EgnyteVfEmbedController.applyOrigin(
            null,
            '/apex/Egnyte_integration_page'
        );
        Test.stopTest();

        System.assertEquals(
            CUSTOM_DOMAIN + '/apex/Egnyte_integration_page',
            withOrigin
        );
        System.assertEquals('/apex/Egnyte_integration_page', withoutOrigin);
        System.assertEquals('/apex/Egnyte_integration_page', fromNullOrigin);
    }

    @IsTest
    static void resolveFallbackPathPrefix_prefersSecureUrlThenSitePrefix() {
        Test.startTest();
        String fromSecure = EgnyteVfEmbedController.resolveFallbackPathPrefix(
            'https://arc-launchpad.diversify.com/arc',
            '/ignored/'
        );
        String fromSitePrefix = EgnyteVfEmbedController.resolveFallbackPathPrefix(
            null,
            '/vforcesite/'
        );
        String fromBlankSecure = EgnyteVfEmbedController.resolveFallbackPathPrefix(
            'https://arc-launchpad.diversify.com',
            '/vforcesite/'
        );
        String fromNeither = EgnyteVfEmbedController.resolveFallbackPathPrefix(
            null,
            ''
        );
        Test.stopTest();

        System.assertEquals('arc', fromSecure);
        System.assertEquals('vforcesite', fromSitePrefix);
        System.assertEquals('vforcesite', fromBlankSecure);
        System.assertEquals(null, fromNeither);
    }

    @IsTest
    static void selectPublishedOrigin_prefersCustomThenMySiteThenDefault() {
        Test.startTest();
        String fromNull = EgnyteVfEmbedController.selectPublishedOrigin(null);
        String fromEmpty = EgnyteVfEmbedController.selectPublishedOrigin(
            new List<String>()
        );
        String fromBlankAndSalesforce = EgnyteVfEmbedController.selectPublishedOrigin(
            new List<String>{
                null,
                '',
                '   ',
                'na1.salesforce.com',
                'something.force.com'
            }
        );
        String fromMySiteOnly = EgnyteVfEmbedController.selectPublishedOrigin(
            new List<String>{
                '',
                'dfpginvestments.my.site.com',
                'na1.salesforce.com'
            }
        );
        String fromCustomPreferred = EgnyteVfEmbedController.selectPublishedOrigin(
            new List<String>{
                'dfpginvestments.my.site.com',
                'arc-launchpad.diversify.com'
            }
        );
        Test.stopTest();

        System.assertEquals(DEFAULT_DOMAIN, fromNull);
        System.assertEquals(DEFAULT_DOMAIN, fromEmpty);
        System.assertEquals(DEFAULT_DOMAIN, fromBlankAndSalesforce);
        System.assertEquals('https://dfpginvestments.my.site.com', fromMySiteOnly);
        System.assertEquals(
            'https://arc-launchpad.diversify.com',
            fromCustomPreferred
        );
    }

    @IsTest
    static void extractPathPrefixFromSecureUrl_returnsNullForInvalidUrls() {
        Test.startTest();
        String fromNull = EgnyteVfEmbedController.extractPathPrefixFromSecureUrl(
            null
        );
        String fromEmpty = EgnyteVfEmbedController.extractPathPrefixFromSecureUrl(
            ''
        );
        String fromWhitespace = EgnyteVfEmbedController.extractPathPrefixFromSecureUrl(
            '   '
        );
        String fromMissingScheme = EgnyteVfEmbedController.extractPathPrefixFromSecureUrl(
            'arc-launchpad.diversify.com/arc'
        );
        String fromHostOnly = EgnyteVfEmbedController.extractPathPrefixFromSecureUrl(
            'https://arc-launchpad.diversify.com'
        );
        String fromTrailingSlashHost = EgnyteVfEmbedController.extractPathPrefixFromSecureUrl(
            'https://arc-launchpad.diversify.com/'
        );
        String fromEmptyPath = EgnyteVfEmbedController.extractPathPrefixFromSecureUrl(
            'https://arc-launchpad.diversify.com//'
        );
        String fromNestedPath = EgnyteVfEmbedController.extractPathPrefixFromSecureUrl(
            'https://arc-launchpad.diversify.com/arc/nested'
        );
        Test.stopTest();

        System.assertEquals(null, fromNull);
        System.assertEquals(null, fromEmpty);
        System.assertEquals(null, fromWhitespace);
        System.assertEquals(null, fromMissingScheme);
        System.assertEquals(null, fromHostOnly);
        System.assertEquals(null, fromTrailingSlashHost);
        System.assertEquals(null, fromEmptyPath);
        System.assertEquals(null, fromNestedPath);
    }

    @IsTest
    static void extractPathPrefixFromSecureUrl_returnsSinglePathSegment() {
        Test.startTest();
        String fromHttps = EgnyteVfEmbedController.extractPathPrefixFromSecureUrl(
            'https://arc-launchpad.diversify.com/arc'
        );
        String fromTrailingSlash = EgnyteVfEmbedController.extractPathPrefixFromSecureUrl(
            'https://arc-launchpad.diversify.com/arc/'
        );
        String fromHttp = EgnyteVfEmbedController.extractPathPrefixFromSecureUrl(
            'http://arc-launchpad.diversify.com/arc'
        );
        Test.stopTest();

        System.assertEquals('arc', fromHttps);
        System.assertEquals('arc', fromTrailingSlash);
        System.assertEquals('arc', fromHttp);
    }

    @IsTest
    static void resolveVfPathPrefixForSiteName_returnsNullWhenSiteMissing() {
        Test.startTest();
        String prefix = EgnyteVfEmbedController.resolveVfPathPrefixForSiteName(
            'SiteNameThatDoesNotExist_XYZ'
        );
        Test.stopTest();

        System.assertEquals(null, prefix);
    }

    @IsTest
    static void resolveVfPathPrefixForSiteName_blankNameUsesDefaultSite() {
        Test.startTest();
        String fromBlank = EgnyteVfEmbedController.resolveVfPathPrefixForSiteName(
            ''
        );
        String fromWhitespace = EgnyteVfEmbedController.resolveVfPathPrefixForSiteName(
            '   '
        );
        String fromNull = EgnyteVfEmbedController.resolveVfPathPrefixForSiteName(
            null
        );
        String fromDefault = EgnyteVfEmbedController.resolveVfPathPrefixForSiteName(
            'ARC'
        );
        Test.stopTest();

        System.assertEquals(fromDefault, fromBlank);
        System.assertEquals(fromDefault, fromWhitespace);
        System.assertEquals(fromDefault, fromNull);
    }

    @IsTest
    static void resolvePublishedSiteOrigin_returnsDefaultWhenSiteMissing() {
        Test.startTest();
        String origin = EgnyteVfEmbedController.resolvePublishedSiteOrigin(
            'SiteNameThatDoesNotExist_XYZ'
        );
        Test.stopTest();

        System.assertEquals(DEFAULT_DOMAIN, origin);
    }

    @IsTest
    static void resolvePublishedSiteOrigin_blankNameUsesDefaultSite() {
        Test.startTest();
        String fromBlank = EgnyteVfEmbedController.resolvePublishedSiteOrigin('');
        String fromWhitespace = EgnyteVfEmbedController.resolvePublishedSiteOrigin(
            '   '
        );
        String fromNull = EgnyteVfEmbedController.resolvePublishedSiteOrigin(null);
        String fromDefault = EgnyteVfEmbedController.resolvePublishedSiteOrigin(
            'ARC'
        );
        Test.stopTest();

        System.assertEquals(fromDefault, fromBlank);
        System.assertEquals(fromDefault, fromWhitespace);
        System.assertEquals(fromDefault, fromNull);
        System.assert(fromDefault.startsWith('https://'), fromDefault);
    }

    @IsTest
    static void resolvePublishedSiteOrigin_prefersCustomDomainWhenPresent() {
        List<Site> sites = [SELECT Id FROM Site WHERE Name = 'ARC' LIMIT 1];
        if (sites.isEmpty()) {
            return;
        }

        List<DomainSite> domainSites = [
            SELECT Domain.Domain
            FROM DomainSite
            WHERE SiteId = :sites[0].Id
        ];

        String expectedCustom;
        String expectedMySite;
        for (DomainSite domainSite : domainSites) {
            String domain = domainSite.Domain.Domain;
            if (String.isBlank(domain)) {
                continue;
            }
            if (domain.endsWith('.my.site.com')) {
                expectedMySite = domain;
                continue;
            }
            if (
                !domain.contains('salesforce.com') &&
                !domain.contains('force.com')
            ) {
                expectedCustom = domain;
            }
        }

        Test.startTest();
        String origin = EgnyteVfEmbedController.resolvePublishedSiteOrigin('ARC');
        Test.stopTest();

        if (String.isNotBlank(expectedCustom)) {
            System.assertEquals('https://' + expectedCustom, origin);
            return;
        }
        if (String.isNotBlank(expectedMySite)) {
            System.assertEquals('https://' + expectedMySite, origin);
            return;
        }
        System.assertEquals(DEFAULT_DOMAIN, origin);
    }

    @IsTest
    static void shouldPassRecordId_returnsFalseOnlyForStandaloneMyEgnyte() {
        Test.startTest();
        Boolean forNull = EgnyteVfEmbedController.shouldPassRecordId(null);
        Boolean forBlank = EgnyteVfEmbedController.shouldPassRecordId('');
        Boolean forStandalone = EgnyteVfEmbedController.shouldPassRecordId(
            'efs__MyEgnyte'
        );
        Boolean forStandaloneLower = EgnyteVfEmbedController.shouldPassRecordId(
            'efs__myegnyte'
        );
        Boolean forStandalonePadded = EgnyteVfEmbedController.shouldPassRecordId(
            '  efs__MyEgnyte  '
        );
        Boolean forRecordPage = EgnyteVfEmbedController.shouldPassRecordId(
            'Egnyte_integration_page'
        );
        Test.stopTest();

        System.assertEquals(true, forNull);
        System.assertEquals(true, forBlank);
        System.assertEquals(false, forStandalone);
        System.assertEquals(false, forStandaloneLower);
        System.assertEquals(false, forStandalonePadded);
        System.assertEquals(true, forRecordPage);
    }

    @IsTest
    static void normalizeDomain_returnsDefaultWhenBlank() {
        Test.startTest();
        String fromEmpty = EgnyteVfEmbedController.normalizeDomain('');
        String fromWhitespace = EgnyteVfEmbedController.normalizeDomain('   ');
        String fromNull = EgnyteVfEmbedController.normalizeDomain(null);
        Test.stopTest();

        System.assertEquals(DEFAULT_DOMAIN, fromEmpty);
        System.assertEquals(DEFAULT_DOMAIN, fromWhitespace);
        System.assertEquals(DEFAULT_DOMAIN, fromNull);
    }

    @IsTest
    static void normalizePathSegment_stripsLeadingAndTrailingSlashes() {
        Test.startTest();
        String fromWrapped = EgnyteVfEmbedController.normalizePathSegment(
            '/arc/'
        );
        String fromManySlashes = EgnyteVfEmbedController.normalizePathSegment(
            '///arc///'
        );
        String fromPadded = EgnyteVfEmbedController.normalizePathSegment(
            '  /arc  '
        );
        String fromPlain = EgnyteVfEmbedController.normalizePathSegment('arc');
        Test.stopTest();

        System.assertEquals('arc', fromWrapped);
        System.assertEquals('arc', fromManySlashes);
        System.assertEquals('arc', fromPadded);
        System.assertEquals('arc', fromPlain);
    }

    private static String resolveExpectedVfPrefix(String networkPrefix) {
        List<Site> sites = [
            SELECT Id, UrlPathPrefix
            FROM Site
            WHERE UrlPathPrefix = :networkPrefix AND SiteType = 'ChatterNetwork'
            LIMIT 1
        ];

        if (!sites.isEmpty()) {
            List<SiteDetail> details = [
                SELECT SecureUrl
                FROM SiteDetail
                WHERE DurableId = :sites[0].Id
                LIMIT 1
            ];

            if (!details.isEmpty() && String.isNotBlank(details[0].SecureUrl)) {
                String securePrefix = EgnyteVfEmbedController.extractPathPrefixFromSecureUrl(
                    details[0].SecureUrl
                );
                if (String.isNotBlank(securePrefix)) {
                    return securePrefix;
                }
            }
        }

        return networkPrefix;
    }
}