@IsTest
private class ArcAnnouncementControllerTest {
  @IsTest
  static void getActiveAnnouncementsReturnsOnlyActiveOrderedBySortOrder() {
    insert new List<Announcement__c>{
      new Announcement__c(
        Name = 'Second',
        Body__c = 'Second body',
        Link_URL__c = 'https://example.com/second',
        Is_Active__c = true,
        Sort_Order__c = 2
      ),
      new Announcement__c(
        Name = 'First',
        Body__c = 'First body',
        Link_URL__c = 'https://example.com/first',
        Is_Active__c = true,
        Sort_Order__c = 1
      ),
      new Announcement__c(
        Name = 'Inactive',
        Body__c = 'Inactive body',
        Is_Active__c = false,
        Sort_Order__c = 0
      )
    };

    Test.startTest();
    List<ArcAnnouncementModels.AnnouncementItem> items = ArcAnnouncementController.getActiveAnnouncements();
    Test.stopTest();

    System.assertEquals(2, items.size());
    System.assertEquals('First', items[0].title);
    System.assertEquals('Second', items[1].title);
  }

  @IsTest
  static void getActiveAnnouncementsReturnsEmptyListWhenNoneActive() {
    Test.startTest();
    List<ArcAnnouncementModels.AnnouncementItem> items = ArcAnnouncementController.getActiveAnnouncements();
    Test.stopTest();

    System.assertEquals(0, items.size());
  }
}