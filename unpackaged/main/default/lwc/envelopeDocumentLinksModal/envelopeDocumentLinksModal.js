import { LightningElement, api } from 'lwc';

/**
 * Author: Mile Cacanovic
 *
 * envelopeDocumentLinksModal — the "Manage document links" dialog opened from a completed
 * uploaded file row on the Manage Documents screen. It lists the envelope's Supporting
 * Documents as checkboxes and lets the user link the file to one or more of them. It composes
 * the shared modal shell (dsModalV2) and owns no persistence: it dispatches `confirm` (with the
 * selected document ids) and `close`, leaving the host (envelopeManageDocuments) to act on the
 * selection.
 *
 * Business rule: one file can link to many documents, but each document can be linked to only
 * one file. A document already linked to another file renders checked-and-disabled with a
 * "Linked to {fileName}" subline so it can't be claimed twice; a document linked to THIS file
 * renders checked-and-enabled so it can be unlinked. Accept is enabled only when the selection
 * differs from the file's currently-linked set (a dirty check).
 *
 * Opened imperatively via a DOM ref (`open()`/`close()`) rather than an is-open flag, matching
 * the other V2 dialogs in envelopeShellV2. `open()` snapshots the current links from the
 * `documents` prop, so the host must let that prop flush before calling it (it defers the call).
 */
export default class EnvelopeDocumentLinksModal extends LightningElement {
    // The current file's name; drives the tagline.
    @api fileName = '';

    // Rows computed by the host: { id, name, linkedHere, linkedToFileName }.
    //   linkedHere       — document is linked to the file this modal was opened for
    //   linkedToFileName — name of the OTHER file that owns this document, or null
    @api documents = [];

    _isOpen = false;
    // Document ids checked among the enabled rows.
    _selected = new Set();
    // Snapshot of _selected at open time, for the Accept dirty check.
    _initial = new Set();

    @api
    get isOpen() {
        return this._isOpen;
    }
    set isOpen(value) {
        this._isOpen = value;
    }

    // Imperative open/close so the host can drive the dialog from JS via a DOM ref. Opening
    // snapshots the file's currently-linked documents into both the live selection and the
    // dirty-check baseline.
    @api
    open() {
        const linked = (this.documents || [])
            .filter((doc) => doc.linkedHere)
            .map((doc) => doc.id);
        this._selected = new Set(linked);
        this._initial = new Set(linked);
        this._isOpen = true;
    }

    @api
    close() {
        this._isOpen = false;
    }

    // Tagline filename is rendered bold by the template's <strong>.
    get fileNameDisplay() {
        return this.fileName;
    }

    // Render model: each document plus its checkbox state and the matching row class. A document
    // linked to another file is disabled and always shown checked; one linked to this file is
    // checked-and-enabled; an unlinked document is unchecked-and-enabled.
    get rows() {
        return (this.documents || []).map((doc) => {
            const disabled = Boolean(doc.linkedToFileName);
            const checked = doc.linkedHere || disabled;
            const classes = ['doc-links__row'];
            if (disabled) {
                classes.push('doc-links__row_disabled');
            }
            return {
                id: doc.id,
                name: doc.name,
                checked,
                disabled,
                subtext: doc.linkedToFileName,
                rowClass: classes.join(' ')
            };
        });
    }

    // Accept is dirty-gated: disabled until the selection differs from the snapshot.
    get acceptDisabled() {
        if (this._selected.size !== this._initial.size) {
            return false;
        }
        for (const id of this._selected) {
            if (!this._initial.has(id)) {
                return false;
            }
        }
        return true;
    }

    handleToggle(event) {
        const id = event.currentTarget.dataset.id;
        if (event.target.checked) {
            this._selected.add(id);
        } else {
            this._selected.delete(id);
        }
        // Reassign so acceptDisabled re-evaluates with the new selection.
        this._selected = new Set(this._selected);
    }

    handleAccept() {
        this.dispatchEvent(
            new CustomEvent('confirm', { detail: { selectedDocIds: [...this._selected] } })
        );
        this._isOpen = false;
    }

    // Cancel, the X, the backdrop, and Esc all surface as dsModalV2's `close`; close without
    // saving.
    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }
}