/**
 * Result shape for arcAnnouncements (the Home dashboard's announcement
 * banner, Figma node 760:131500).
 */
public class ArcAnnouncementModels {
  public class AnnouncementItem {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String body;
    @AuraEnabled
    public String linkUrl;
  }
}