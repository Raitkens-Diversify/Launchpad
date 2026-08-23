import { LightningElement, api } from 'lwc';

/**
 * adminConfirmModal — the one confirmation dialog for every destructive UAT
 * action, on both surfaces (console sections and the tester app). Pixel-matches
 * the console's inline confirm-dialog convention (adminArticleList's
 * .aal-modal): title "{Verb}: {name}", a plain-language consequence sentence,
 * Cancel + a destructive-variant confirm button. Nothing is destroyed on the
 * first click anywhere.
 *
 * Parents render it conditionally (template if:true) and pass the wording:
 *   <c-admin-confirm-modal header="Remove step: Step 3"
 *                          message="Removing this step deletes its recorded results…"
 *                          confirm-label="Remove"
 *                          onconfirm={...} oncancel={...}>
 *
 * Opt-in reason capture (pool release/unassign flows): set prompt-label to
 * render a textarea; its trimmed value arrives as event.detail.comment on
 * confirm. prompt-required blocks confirm while it's blank. Existing
 * consumers pass neither and see no change.
 */
export default class AdminConfirmModal extends LightningElement {
    @api header = '';
    @api message = '';
    @api confirmLabel = 'Remove';
    /** 'destructive' (default) or 'brand' for non-destructive confirmations. */
    @api variant = 'destructive';
    @api busy = false;
    /** When set, renders a comment textarea with this label. */
    @api promptLabel = '';

    _promptRequired = false;
    @api
    get promptRequired() {
        return this._promptRequired;
    }
    set promptRequired(value) {
        this._promptRequired = value === '' ? true : Boolean(value);
    }

    comment = '';

    get confirmVariant() {
        return this.variant === 'brand' ? 'brand' : 'destructive';
    }

    get hasPrompt() {
        return Boolean(this.promptLabel);
    }

    get confirmDisabled() {
        return this.busy
            || (this.hasPrompt && this._promptRequired && !this.comment.trim());
    }

    handleCommentChange(event) {
        this.comment = event.target.value;
    }

    handleCancel() {
        this.comment = '';
        this.dispatchEvent(new CustomEvent('cancel'));
    }

    handleConfirm() {
        const comment = this.comment.trim();
        this.comment = '';
        this.dispatchEvent(new CustomEvent('confirm', { detail: { comment } }));
    }

    handleKeydown(event) {
        if (event.key === 'Escape') {
            this.handleCancel();
        }
    }
}