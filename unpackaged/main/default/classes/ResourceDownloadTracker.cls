/**
 * ResourceDownloadTracker
 *
 * Fire-and-forget Queueable that increments Resource__c.Download_Count__c.
 * Enqueued by ResourceCenterService.trackDownload so counting never blocks or
 * breaks the actual download.
 *
 * `without sharing`: the site member who downloads a file has only Read (Public
 * Read Only OWD) on Resource__c and cannot edit it under record sharing, so the
 * counter runs in system context. Only an aggregate count is touched — no record
 * data is exposed. Concurrent increments may occasionally drop one; the count is
 * analytics-grade, not audit-grade.
 */
public without sharing class ResourceDownloadTracker implements Queueable {

    private final Id resourceId;

    public ResourceDownloadTracker(Id resourceId) {
        this.resourceId = resourceId;
    }

    public void execute(QueueableContext context) {
        if (resourceId == null) {
            return;
        }
        List<Resource__c> rows = [
            SELECT Id, Download_Count__c FROM Resource__c WHERE Id = :resourceId LIMIT 1
        ];
        if (rows.isEmpty()) {
            return;
        }
        Resource__c r = rows[0];
        r.Download_Count__c = (r.Download_Count__c == null ? 0 : r.Download_Count__c) + 1;
        try {
            update r;
        } catch (Exception e) {
            // Analytics-grade; safe to drop on contention or validation error.
        }
    }
}