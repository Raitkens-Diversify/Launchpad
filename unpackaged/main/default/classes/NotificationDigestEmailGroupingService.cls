/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-29
 *
 * Groups and assembles digest email tables per AC1/AC2 household rules.
 */
public without sharing class NotificationDigestEmailGroupingService {
  public static final String OTHER_NOTIFICATIONS_SECTION = 'Other Notifications';
  public static final Integer AC_COLUMN_COUNT = 6;

  public class DigestSortEntry {
    public Notification_Log__c logRecord { get; set; }
    public Id householdId { get; set; }
    public String householdName { get; set; }
    public Datetime changeDate { get; set; }
    public Boolean hasHouseholdAssociation { get; set; }
    public Boolean hasContactAssociation { get; set; }

    public DigestSortEntry() {
      this.hasHouseholdAssociation = false;
      this.hasContactAssociation = false;
    }

    public Boolean isAc2Candidate() {
      return hasHouseholdAssociation != true && hasContactAssociation != true;
    }
  }

  public class DigestAssemblyItem {
    public String itemType { get; private set; }
    public String sectionLabel { get; set; }
    public Notification_Log__c logRecord { get; set; }

    public DigestAssemblyItem() {
    }

    public DigestAssemblyItem(String itemType) {
      this.itemType = itemType;
    }
  }

  public static List<DigestAssemblyItem> buildAcAssemblyOrder(
    List<DigestSortEntry> entries
  ) {
    if (entries == null || entries.isEmpty()) {
      return new List<DigestAssemblyItem>();
    }

    Map<String, List<DigestSortEntry>> householdEntriesByName = new Map<String, List<DigestSortEntry>>();
    List<DigestSortEntry> unassociatedEntries = new List<DigestSortEntry>();

    for (DigestSortEntry entry : entries) {
      if (entry == null || entry.logRecord == null) {
        continue;
      }

      if (entry.isAc2Candidate()) {
        unassociatedEntries.add(entry);
        continue;
      }

      String householdName = resolveHouseholdSectionName(entry);

      if (!householdEntriesByName.containsKey(householdName)) {
        householdEntriesByName.put(householdName, new List<DigestSortEntry>());
      }

      householdEntriesByName.get(householdName).add(entry);
    }

    List<String> householdNames = new List<String>(householdEntriesByName.keySet());
    householdNames.sort();

    List<DigestAssemblyItem> assemblyItems = new List<DigestAssemblyItem>();

    for (String householdName : householdNames) {
      List<DigestSortEntry> householdEntries = sortEntriesByChangeDate(
        householdEntriesByName.get(householdName)
      );

      if (householdEntries.isEmpty()) {
        continue;
      }

      assemblyItems.add(buildSectionItem(householdName));

      for (DigestSortEntry entry : householdEntries) {
        assemblyItems.add(buildRowItem(entry.logRecord));
      }
    }

    List<DigestSortEntry> sortedUnassociatedEntries = sortEntriesByChangeDate(
      unassociatedEntries
    );

    if (!sortedUnassociatedEntries.isEmpty()) {
      assemblyItems.add(
        buildSectionItem(OTHER_NOTIFICATIONS_SECTION)
      );

      for (DigestSortEntry entry : sortedUnassociatedEntries) {
        assemblyItems.add(buildRowItem(entry.logRecord));
      }
    }

    return assemblyItems;
  }

  public static String assembleAcTableHtml(
    List<DigestAssemblyItem> assemblyItems,
    Map<Id, String> rowHtmlByLogId,
    Integer bodyLimit
  ) {
    if (assemblyItems == null || assemblyItems.isEmpty()) {
      return '';
    }

    List<String> bodyParts = new List<String>();
    String tableOpen = buildAcTableOpen();
    String tableClose = '</tbody></table>';
    Integer includedRowCount = 0;
    Integer totalRowCount = countRows(assemblyItems);

    for (DigestAssemblyItem item : assemblyItems) {
      String fragment = item.itemType == 'SECTION'
        ? buildSectionHeaderRow(item.sectionLabel)
        : rowHtmlByLogId.get(item.logRecord.Id);

      if (String.isBlank(fragment)) {
        continue;
      }

      String candidate = tableOpen + String.join(bodyParts, '') + fragment + tableClose;

      if (
        item.itemType == 'ROW' &&
        bodyLimit != null &&
        candidate.length() > bodyLimit &&
        includedRowCount > 0
      ) {
        break;
      }

      bodyParts.add(fragment);

      if (item.itemType == 'ROW') {
        includedRowCount++;
      }
    }

    if (bodyParts.isEmpty()) {
      return '';
    }

    String body = tableOpen + String.join(bodyParts, '') + tableClose;
    Integer omittedCount = totalRowCount - includedRowCount;

    if (omittedCount > 0) {
      body += '<p>+ ' + omittedCount + ' more</p>';
    }

    return body;
  }

  public static String buildAcTableOpen() {
    return '<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse;">' +
      '<thead><tr>' +
      '<th align="left" style="background-color:#f3f3f3;">Subject</th>' +
      '<th align="left" style="background-color:#f3f3f3;">Change Made</th>' +
      '<th align="left" style="background-color:#f3f3f3;">Assigned To</th>' +
      '<th align="left" style="background-color:#f3f3f3;">Change Date</th>' +
      '<th align="left" style="background-color:#f3f3f3;">Household</th>' +
      '<th align="left" style="background-color:#f3f3f3;">Financial Advisor Team</th>' +
      '</tr></thead><tbody>';
  }

  public static String buildSectionHeaderRow(String sectionLabel) {
    return '<tr><td colspan="' +
      AC_COLUMN_COUNT +
      '" style="background-color:#eef4fb;font-weight:bold;">' +
      escapeHtml(String.isBlank(sectionLabel) ? NotificationConstants.DISPLAY_NOT_APPLICABLE : sectionLabel) +
      '</td></tr>';
  }

  private static DigestAssemblyItem buildSectionItem(String sectionLabel) {
    DigestAssemblyItem item = new DigestAssemblyItem('SECTION');
    item.sectionLabel = sectionLabel;
    return item;
  }

  private static DigestAssemblyItem buildRowItem(Notification_Log__c logRecord) {
    DigestAssemblyItem item = new DigestAssemblyItem('ROW');
    item.logRecord = logRecord;
    return item;
  }

  private static List<DigestSortEntry> sortEntriesByChangeDate(
    List<DigestSortEntry> entries
  ) {
    List<DigestSortEntry> sortedEntries = new List<DigestSortEntry>(entries);
    sortedEntries.sort(new DigestSortEntryComparator());
    return sortedEntries;
  }

  private static String resolveHouseholdSectionName(DigestSortEntry entry) {
    if (!String.isBlank(entry.householdName)) {
      return entry.householdName.trim();
    }

    if (entry.householdId != null) {
      return String.valueOf(entry.householdId);
    }

    return '(Unknown Household)';
  }

  private static Integer countRows(List<DigestAssemblyItem> assemblyItems) {
    Integer count = 0;

    for (DigestAssemblyItem item : assemblyItems) {
      if (item.itemType == 'ROW') {
        count++;
      }
    }

    return count;
  }

  private static String escapeHtml(String value) {
    if (String.isBlank(value)) {
      return '';
    }

    return value.replace('&', '&amp;')
      .replace('<', '&lt;')
      .replace('>', '&gt;')
      .replace('"', '&quot;')
      .replace('\'', '&#39;');
  }

  private class DigestSortEntryComparator implements Comparator<DigestSortEntry> {
    public Integer compare(DigestSortEntry first, DigestSortEntry second) {
      if (first.changeDate == null && second.changeDate == null) {
        return compareLogIds(first, second);
      }

      if (first.changeDate == null) {
        return 1;
      }

      if (second.changeDate == null) {
        return -1;
      }

      if (first.changeDate == second.changeDate) {
        return compareLogIds(first, second);
      }

      return first.changeDate < second.changeDate ? -1 : 1;
    }

    private Integer compareLogIds(DigestSortEntry first, DigestSortEntry second) {
      String firstId = first.logRecord == null ? '' : String.valueOf(first.logRecord.Id);
      String secondId = second.logRecord == null ? '' : String.valueOf(second.logRecord.Id);
      return firstId.compareTo(secondId);
    }
  }
}