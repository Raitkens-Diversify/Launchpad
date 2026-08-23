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
 *  - ContentDistribution: public, no-login URLs. STUBBED — wiring it up requires
 *    creating ContentDistribution records (a DML step, so it cannot live in a
 *    cacheable read path) and is out of scope until guest access is enabled.
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

    private static String deliveryMode() {
        Resource_Center_Setting__mdt setting = Resource_Center_Setting__mdt.getInstance('Default');
        return (setting != null && String.isNotBlank(setting.File_Delivery_Mode__c))
            ? setting.File_Delivery_Mode__c
            : 'Shepherd';
    }
}