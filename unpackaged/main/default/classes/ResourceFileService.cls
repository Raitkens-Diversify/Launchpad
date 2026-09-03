/**
 * ResourceFileService
 *
 * Builds file download URLs for Resource Center attachments. The delivery
 * strategy is selected by the Resource_Center_Setting__mdt.Default record so
 * switching from authenticated Shepherd URLs to public ContentDistribution URLs
 * (if the site is ever opened to guests) is a config change, not a rewrite.
 *
 *  - Shepherd (default): /sfc/servlet.shepherd/document/download/{ContentDocumentId}
 *    — works for authenticated Experience/internal users who can see the file.
 *  - ContentDistribution: public, no-login URLs. The cacheable read path still
 *    hands out the Shepherd URL (creating a ContentDistribution is DML);
 *    resolvePublicDownloadUrl mints/reuses the public link at click time.
 */
public with sharing class ResourceFileService {

    public interface UrlStrategy {
        String buildDownloadUrl(Id contentDocumentId);
    }

    public class ShepherdUrlStrategy implements UrlStrategy {
        public String buildDownloadUrl(Id contentDocumentId) {
            return '/sfc/servlet.shepherd/document/download/' + contentDocumentId;
        }
    }

    public class ContentDistributionStrategy implements UrlStrategy {
        public String buildDownloadUrl(Id contentDocumentId) {
            // TODO(guest-access): return DistributionPublicUrl from a
            // ContentDistribution record. Until enabled, fall back to the
            // authenticated URL so behavior is never worse than Shepherd.
            return '/sfc/servlet.shepherd/document/download/' + contentDocumentId;
        }
    }

    /** Test seam: inject a strategy without touching the CMDT setting. */
    @TestVisible private static UrlStrategy strategyOverride;

    public static String buildDownloadUrl(Id contentDocumentId) {
        if (contentDocumentId == null) {
            return null;
        }
        return strategy().buildDownloadUrl(contentDocumentId);
    }

    private static UrlStrategy strategy() {
        if (strategyOverride != null) {
            return strategyOverride;
        }
        return deliveryMode() == 'ContentDistribution'
            ? (UrlStrategy) new ContentDistributionStrategy()
            : (UrlStrategy) new ShepherdUrlStrategy();
    }

    /** Test seam: force a delivery mode without touching the CMDT setting. */
    @TestVisible private static String deliveryModeOverride;

    private static String deliveryMode() {
        if (deliveryModeOverride != null) {
            return deliveryModeOverride;
        }
        Resource_Center_Setting__mdt setting = Resource_Center_Setting__mdt.getInstance('Default');
        return (setting != null && String.isNotBlank(setting.File_Delivery_Mode__c))
            ? setting.File_Delivery_Mode__c
            : 'Shepherd';
    }

    /**
     * Resolves a public, no-login download URL for a file, creating a
     * ContentDistribution record on demand. Gated on deliveryMode() so this
     * only ever mints a public link when Resource_Center_Setting__mdt.Default
     * is actually switched to ContentDistribution — otherwise it defers to
     * buildDownloadUrl's authenticated Shepherd URL, same as the class
     * comment above describes. This is the DML step that comment flags as
     * unable to live in a cacheable read path — call it only from a
     * user-initiated action (the Download click), never from a cacheable wire.
     * Also falls back to the Shepherd URL if the version or distribution
     * can't be resolved, so a guest download is never worse than today.
     */
    public static String resolvePublicDownloadUrl(Id contentDocumentId) {
        if (contentDocumentId == null) {
            return null;
        }
        if (deliveryMode() != 'ContentDistribution') {
            return buildDownloadUrl(contentDocumentId);
        }
        try {
            List<ContentVersion> versions = [
                SELECT Id
                FROM ContentVersion
                WHERE ContentDocumentId = :contentDocumentId AND IsLatest = TRUE
                WITH USER_MODE
                LIMIT 1
            ];
            if (!versions.isEmpty()) {
                String url = existingDistributionUrl(versions[0].Id);
                if (String.isBlank(url)) {
                    url = createDistributionUrl(versions[0].Id);
                }
                if (String.isNotBlank(url)) {
                    return url;
                }
            }
        } catch (Exception e) {
            // Fall through to the authenticated URL below.
        }
        return buildDownloadUrl(contentDocumentId);
    }

    private static String existingDistributionUrl(Id contentVersionId) {
        List<ContentDistribution> matches = [
            SELECT DistributionPublicUrl
            FROM ContentDistribution
            WHERE ContentVersionId = :contentVersionId
            WITH USER_MODE
            LIMIT 1
        ];
        return matches.isEmpty() ? null : matches[0].DistributionPublicUrl;
    }

    private static String createDistributionUrl(Id contentVersionId) {
        ContentDistribution distribution = new ContentDistribution(
            Name = 'Resource Center Download ' + contentVersionId,
            ContentVersionId = contentVersionId,
            PreferencesAllowViewInBrowser = true,
            PreferencesAllowOriginalDownload = true,
            PreferencesLinkLatestVersion = true,
            PreferencesNotifyRndtnComplete = false,
            PreferencesPasswordRequired = false
        );
        insert distribution;
        distribution = [
            SELECT DistributionPublicUrl
            FROM ContentDistribution
            WHERE Id = :distribution.Id
        ];
        return distribution.DistributionPublicUrl;
    }
}