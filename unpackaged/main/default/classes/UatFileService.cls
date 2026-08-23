/**
 * UatFileService
 *
 * Salesforce Files plumbing shared by the UAT admin sections and the tester
 * app: list files on a record (with shepherd preview/download URLs, following
 * ResourceCenterService.fileInfoByResource), delete a file, and normalize
 * visibility after lightning-file-upload.
 *
 * Visibility note: files uploaded via lightning-file-upload get owner-only
 * ContentDocumentLink visibility by default — without normalizeVisibility,
 * admins can't see tester evidence and vice versa. Call it from every
 * uploadfinished handler's server round-trip.
 *
 * Deliberate divergence from ResourceAdminController.removeFile (which only
 * detaches the link): UAT evidence/reference files have no other home, so
 * deleteFile removes the ContentDocument itself after verifying it is
 * actually linked to the record the caller claims.
 *
 * Staging pattern (evidence before the record exists): lightning-file-upload
 * hard-requires a record Id, so a not-yet-saved finding uploads against its
 * parent session instead; on save, relinkFiles moves the links onto the
 * finding, and on cancel, deleteFiles discards the staged documents (owner
 * only). The gates live in the callers (UatRunController.claimStagedFiles /
 * discardStagedFiles) — these primitives stay domain-free.
 */
public with sharing class UatFileService {

    public class FileDTO {
        @AuraEnabled public Id contentDocumentId;
        @AuraEnabled public Id versionId;
        @AuraEnabled public String title;
        @AuraEnabled public String extension;
        @AuraEnabled public Boolean isImage;
        @AuraEnabled public String downloadUrl;
        @AuraEnabled public String thumbnailUrl;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public String uploadedByName;
        @AuraEnabled public Long contentSize;   // bytes; formatted client-side
    }

    private static final Set<String> IMAGE_EXTENSIONS = new Set<String>{
        'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg'
    };

    /** Files linked to one record, newest first. */
    public static List<FileDTO> getFilesFor(Id recordId) {
        Map<Id, List<FileDTO>> byRecord = getFilesFor(new Set<Id>{ recordId });
        return byRecord.containsKey(recordId) ? byRecord.get(recordId) : new List<FileDTO>();
    }

    /** Files linked to each record, newest first per record. */
    public static Map<Id, List<FileDTO>> getFilesFor(Set<Id> recordIds) {
        Map<Id, List<FileDTO>> result = new Map<Id, List<FileDTO>>();
        if (recordIds == null || recordIds.isEmpty()) {
            return result;
        }
        for (ContentDocumentLink cdl : [
            SELECT LinkedEntityId, ContentDocumentId,
                ContentDocument.Title, ContentDocument.FileExtension,
                ContentDocument.LatestPublishedVersionId, ContentDocument.ContentSize,
                ContentDocument.CreatedDate, ContentDocument.CreatedBy.Name
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :recordIds
            ORDER BY ContentDocument.CreatedDate DESC
        ]) {
            FileDTO dto = new FileDTO();
            dto.contentDocumentId = cdl.ContentDocumentId;
            dto.versionId = cdl.ContentDocument.LatestPublishedVersionId;
            dto.title = cdl.ContentDocument.Title;
            dto.extension = cdl.ContentDocument.FileExtension;
            dto.isImage = cdl.ContentDocument.FileExtension != null
                && IMAGE_EXTENSIONS.contains(cdl.ContentDocument.FileExtension.toLowerCase());
            dto.downloadUrl = '/sfc/servlet.shepherd/document/download/' + cdl.ContentDocumentId;
            dto.thumbnailUrl = '/sfc/servlet.shepherd/version/renditionDownload?rendition=THUMB720BY480&versionId='
                + dto.versionId;
            dto.createdDate = cdl.ContentDocument.CreatedDate;
            dto.uploadedByName = cdl.ContentDocument.CreatedBy.Name;
            dto.contentSize = cdl.ContentDocument.ContentSize;
            if (!result.containsKey(cdl.LinkedEntityId)) {
                result.put(cdl.LinkedEntityId, new List<FileDTO>());
            }
            result.get(cdl.LinkedEntityId).add(dto);
        }
        return result;
    }

    /**
     * Delete a ContentDocument, but only when it really is linked to the
     * record the caller names — prevents deleting arbitrary files by Id.
     */
    public static void deleteFile(Id contentDocumentId, Id linkedRecordId) {
        Integer linked = [
            SELECT COUNT() FROM ContentDocumentLink
            WHERE ContentDocumentId = :contentDocumentId
            AND LinkedEntityId = :linkedRecordId
        ];
        if (linked == 0) {
            throw new UatFileException('That file is not attached to this record.');
        }
        delete new ContentDocument(Id = contentDocumentId);
    }

    /**
     * Move documents from one record to another: verifies every doc is
     * actually linked to fromRecordId (the staging claim), inserts links on
     * toRecordId (skipping any already there — idempotent for retries), then
     * deletes the staging links. The documents themselves are untouched.
     */
    public static void relinkFiles(Id fromRecordId, Id toRecordId, List<Id> contentDocumentIds) {
        if (contentDocumentIds == null || contentDocumentIds.isEmpty()) {
            return;
        }
        List<ContentDocumentLink> fromLinks = [
            SELECT Id, ContentDocumentId FROM ContentDocumentLink
            WHERE LinkedEntityId = :fromRecordId
            AND ContentDocumentId IN :contentDocumentIds
        ];
        Set<Id> staged = new Set<Id>();
        for (ContentDocumentLink cdl : fromLinks) {
            staged.add(cdl.ContentDocumentId);
        }
        for (Id docId : contentDocumentIds) {
            if (!staged.contains(docId)) {
                throw new UatFileException('That file is not attached to this record.');
            }
        }
        Set<Id> alreadyLinked = new Set<Id>();
        for (ContentDocumentLink cdl : [
            SELECT ContentDocumentId FROM ContentDocumentLink
            WHERE LinkedEntityId = :toRecordId
            AND ContentDocumentId IN :contentDocumentIds
        ]) {
            alreadyLinked.add(cdl.ContentDocumentId);
        }
        List<ContentDocumentLink> inserts = new List<ContentDocumentLink>();
        for (Id docId : contentDocumentIds) {
            if (!alreadyLinked.contains(docId)) {
                inserts.add(new ContentDocumentLink(
                    ContentDocumentId = docId,
                    LinkedEntityId = toRecordId,
                    ShareType = 'V',
                    Visibility = 'AllUsers'
                ));
            }
        }
        if (!inserts.isEmpty()) {
            insert inserts;
        }
        delete fromLinks;
    }

    /**
     * Link every document already on fromRecordId onto toRecordId as well,
     * WITHOUT unlinking the source — the copy half of relinkFiles.
     *
     * Promoting a session entry to a finding uses this: the finding needs the
     * screenshot as its evidence, and the entry needs to keep it too, because
     * the timeline is the tester's own record of what they saw and stripping it
     * would rewrite history. Same ContentDocument, two links, one file in
     * storage.
     *
     * Idempotent — re-promoting or retrying skips links that already exist.
     * @return the document ids now linked to toRecordId.
     */
    public static List<Id> copyLinks(Id fromRecordId, Id toRecordId) {
        List<Id> docIds = new List<Id>();
        for (ContentDocumentLink cdl : [
            SELECT ContentDocumentId FROM ContentDocumentLink
            WHERE LinkedEntityId = :fromRecordId
        ]) {
            docIds.add(cdl.ContentDocumentId);
        }
        if (docIds.isEmpty()) {
            return docIds;
        }
        Set<Id> alreadyLinked = new Set<Id>();
        for (ContentDocumentLink cdl : [
            SELECT ContentDocumentId FROM ContentDocumentLink
            WHERE LinkedEntityId = :toRecordId AND ContentDocumentId IN :docIds
        ]) {
            alreadyLinked.add(cdl.ContentDocumentId);
        }
        List<ContentDocumentLink> inserts = new List<ContentDocumentLink>();
        for (Id docId : docIds) {
            if (!alreadyLinked.contains(docId)) {
                inserts.add(new ContentDocumentLink(
                    ContentDocumentId = docId,
                    LinkedEntityId = toRecordId,
                    ShareType = 'V',
                    Visibility = 'AllUsers'
                ));
            }
        }
        if (!inserts.isEmpty()) {
            insert inserts;
        }
        return docIds;
    }

    /**
     * deleteFile for a staged batch, with an explicit ownership filter: only
     * the uploader may discard, and only docs actually linked to the named
     * record — a friendly error instead of a DML ownership failure.
     */
    public static void deleteFiles(Id linkedRecordId, List<Id> contentDocumentIds) {
        if (contentDocumentIds == null || contentDocumentIds.isEmpty()) {
            return;
        }
        Set<Id> linked = new Set<Id>();
        for (ContentDocumentLink cdl : [
            SELECT ContentDocumentId FROM ContentDocumentLink
            WHERE LinkedEntityId = :linkedRecordId
            AND ContentDocumentId IN :contentDocumentIds
        ]) {
            linked.add(cdl.ContentDocumentId);
        }
        for (Id docId : contentDocumentIds) {
            if (!linked.contains(docId)) {
                throw new UatFileException('That file is not attached to this record.');
            }
        }
        List<ContentDocument> owned = [
            SELECT Id FROM ContentDocument
            WHERE Id IN :contentDocumentIds
            AND OwnerId = :UserInfo.getUserId()
        ];
        if (owned.size() != contentDocumentIds.size()) {
            throw new UatFileException('You can only remove files you uploaded.');
        }
        delete owned;
    }

    /**
     * Post-upload normalization: make freshly-uploaded files visible to all
     * internal users on the record, not just the uploader.
     */
    public static void normalizeVisibility(Id recordId, List<Id> contentDocumentIds) {
        if (contentDocumentIds == null || contentDocumentIds.isEmpty()) {
            return;
        }
        List<ContentDocumentLink> links = [
            SELECT Id, Visibility FROM ContentDocumentLink
            WHERE LinkedEntityId = :recordId
            AND ContentDocumentId IN :contentDocumentIds
        ];
        List<ContentDocumentLink> changed = new List<ContentDocumentLink>();
        for (ContentDocumentLink cdl : links) {
            if (cdl.Visibility != 'AllUsers') {
                cdl.Visibility = 'AllUsers';
                changed.add(cdl);
            }
        }
        if (!changed.isEmpty()) {
            update changed;
        }
    }

    public class UatFileException extends Exception {}
}