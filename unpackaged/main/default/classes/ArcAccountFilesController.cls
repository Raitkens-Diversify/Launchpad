/**
 * Files tab on the Account/Household/Business/Trust/Retirement Plan detail
 * page (arcHouseholdDetail): the Salesforce Files linked to the record,
 * newest first. A row opens through ArcFileViewerController.getFileData, the
 * way arcCheckLogDetail's Files card does, because the platform download
 * servlet is not served on the live-preview host.
 *
 * Its own class rather than a method on an existing one: the LWR site's Apex
 * invoker registry picks up a brand-new class immediately, while a method
 * added to an already-registered class stays unknown to running pages until
 * the site build refreshes (see ArcFileViewerController).
 *
 * USER_MODE, so only files the running user can already see come back.
 */
public with sharing class ArcAccountFilesController {
  @AuraEnabled(cacheable=true)
  public static List<FileInfo> getFiles(Id accountId) {
    List<FileInfo> results = new List<FileInfo>();
    if (accountId == null) {
      return results;
    }

    for (ContentDocumentLink link : [
      SELECT
        ContentDocumentId,
        ContentDocument.Title,
        ContentDocument.FileExtension,
        ContentDocument.ContentModifiedDate
      FROM ContentDocumentLink
      WHERE LinkedEntityId = :accountId
      WITH USER_MODE
      ORDER BY ContentDocument.ContentModifiedDate DESC
      LIMIT 100
    ]) {
      FileInfo info = new FileInfo();
      info.contentDocumentId = link.ContentDocumentId;
      info.title = link.ContentDocument.Title;
      info.fileExtension = link.ContentDocument.FileExtension;
      info.contentModifiedDate = link.ContentDocument.ContentModifiedDate;
      results.add(info);
    }
    return results;
  }

  public class FileInfo {
    @AuraEnabled
    public Id contentDocumentId;

    @AuraEnabled
    public String title;

    @AuraEnabled
    public String fileExtension;

    @AuraEnabled
    public Datetime contentModifiedDate;
  }
}