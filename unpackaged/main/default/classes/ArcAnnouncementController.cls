/**
 * Aura-enabled facade for arcAnnouncements: returns active Announcement__c
 * records, ordered for the banner's prev/next pager.
 */
public with sharing class ArcAnnouncementController {
  @AuraEnabled(cacheable=true)
  public static List<ArcAnnouncementModels.AnnouncementItem> getActiveAnnouncements() {
    List<ArcAnnouncementModels.AnnouncementItem> items = new List<ArcAnnouncementModels.AnnouncementItem>();

    for (Announcement__c announcement : [
      SELECT Id, Name, Body__c, Link_URL__c
      FROM Announcement__c
      WHERE Is_Active__c = TRUE
      WITH SECURITY_ENFORCED
      ORDER BY Sort_Order__c NULLS LAST, CreatedDate DESC
    ]) {
      ArcAnnouncementModels.AnnouncementItem item = new ArcAnnouncementModels.AnnouncementItem();
      item.id = announcement.Id;
      item.title = announcement.Name;
      item.body = announcement.Body__c;
      item.linkUrl = announcement.Link_URL__c;
      items.add(item);
    }

    return items;
  }
}