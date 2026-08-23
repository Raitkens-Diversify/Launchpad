import { LightningElement, api } from 'lwc';
import LightningToast from 'lightning/toast';
import updateContentDocumentLinks from '@salesforce/apex/DocumentService.updateContentDocumentLinks';
import getRequiredDocuments from '@salesforce/apex/DocumentService.getRequiredDocuments';
import getUploadedFiles from '@salesforce/apex/DocumentService.getUploadedFiles';
import removeFile from '@salesforce/apex/DocumentService.removeFile';

// Mock supporting documents until the document model is wired to Apex. Each renders as an
// envelopeDocumentCard in the right column.
// `linkedFileId` is the single source of truth for file↔document links: the id of the uploaded
// file this document is linked to, or null when unlinked. One file links to many documents, but
// each document links to at most one file, so ownership lives on the document.
const MOCK_DOCUMENTS = [
    { id: 'doc-1', name: 'Document Name 1', signees: 'Buster Bunny', linkedFileId: null },
    { id: 'doc-2', name: 'Document Name 2', signees: 'Buster Bunny', linkedFileId: null },
    { id: 'doc-3', name: 'Document Name 3', signees: 'Buster Bunny, Bugs Bunny', linkedFileId: null }
];

// Simulated upload cadence: advance each in-progress file by UPLOAD_STEP percent every
// UPLOAD_TICK_MS, so a file reaches 100% in roughly two seconds.
const UPLOAD_STEP = 10;
const UPLOAD_TICK_MS = 200;

/**
 * Author: Mile Cacanovic
 *
 * envelopeManageDocuments — the Manage Documents content screen for envelopeShellV2.
 * Shows the envelope's supporting documents and a file-selector drop area. Files picked via
 * browse or drag-and-drop are uploaded by lightning-file-upload, which reports progress in
 * its own dialog and links each file to the envelope; completed files are then listed under
 * "Uploaded Files". That dialog renders in the overlay layer, outside this component, and is
 * themed in the shared stylesheet (envelopeWizardStyles) rather than here. Renders inside the
 * shell's content grid, which provides the outer width, centering, and padding. Dispatches
 * `back` to return to the items view.
 */
export default class EnvelopeManageDocuments extends LightningElement {
    @api envelopeTitle = '';
    @api householdName = '';
    @api envelopeId= '';

    documents = [];

    // Files chosen via the file-selector (browse or drop). Client-side only for now.
    uploadedFiles = [];

    // Removal confirmation: the file pending removal drives the dialog copy and the
    // document-link warning. Set when "Remove file" is chosen, cleared on confirm/cancel.
    pendingRemoveName = '';

    // True while the remove call is in flight — drives the spinner over the confirm button
    // and disables the footer so the dialog stays put until the action resolves.
    isRemoving = false;

    // Id of the file whose "Manage document links" dialog is open, or null when none is.
    _linkFileId = null;

    // "Household - Envelope"; either part is dropped if empty.
    get subtitle() {
        return [this.householdName, this.envelopeTitle].filter(Boolean).join(' - ');
    }

    get hasUploadedFiles() {
        return this.uploadedFiles.length > 0;
    }

    // Documents projected for the card list, each resolving its linked file's name (by
    // linkedFileId) so the card can show the "File linked" badge and the file name. Read-only
    // over `documents`; the raw store stays the source of truth.
    get documentRows() {
        return this.documents.map((doc) => {
            const file = doc.linkedFileId
                ? this.uploadedFiles.find((f) => f.id === doc.linkedFileId)
                : null;
            return {
                id: doc.id,
                name: doc.name,
                signees: doc.signees,
                linkedFileName: file?.name ?? null
            };
        });
    }

    // Files plus the documents each one currently owns (by linkedFileId), for the card's link
    // list. A read-only projection over uploadedFiles; the raw store stays the source of truth.
    get fileRows() {
        return this.uploadedFiles.map((file) => {
            const linkedDocs = this.documents
                .filter((doc) => doc.linkedFileId === file.id)
                .map((doc) => ({ id: doc.id, name: doc.name }));
            return { ...file, linkedDocs, hasLinks: linkedDocs.length > 0 };
        });
    }

    // Documents currently linked to the file pending removal (by name); drives the unlink warning.
    get pendingRemoveLinks() {
        return this.documents
            .filter((doc) => doc.linkedFileId === this._pendingRemoveId)
            .map((doc) => doc.name);
    }

    get pendingRemoveHasLinks() {
        return this.pendingRemoveLinks.length > 0;
    }

    // The removal dialog warns about lost document links only when the file has them.
    get removeMessage() {
        return this.pendingRemoveHasLinks
            ? 'This will permanently remove file. All of the active links with the documents will be lost.'
            : 'This will permanently remove file.';
    }

    // Name of the file whose links dialog is open; drives the dialog tagline.
    get linkModalFileName() {
        return this.uploadedFiles.find((file) => file.id === this._linkFileId)?.name ?? '';
    }

    // Per-document rows for the links dialog, computed for the currently-open file: linkedHere
    // when this file owns the document; linkedToFileName names the OTHER file that owns it.
    get linkModalRows() {
        return this.documents.map((doc) => {
            const linkedHere = doc.linkedFileId === this._linkFileId;
            const otherOwner =
                doc.linkedFileId && doc.linkedFileId !== this._linkFileId
                    ? this.uploadedFiles.find((file) => file.id === doc.linkedFileId)
                    : null;
            return {
                id: doc.id,
                name: doc.name,
                linkedHere,
                linkedToFileName: otherOwner?.name ?? null
            };
        });
    }

async connectedCallback() {
     try {

        await this._loadUploadedFiles();

        const docs = await getRequiredDocuments({
                    envelopeId : this.envelopeId
                });
                if(docs != null){
                this.documents = docs.map(doc => ({
                            ...doc,
                            id : doc.Id,
                            name : doc.Name,
                linkedFileId: doc.ContentDocumentLinks?.length
                ? doc.ContentDocumentLinks[0].ContentDocumentId
                : null,
                            // Join each signee's account name into the comma-separated string the card renders.
                            signees: doc.Signee__r?.length
                                ? doc.Signee__r.map((s) => s.Account__r?.Name).filter(Boolean).join(', ')
                                : null
                        }));
                }else{
                    this.documents = MOCK_DOCUMENTS;
                }
        
    } catch (error) {
        console.error('Error loading required documents:', error);
    }
}


    // Uploads go through the standard platform dialog. Its uploadfinished payload reports file
    // names without a reliable extension, so instead of building rows from the event we re-read
    // the list from the server, where each row carries its canonical Title and FileExtension.
    async handleFilesChange() {
        try {
            await this._loadUploadedFiles();
        } catch (error) {
            console.error('Error refreshing uploaded files:', error);
        }
    }

    // Per-file more-actions menu. "Remove file" opens a confirmation dialog; "Download" round-trips
    // the real File the user picked (kept in _fileBlobs) back to the browser as a download.
    handleFileMenuSelect(event) {
        const action = event.detail.value;
        const { id, name } = event.currentTarget.dataset;
        if (action === 'remove') {
            this._pendingRemoveId = id;
            this.pendingRemoveName = name;
            this.refs.removeModal.open();
        } else if (action === 'download') {
            //const blob = this._fileBlobs.get(id);
            if (id) {
                this._downloadFile(id)
                //this._downloadFile(name,blob);
            } else {
                // Defensive: every listed file came from a real pick, so this shouldn't happen.
                this._showToast('Download', `Downloading "${name}" is not available yet.`, 'info');
            }
        }
    }

    // Remove the file server-side first and only mirror the result locally on success, so the
    // list never shows a removal that didn't happen. The dialog stays open with a spinner for
    // the duration; on error it surfaces a toast and stays open to retry.
    async handleRemoveConfirm() {
        const fileId = this._pendingRemoveId;
        this.isRemoving = true;
        try {
            await removeFile({ fileId });
            // Deleting the ContentDocument also drops its links, so unlink locally to match.
            this.documents = this.documents.map((doc) =>
                doc.linkedFileId === fileId ? { ...doc, linkedFileId: null } : doc
            );
            this.uploadedFiles = this.uploadedFiles.filter((file) => file.id !== fileId);
            this._closeRemoveDialog();
        } catch (error) {
            console.error('Failed to remove file', error);
            const message = error?.body?.message || error?.message || 'Unable to remove file.';
            this._showToast('Remove failed', message, 'error');
        } finally {
            this.isRemoving = false;
        }
    }

    // Cancel / X / backdrop. Ignored while the removal is in flight so the dialog can't be
    // dismissed out from under a running call.
    handleRemoveClose() {
        if (this.isRemoving) {
            return;
        }
        this._closeRemoveDialog();
    }

    // Open the "Manage document links" dialog for the chosen file. Setting _linkFileId refreshes
    // the dialog's file-name/documents bindings; defer open() so those props flush before the
    // dialog snapshots them (same idiom as envelopeShellV2's deferred view changes).
    handleLinkDocuments(event) {
        this._linkFileId = event.currentTarget.dataset.id;
        Promise.resolve().then(() => this.refs.linksModal.open());
    }

    // Apply the dialog's selection to this file's links. Only documents selectable in this
    // context (unlinked, or already linked to this file) are touched, so another file's links
    // are never disturbed.
    // handleLinkConfirm(event) {
    //     const selected = new Set(event.detail?.selectedDocIds ?? []);
    //     this.linkDocument(selected);
    //     this.documents = this.documents.map((doc) => {
    //         const selectable = doc.linkedFileId === null || doc.linkedFileId === this._linkFileId;
    //         if (!selectable) {
    //             return doc;
    //         }
    //         return { ...doc, linkedFileId: selected.has(doc.id) ? this._linkFileId : null };
    //     });
    //     this.refs.linksModal.close();
    // }

handleLinkConfirm(event) {
    const selected = new Set(event.detail?.selectedDocIds ?? []);

    // Previously linked to this file
    const previouslySelected = new Set(
        this.documents
            .filter(doc => doc.linkedFileId === this._linkFileId)
            .map(doc => doc.id)
    );

    // Newly selected (need to insert CDL)
    const idsToLink = [...selected].filter(id => !previouslySelected.has(id));

    // Previously selected but now unselected (need to remove CDL)
    const idsToUnlink = [...previouslySelected].filter(id => !selected.has(id));

    if (idsToLink.length || idsToUnlink.length) {
        this.linkDocument(idsToLink,idsToUnlink);
    }

    this.documents = this.documents.map(doc => {
        const selectable =
            doc.linkedFileId === null ||
            doc.linkedFileId === this._linkFileId;

        if (!selectable) {
            return doc;
        }

        return {
            ...doc,
            linkedFileId: selected.has(doc.id) ? this._linkFileId : null
        };
    });

    this.refs.linksModal.close();
}



    async linkDocument(idsToLink, idsToUnlink) {
        try {
            await updateContentDocumentLinks({
                contentDocumentId: this._linkFileId,
                idsToLink: [...idsToLink],
                idsToUnlink: [...idsToUnlink]
            });

            console.log('ContentDocumentLinks created successfully.');
        } catch (error) {
            console.error('Error creating ContentDocumentLinks:', error);
        }
    }

    handleLinkClose() {
        this.refs.linksModal.close();
    }

    // Abort an in-progress upload: drop the file and stop the timer if nothing else is uploading.
    handleCancelUpload(event) {
        const { id } = event.currentTarget.dataset;
        this.uploadedFiles = this.uploadedFiles.filter((file) => file.id !== id);
        this._fileBlobs.delete(id);
        if (!this.uploadedFiles.some((file) => file.uploading)) {
            this._stopUploadSimulation();
        }
    }

    handleBack() {
        this.dispatchEvent(new CustomEvent('back'));
    }

    disconnectedCallback() {
        this._stopUploadSimulation();
    }

    // Tick every in-progress file forward; mark each complete at 100%, then stop once none remain.
    _advanceUploads() {
        let anyUploading = false;
        this.uploadedFiles = this.uploadedFiles.map((file) => {
            if (!file.uploading) {
                return file;
            }
            const progress = Math.min(100, file.progress + UPLOAD_STEP);
            const uploading = progress < 100;
            if (uploading) {
                anyUploading = true;
            }
            return {
                ...file,
                progress,
                uploading,
                progressLabel: this._uploadLabel(file.size, progress)
            };
        });
        if (!anyUploading) {
            this._stopUploadSimulation();
        }
    }

    _startUploadSimulation() {
        if (this._uploadTimer) {
            return;
        }
        this._uploadTimer = window.setInterval(() => this._advanceUploads(), UPLOAD_TICK_MS);
    }

    _stopUploadSimulation() {
        if (this._uploadTimer) {
            window.clearInterval(this._uploadTimer);
            this._uploadTimer = null;
        }
    }

    // Loads the envelope's uploaded files and replaces the local list. Each row's doctype icon
    // is resolved from the stored FileExtension, matching what the platform upload dialog shows.
    async _loadUploadedFiles() {
        const files = await getUploadedFiles({
            envelopeId: this.envelopeId
        });
        if (files != null) {
            this.uploadedFiles = files.map((file) => ({
                ...file,
                linkedFileId: null,
                signees: null,
                id: file.ContentDocumentId,
                name: file.Title,
                iconName: this._iconForExtension(file.FileExtension)
            }));
        }
    }

    // Maps a file extension to its document-type icon, covering the file-selector's accepted types.
    _iconForExtension(ext) {
        const icons = {
            pdf: 'doctype:pdf',
            zip: 'doctype:zip',
            doc: 'doctype:word',
            docx: 'doctype:word',
            xls: 'doctype:excel',
            xlsx: 'doctype:excel'
        };
        return icons[ext?.toLowerCase()] || 'doctype:unknown';
    }

    // "1.2MB / 2.4MB - 50%": bytes uploaded over total plus percent; total is derived from the
    // real file size. Falls back to just the percent when the size is unknown.
    _uploadLabel(size, progress) {
        if (!size || size <= 0) {
            return `${progress}%`;
        }
        const uploaded = Math.round((size * progress) / 100);
        return `${this._formatBytes(uploaded)} / ${this._formatBytes(size)} - ${progress}%`;
    }

    _formatBytes(bytes) {
        if (!bytes || bytes <= 0) {
            return '0KB';
        }
        const kb = bytes / 1024;
        if (kb < 1024) {
            return `${Math.round(kb)}KB`;
        }
        return `${(kb / 1024).toFixed(1)}MB`;
    }

    // Close the removal dialog and clear the pending-file state it reads from.
    _closeRemoveDialog() {
        this.refs.removeModal.close();
        this._pendingRemoveId = null;
        this.pendingRemoveName = '';
    }

    _showToast(title, message, variant) {
        LightningToast.show({ label: title, message, variant }, this);
    }

    // Trigger a browser download of a Blob/File under the given filename via a transient object
    // URL and a hidden anchor; revokes the URL afterward to avoid leaks. Mirrors bookOfBusinessUtils
    // downloadCsv, kept local since we already have a Blob (not string content) and to avoid coupling.
    _downloadFile(contentDocumentId) {
        window.location.href = `/sfc/servlet.shepherd/document/download/${contentDocumentId}`;
    }
    //  _downloadFile(filename, blob) {
    //     if (typeof document === 'undefined' || !blob) {
    //         return;
    //     }
    //     const url = URL.createObjectURL(blob);
    //     const anchor = document.createElement('a');
    //     anchor.href = url;
    //     anchor.download = filename;
    //     anchor.style.visibility = 'hidden';
    //     document.body.appendChild(anchor);
    //     anchor.click();
    //     document.body.removeChild(anchor);
    //     URL.revokeObjectURL(url);
    // }

    // Raw File objects for picked uploads, keyed by file id, so Download can round-trip the actual
    // content. Non-reactive: uploadedFiles holds only plain metadata.
    _fileBlobs = new Map();

    // Id of the file awaiting removal confirmation, or null when no dialog is pending.
    _pendingRemoveId = null;

    // Monotonic counter for stable list keys across additions/removals.
    _fileSeq = 0;

    // Handle of the simulated-upload interval, or null when idle.
    _uploadTimer = null;
}