/**
 * Serves a file's bytes for in-browser viewing on the ARC site.
 *
 * The platform's own download endpoint (/sfc/servlet.shepherd/...) is not
 * served on the live-preview host (404), so pages open files from a blob
 * built out of this payload instead — identical behavior on preview and
 * published. First consumer: arcCheckLogDetail's Files card.
 *
 * Its own class rather than a method on ArcCheckLogController for a
 * deployment reason: the LWR site's Apex invoker registry picks up a brand
 * new class immediately, but a method added to an already-registered class
 * stays unknown to running pages until the site build refreshes ("Cannot
 * read properties of undefined (reading 'apply')" client-side, observed
 * live 2026-08-30). It is also genuinely reusable — nothing about it is
 * check-log-specific.
 *
 * Reads the latest version under USER_MODE, so only files the user can
 * already see come back. Files beyond the size cap return tooLarge=true
 * with no data (base64-encoding them would blow the Apex heap); the client
 * falls back to the platform download URL for those.
 */
public with sharing class ArcFileViewerController {
  @TestVisible
  private static final Integer MAX_FILE_PREVIEW_BYTES = 3 * 1024 * 1024;

  private static final Map<String, String> MIME_BY_EXTENSION = new Map<String, String>{
    'pdf' => 'application/pdf',
    'png' => 'image/png',
    'jpg' => 'image/jpeg',
    'jpeg' => 'image/jpeg',
    'gif' => 'image/gif'
  };

  // cacheable=false deliberately: this is called imperatively (a click
  // handler that opens a tab), and this site's LWR runtime can only
  // dispatch imperative calls down the non-cacheable POST path — an
  // imperative call to a cacheable method dies client-side in the invoker
  // ("Cannot read properties of undefined (reading 'apply')", observed
  // live 2026-08-30). Every working imperative call on this site
  // (postFeedComment, markComplete) is non-cacheable for the same reason.
  @AuraEnabled
  public static FilePayload getFileData(Id contentDocumentId) {
    if (contentDocumentId == null) {
      throw new AuraHandledException('No file was given.');
    }

    List<ContentVersion> versions = [
      SELECT Title, FileExtension, ContentSize, VersionData
      FROM ContentVersion
      WHERE ContentDocumentId = :contentDocumentId AND IsLatest = true
      WITH USER_MODE
      LIMIT 1
    ];
    if (versions.isEmpty()) {
      throw new AuraHandledException('This file is not available.');
    }

    ContentVersion version = versions[0];
    FilePayload payload = new FilePayload();
    payload.title = version.Title;
    String extension = version.FileExtension == null
      ? ''
      : version.FileExtension.toLowerCase();
    payload.mimeType = MIME_BY_EXTENSION.containsKey(extension)
      ? MIME_BY_EXTENSION.get(extension)
      : 'application/octet-stream';
    payload.tooLarge = version.ContentSize > MAX_FILE_PREVIEW_BYTES;
    if (!payload.tooLarge) {
      payload.base64Data = EncodingUtil.base64Encode(version.VersionData);
    }
    return payload;
  }

  public class FilePayload {
    @AuraEnabled
    public String title;

    @AuraEnabled
    public String mimeType;

    /** Base64 of the latest version's bytes; null when tooLarge. */
    @AuraEnabled
    public String base64Data;

    @AuraEnabled
    public Boolean tooLarge = false;
  }
}