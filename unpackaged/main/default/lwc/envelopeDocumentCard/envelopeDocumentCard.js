import { LightningElement, api } from 'lwc';

/**
 * Author: Mile Cacanovic
 * 
 * envelopeDocumentCard — presentational card for a single supporting document.
 * Renders a document icon, the document name, and its signees. Display only;
 * the parent owns the document data.
 */
export default class EnvelopeDocumentCard extends LightningElement {
    @api name = '';
    // Comma-separated signee names, rendered after the "Signees:" label.
    @api signees = '';
    // Name of the file linked to this document, or null/empty when unlinked.
    // Drives the "File linked" badge and the linked-file row.
    @api linkedFileName = null;

    get hasLinkedFile() {
        return Boolean(this.linkedFileName);
    }

    get hasSignees() {
        return Boolean(this.signees);
    }
}