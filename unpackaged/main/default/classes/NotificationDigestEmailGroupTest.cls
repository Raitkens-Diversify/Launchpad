/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-29
 */
@IsTest
private class NotificationDigestEmailGroupTest {
  @IsTest
  static void buildAcAssemblyOrderGroupsHouseholdsAlphabeticallyAndSortsByChangeDate() {
    Notification_Log__c alphaLater = buildLog('alpha-later');
    Notification_Log__c alphaEarlier = buildLog('alpha-earlier');
    Notification_Log__c betaLog = buildLog('beta');

    List<NotificationDigestEmailGroupingService.DigestSortEntry> entries = new List<NotificationDigestEmailGroupingService.DigestSortEntry>{
      buildEntry(alphaLater, 'Beta HH', Datetime.newInstance(2026, 7, 29, 15, 0, 0), true, false),
      buildEntry(alphaEarlier, 'Alpha HH', Datetime.newInstance(2026, 7, 29, 10, 0, 0), true, false),
      buildEntry(betaLog, 'Alpha HH', Datetime.newInstance(2026, 7, 29, 12, 0, 0), true, false)
    };

    List<NotificationDigestEmailGroupingService.DigestAssemblyItem> assemblyItems = NotificationDigestEmailGroupingService.buildAcAssemblyOrder(
      entries
    );

    System.assertEquals(5, assemblyItems.size());
    System.assertEquals('SECTION', assemblyItems[0].itemType);
    System.assertEquals('Alpha HH', assemblyItems[0].sectionLabel);
    System.assertEquals('alpha-earlier', assemblyItems[1].logRecord.Title__c);
    System.assertEquals('beta', assemblyItems[2].logRecord.Title__c);
    System.assertEquals('SECTION', assemblyItems[3].itemType);
    System.assertEquals('Beta HH', assemblyItems[3].sectionLabel);
    System.assertEquals('alpha-later', assemblyItems[4].logRecord.Title__c);
  }

  @IsTest
  static void buildAcAssemblyOrderPlacesUnassociatedNotificationsLast() {
    Notification_Log__c householdLog = buildLog('household-log');
    Notification_Log__c otherLog = buildLog('other-log');

    List<NotificationDigestEmailGroupingService.DigestSortEntry> entries = new List<NotificationDigestEmailGroupingService.DigestSortEntry>{
      buildEntry(
        otherLog,
        null,
        Datetime.newInstance(2026, 7, 29, 9, 0, 0),
        false,
        false
      ),
      buildEntry(
        householdLog,
        'Alpha HH',
        Datetime.newInstance(2026, 7, 29, 11, 0, 0),
        true,
        false
      )
    };

    List<NotificationDigestEmailGroupingService.DigestAssemblyItem> assemblyItems = NotificationDigestEmailGroupingService.buildAcAssemblyOrder(
      entries
    );

    System.assertEquals(4, assemblyItems.size());
    System.assertEquals('Alpha HH', assemblyItems[0].sectionLabel);
    System.assertEquals('household-log', assemblyItems[1].logRecord.Title__c);
    System.assertEquals(
      NotificationDigestEmailGroupingService.OTHER_NOTIFICATIONS_SECTION,
      assemblyItems[2].sectionLabel
    );
    System.assertEquals('other-log', assemblyItems[3].logRecord.Title__c);
  }

  @IsTest
  static void assembleAcTableHtmlIncludesAcColumnsAndSectionHeaders() {
    Notification_Log__c logRecord = buildLog('digest-log');
    NotificationDigestEmailGroupingService.DigestSortEntry entry = buildEntry(
      logRecord,
      'Alpha HH',
      Datetime.newInstance(2026, 7, 29, 11, 0, 0),
      true,
      false
    );
    List<NotificationDigestEmailGroupingService.DigestAssemblyItem> assemblyItems = NotificationDigestEmailGroupingService.buildAcAssemblyOrder(
      new List<NotificationDigestEmailGroupingService.DigestSortEntry>{ entry }
    );

    String htmlBody = NotificationDigestEmailGroupingService.assembleAcTableHtml(
      assemblyItems,
      new Map<Id, String>{ logRecord.Id => '<tr><td>Row</td></tr>' },
      32000
    );

    System.assert(htmlBody.contains('Change Date'));
    System.assert(htmlBody.contains('Financial Advisor Team'));
    System.assert(htmlBody.contains('Alpha HH'));
    System.assert(htmlBody.contains('Row'));
  }

  private static Notification_Log__c buildLog(String identifier) {
    return new Notification_Log__c(
      Title__c = identifier,
      CreatedDate = Datetime.newInstance(2026, 7, 29, 8, 0, 0)
    );
  }

  private static NotificationDigestEmailGroupingService.DigestSortEntry buildEntry(
    Notification_Log__c logRecord,
    String householdName,
    Datetime changeDate,
    Boolean hasHouseholdAssociation,
    Boolean hasContactAssociation
  ) {
    NotificationDigestEmailGroupingService.DigestSortEntry entry = new NotificationDigestEmailGroupingService.DigestSortEntry();
    entry.logRecord = logRecord;
    entry.householdName = householdName;
    entry.changeDate = changeDate;
    entry.hasHouseholdAssociation = hasHouseholdAssociation;
    entry.hasContactAssociation = hasContactAssociation;
    return entry;
  }
}