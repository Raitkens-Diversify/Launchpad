import { LightningElement, api } from 'lwc';
import getFiles from '@salesforce/apex/UatRunController.getFiles';
import registerUploads from '@salesforce/apex/UatRunController.registerUploads';
import deleteFile from '@salesforce/apex/UatRunController.deleteFile';
import { messageFrom, toast } from 'c/messageUtil';

/** 1843200 → "1.8 MB"; null/0 → '' (older files predate the size column). */
function formatBytes(bytes) {
    if (!bytes || bytes <= 0) {
        return '';
    }
    if (bytes < 1024) {
        return bytes + ' B';
    }
    if (bytes < 1024 * 1024) {
        return (bytes / 1024).toFixed(bytes < 10 * 1024 ? 1 : 0) + ' KB';
    }
    return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
}

/**
 * uatEvidenceUpload — the tester app's evidence widget: multi-file upload via
 * real Salesforce Files (lightning-file-upload), thumbnail grid for images
 * (shepherd rendition URLs), a generic tile for other files, click-to-view,
 * and remove-with-confirmation through the shared adminConfirmModal.
 *
 * After every upload it calls registerUploads, which normalizes the new
 * ContentDocumentLinks to AllUsers visibility — without that, admins can't
 * see tester evidence. Attach evidence regardless of pass or fail (Standards
 * doc requirement, per the spec).
 *
 * Staging mode: lightning-file-upload hard-requires a record Id, so a form
 * whose record doesn't exist yet (a not-yet-saved finding) passes
 * staging-record-id (its parent session) instead. Uploads then target the
 * staging record, the tile list shows ONLY this instance's uploads
 * (_stagedDocIds), and the host reads stagedDocumentIds at save time to
 * claim them onto the real record (UatRunController.claimStagedFiles) or at
 * cancel to discard them. Setting record-id exits staging. Staging is inert
 * unless staging-record-id is set with no record-id — the runner's contract
 * (reloading record-id setter, fileschange {count}) is untouched.
 *
 * That per-instance filter is also what lets the session workspace point a
 * SECOND instance at the same session record in normal mode (its running-notes
 * evidence) without the finding form's in-flight staged uploads leaking into
 * it.
 */
export default class UatEvidenceUpload extends LightningElement {
    /* Getter/setter (not a plain @api field): the runner rebinds record-id on
     * every step change while REUSING this element, so a change must drop the
     * previous record's list and reload — otherwise the panel shows the prior
     * step's files. */
    _recordId;
    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        const changed = value !== this._recordId;
        this._recordId = value;
        if (changed && this._connected) {
            // A real record takes over — by now the host has claimed any
            // staged docs onto it, so the normal reload will show them.
            this._stagedDocIds = [];
            this.files = [];
            this.loadFiles();
        }
    }

    /** Staging parent (e.g. the session) for uploads made before the real
     *  record exists. Active only while record-id is empty. */
    @api stagingRecordId;

    @api label = 'Evidence';

    /** View-only: render the tiles, drop the upload control and the per-tile
     *  remove. Named viewOnly, NOT readonly — `readonly` is an ambiguous HTML
     *  attribute, so LWC does not route `readonly={x}` on a custom element to an
     *  @api of that name and the binding silently never arrives. */
    _viewOnly = false;
    @api
    get viewOnly() {
        return this._viewOnly;
    }
    set viewOnly(value) {
        this._viewOnly = value === '' ? true : Boolean(value);
    }

    files = [];
    loading = false;
    confirm = null;
    _connected = false;
    _stagedDocIds = [];

    get staging() {
        return !this._recordId && Boolean(this.stagingRecordId);
    }

    get uploadTargetId() {
        return this._recordId || this.stagingRecordId;
    }

    /** Docs uploaded by THIS instance while staging — what the host claims
     *  onto the saved record or discards on cancel. */
    @api
    get stagedDocumentIds() {
        return [...this._stagedDocIds];
    }

    get acceptedFormats() {
        return ['.png', '.jpg', '.jpeg', '.gif', '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.csv', '.txt', '.mp4', '.mov'];
    }

    connectedCallback() {
        this._connected = true;
        this.loadFiles();
    }

    @api
    async loadFiles() {
        if (!this.recordId && !this.staging) {
            return;
        }
        if (this.staging && this._stagedDocIds.length === 0) {
            this.files = [];
            return;
        }
        const requestedFor = this.uploadTargetId;
        this.loading = true;
        try {
            const files = await getFiles({ recordId: requestedFor });
            if (requestedFor !== this.uploadTargetId) {
                return; // stale response — the record changed mid-flight
            }
            // While staging, the parent record may carry other docs (earlier
            // leaks, sibling forms) — render only this instance's uploads.
            const visible = this.staging
                ? files.filter((f) => this._stagedDocIds.includes(f.contentDocumentId))
                : files;
            this.files = visible.map((f) => ({
                ...f,
                sizeLabel: formatBytes(f.contentSize)
            }));
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.loading = false;
        }
    }

    get hasFiles() {
        return this.files.length > 0;
    }

    get showUpload() {
        return !this.viewOnly && Boolean(this.uploadTargetId);
    }

    async handleUploadFinished(event) {
        const uploaded = event.detail.files;
        const docIds = uploaded.map((f) => f.documentId);
        if (this.staging) {
            this._stagedDocIds = [...this._stagedDocIds, ...docIds];
        }
        try {
            await registerUploads({ recordId: this.uploadTargetId, contentDocumentIds: docIds });
            await this.loadFiles();
            this.notifyFilesChange(uploaded.map((f) => ({
                contentDocumentId: f.documentId, title: f.name
            })));
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        }
    }

    /* detail.count lets the host track per-record evidence tallies (the
     * runner's step navigator + submit review) without a second query.
     * detail.added names just-uploaded files (empty on a removal) so a host can
     * reference them — the session workspace stamps a line in the running notes
     * for each. Additive: count-only consumers are untouched. */
    notifyFilesChange(added = []) {
        this.dispatchEvent(new CustomEvent('fileschange', {
            detail: { count: this.files.length, added }
        }));
    }

    handleRemoveClick(event) {
        const ds = event.currentTarget.dataset;
        this.confirm = {
            contentDocumentId: ds.docid,
            header: 'Remove evidence: ' + ds.title,
            message: 'The file is deleted and cannot be recovered.',
            confirmLabel: 'Remove'
        };
    }

    get confirmOpen() {
        return this.confirm !== null;
    }

    handleConfirmCancel() {
        this.confirm = null;
    }

    async handleConfirmProceed() {
        try {
            await deleteFile({
                contentDocumentId: this.confirm.contentDocumentId,
                recordId: this.uploadTargetId
            });
            if (this.staging) {
                this._stagedDocIds = this._stagedDocIds
                    .filter((id) => id !== this.confirm.contentDocumentId);
            }
            this.confirm = null;
            await this.loadFiles();
            this.notifyFilesChange();
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        }
    }

}