import { LightningElement, api } from 'lwc';
import getRequiredDocuments from '@salesforce/apex/DocumentService.getRequiredDocuments';
import getUploadedFiles from '@salesforce/apex/DocumentService.getUploadedFiles';

/**
 * Author: Mile Cacanovic
 * 
 * envelopeReviewSubmit — the full-screen "Review & Submit" page: a read-only accordion summary
 * of the envelope's action items, the supporting documents, and the final submit confirmation.
 * The shell owns the summary data and handles every action this page raises (editreviewitem,
 * managedocuments, back, submitenvelope); the supporting documents are read directly from
 * DocumentService using the envelope id.
 */
export default class EnvelopeReviewSubmit extends LightningElement {
    /**
     * Accordion summary rows:
     * [{ key, icon: 'member'|'account', title, subtitle, expanded,
     *    sections: [{ key, title, fields: [{ key, label, value }] }] }]
     */
    @api reviewItems = [];

    // The Envelope__c id; drives the documents read below.
    @api envelopeId = '';

    documents = [];

    loading = true;

    // Gates the Submit Envelope button; submitting is final, so it stays disabled until the
    // user explicitly confirms the summary above.
    confirmChecked = false;

    // User expand/collapse overrides keyed by item key, applied on top of each item's `expanded`
    // default — so items arriving or rebuilding after mount keep working. Row keys are stable
    // action ids, so a manual collapse survives a parent rebuild.
    _expandedKeys = {};

    connectedCallback() {
        this._loadDocuments();
    }

    // View model for the accordion rows: resolves each row's icon (member vs account, matching
    // the workspace action cards) and its effective expand state.
    get items() {
        return (this.reviewItems || []).map((item) => {
            const isMember = item.icon === 'member';
            const expanded = this._expandedKeys[item.key] ?? Boolean(item.expanded);
            return {
                ...item,
                expanded,
                hasSections: (item.sections || []).length > 0,
                iconName: isMember ? 'utility:user' : 'utility:page',
                iconClass: isMember
                    ? 'review__item-icon review__item-icon_member'
                    : 'review__item-icon review__item-icon_account',
                caretIcon: expanded ? 'utility:chevronup' : 'utility:chevrondown'
            };
        });
    }

    get submitDisabled() {
        return !this.confirmChecked;
    }

    get hasDocuments() {
        return this.documents.length > 0;
    }

    // Manage Documents would open an empty screen while nothing is required, so the button
    // stays disabled until the documents read resolves with at least one of them.
    get manageDocumentsDisabled() {
        return this.loading || !this.hasDocuments;
    }

    // Only after loading resolves, so the note never flashes during the fetch.
    get showEmptyNote() {
        return !this.loading && !this.hasDocuments;
    }

    handleToggle(event) {
        const key = event.currentTarget.dataset.key;
        const item = (this.reviewItems || []).find((entry) => entry.key === key);
        const current = this._expandedKeys[key] ?? Boolean(item?.expanded);
        this._expandedKeys = { ...this._expandedKeys, [key]: !current };
    }

    handleEdit(event) {
        const key = event.currentTarget.dataset.key;
        this.dispatchEvent(new CustomEvent('editreviewitem', { detail: { key } }));
    }

    handleManageDocuments() {
        this.dispatchEvent(new CustomEvent('managedocuments'));
    }

    handleConfirmChange(event) {
        this.confirmChecked = event.target.checked;
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('back'));
    }

    handleSubmit() {
        this.dispatchEvent(new CustomEvent('submitenvelope'));
    }

    // Loads the envelope's required documents and resolves each one's linked file name.
    // Unlike Manage Documents, this page has no link/unlink flows, so documents map
    // straight to the envelopeDocumentCard shape.
    async _loadDocuments() {
        try {
            const [docs, files] = await Promise.all([
                getRequiredDocuments({ envelopeId: this.envelopeId }),
                getUploadedFiles({ envelopeId: this.envelopeId })
            ]);
            const fileNamesById = new Map(
                (files ?? []).map((file) => [file.ContentDocumentId, file.Title])
            );
            this.documents = (docs ?? []).map((doc) => ({
                id: doc.Id,
                name: doc.Name,
                // Join each signee's account name into the comma-separated string the card renders;
                // blank when the document has no signees.
                signees: doc.Signee__r?.length
                    ? doc.Signee__r.map((s) => s.Account__r?.Name).filter(Boolean).join(', ')
                    : '',
                linkedFileName:
                    fileNamesById.get(doc.ContentDocumentLinks?.[0]?.ContentDocumentId) ?? null
            }));
        } catch (error) {
            // The review page must never show stale documents; empty is the safe failure mode.
            this.documents = [];
            console.error('Error loading review documents:', error);
        } finally {
            this.loading = false;
        }
    }
}