/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-20
 *
 * Builds Visualforce URLs for the egnyteVfEmbed LWC iframe.
 * Uses Egnyte_integration_page for record pages and efs__MyEgnyte for standalone views.
 */
public with sharing class EgnyteVfEmbedController {
    private static final String DEFAULT_SITE_NAME = 'ARC';
    private static final String DEFAULT_DOMAIN = 'https://arc-launchpad.diversify.com';
    private static final String RECORD_VF_PAGE = 'Egnyte_integration_page';
    private static final String STANDALONE_VF_PAGE = 'efs__MyEgnyte';

    @AuraEnabled
    public static String buildVfEmbedUrl(String domain, String recordId) {
        String vfPageName = String.isNotBlank(recordId)
            ? RECORD_VF_PAGE
            : STANDALONE_VF_PAGE;
        return buildVfEmbedUrlInternal(vfPageName, domain, recordId);
    }

    @TestVisible
    private static String buildVfEmbedUrlInternal(
        String vfPageName,
        String domain,
        String recordId
    ) {
        if (String.isBlank(vfPageName)) {
            return null;
        }

        String pathPrefix = resolveVfPathPrefixForSiteName(DEFAULT_SITE_NAME);
        PageReference pageRef = new PageReference(
            buildApexPath(pathPrefix, vfPageName)
        );
        String normalizedPage = vfPageName.trim().toLowerCase();

        if (normalizedPage == RECORD_VF_PAGE.toLowerCase()) {
            pageRef.getParameters().put('id', recordId.trim());
            pageRef.getParameters().put('isdtp', 'nv');
        } else if (String.isNotBlank(recordId) && shouldPassRecordId(vfPageName)) {
            pageRef.getParameters().put('id', recordId.trim());
            pageRef.getParameters().put('isdtp', 'nv');
        } else {
            pageRef.getParameters().put('isdtp', 'nv');
        }

        return applyOrigin(resolvePublishedOrigin(domain), pageRef.getUrl());
    }

    @TestVisible
    private static String buildApexPath(String pathPrefix, String vfPageName) {
        String apexPath = '/apex/' + vfPageName.trim();
        if (String.isBlank(pathPrefix)) {
            return apexPath;
        }
        return '/' + pathPrefix + apexPath;
    }

    @TestVisible
    private static String applyOrigin(String origin, String relativeUrl) {
        if (String.isNotBlank(origin)) {
            return origin + relativeUrl;
        }
        return relativeUrl;
    }

    @TestVisible
    private static String resolvePublishedOrigin(String domain) {
        if (String.isNotBlank(domain)) {
            return normalizeDomain(domain);
        }
        return resolvePublishedSiteOrigin(DEFAULT_SITE_NAME);
    }

    @TestVisible
    private static String normalizeDomain(String domain) {
        if (String.isBlank(domain)) {
            return DEFAULT_DOMAIN;
        }

        String normalized = domain.trim().removeEnd('/');
        if (!normalized.startsWith('http://') && !normalized.startsWith('https://')) {
            normalized = 'https://' + normalized;
        }

        return normalized;
    }

    @TestVisible
    private static String resolveVfPathPrefixForSiteName(String experienceSiteName) {
        String resolvedSiteName = String.isBlank(experienceSiteName)
            ? DEFAULT_SITE_NAME
            : experienceSiteName.trim();
        List<Site> sites = [
            SELECT Id, UrlPathPrefix
            FROM Site
            WHERE Name = :resolvedSiteName AND SiteType = 'ChatterNetwork'
            LIMIT 1
        ];

        if (sites.isEmpty()) {
            return null;
        }

        List<SiteDetail> details = [
            SELECT SecureUrl
            FROM SiteDetail
            WHERE DurableId = :sites[0].Id
            LIMIT 1
        ];

        String secureUrl = details.isEmpty() ? null : details[0].SecureUrl;
        return resolveFallbackPathPrefix(secureUrl, sites[0].UrlPathPrefix);
    }

    @TestVisible
    private static String resolveFallbackPathPrefix(
        String secureUrl,
        String urlPathPrefix
    ) {
        String securePathPrefix = extractPathPrefixFromSecureUrl(secureUrl);
        if (String.isNotBlank(securePathPrefix)) {
            return securePathPrefix;
        }

        if (String.isNotBlank(urlPathPrefix)) {
            return normalizePathSegment(urlPathPrefix);
        }

        return null;
    }

    @TestVisible
    private static String extractPathPrefixFromSecureUrl(String secureUrl) {
        if (String.isBlank(secureUrl)) {
            return null;
        }

        String normalized = secureUrl.trim().removeEnd('/');
        Integer schemeEnd = normalized.indexOf('://');
        if (schemeEnd < 0) {
            return null;
        }

        Integer pathStart = normalized.indexOf('/', schemeEnd + 3);
        if (pathStart < 0) {
            return null;
        }

        String pathPrefix = normalized.substring(pathStart + 1);
        if (String.isBlank(pathPrefix) || pathPrefix.contains('/')) {
            return null;
        }

        return pathPrefix;
    }

    @TestVisible
    private static String resolvePublishedSiteOrigin(String experienceSiteName) {
        String resolvedSiteName = String.isBlank(experienceSiteName)
            ? DEFAULT_SITE_NAME
            : experienceSiteName.trim();
        List<Site> sites = [
            SELECT Id
            FROM Site
            WHERE Name = :resolvedSiteName
            LIMIT 1
        ];

        if (sites.isEmpty()) {
            return DEFAULT_DOMAIN;
        }

        List<DomainSite> domainSites = [
            SELECT Domain.Domain
            FROM DomainSite
            WHERE SiteId = :sites[0].Id
        ];

        List<String> domains = new List<String>();
        for (DomainSite domainSite : domainSites) {
            domains.add(domainSite.Domain.Domain);
        }
        return selectPublishedOrigin(domains);
    }

    @TestVisible
    private static String selectPublishedOrigin(List<String> domains) {
        if (domains == null || domains.isEmpty()) {
            return DEFAULT_DOMAIN;
        }

        String mySiteDomain;
        String customDomain;

        for (String domain : domains) {
            if (String.isBlank(domain)) {
                continue;
            }

            if (domain.endsWith('.my.site.com')) {
                mySiteDomain = domain;
                continue;
            }

            if (!domain.contains('salesforce.com') && !domain.contains('force.com')) {
                customDomain = domain;
            }
        }

        if (String.isNotBlank(customDomain)) {
            return 'https://' + customDomain;
        }

        if (String.isNotBlank(mySiteDomain)) {
            return 'https://' + mySiteDomain;
        }

        return DEFAULT_DOMAIN;
    }

    @TestVisible
    private static Boolean shouldPassRecordId(String vfPageName) {
        String page = vfPageName == null ? '' : vfPageName.trim().toLowerCase();
        return page != 'efs__myegnyte';
    }

    @TestVisible
    private static String normalizePathSegment(String value) {
        return value.trim().replaceAll('^/+', '').replaceAll('/+$', '');
    }
}