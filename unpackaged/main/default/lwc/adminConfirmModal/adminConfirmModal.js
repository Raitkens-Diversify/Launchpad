import { LightningElement, api } from 'lwc';

/**
 * adminConfirmModal — the one confirmation dialog for every destructive admin
 * action (Help Center and UAT console sections, the tester app). Pixel-matches
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
 * confirm. prompt-required blocks confirm while it's blank.
 *
 * Opt-in choice (category delete: "move subtopics up" vs "keep until empty"):
 * pass `choices` [{ label, value }] (+ `choice-label`, `default-choice`) to
 * render a radio group; the picked value arrives as event.detail.choice.
 * Existing consumers pass none of these and see no change.
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
    /** When non-empty, renders a radio group of { label, value } choices. */
    @api choices = [];
    @api choiceLabel = 'How should this be handled?';

    _promptRequired = false;
    @api
    get promptRequired() {
        return this._promptRequired;
    }
    set promptRequired(value) {
        this._promptRequired = value === '' ? true : Boolean(value);
    }

    _choice = '';
    @api
    get defaultChoice() {
        return this._choice;
    }
    set defaultChoice(value) {
        this._choice = value || '';
    }

    comment = '';

    get confirmVariant() {
        return this.variant === 'brand' ? 'brand' : 'destructive';
    }

    get hasPrompt() {
        return Boolean(this.promptLabel);
    }

    get hasChoices() {
        return Array.isArray(this.choices) && this.choices.length > 0;
    }

    get choiceOptions() {
        return this.hasChoices ? this.choices.map((c) => ({ label: c.label, value: c.value })) : [];
    }

    get confirmDisabled() {
        return this.busy
            || (this.hasPrompt && this._promptRequired && !this.comment.trim())
            || (this.hasChoices && !this._choice);
    }

    handleCommentChange(event) {
        this.comment = event.target.value;
    }

    handleChoiceChange(event) {
        this._choice = event.detail.value;
    }

    handleCancel() {
        this.comment = '';
        this.dispatchEvent(new CustomEvent('cancel'));
    }

    handleConfirm() {
        const comment = this.comment.trim();
        this.comment = '';
        this.dispatchEvent(new CustomEvent('confirm', {
            detail: { comment, choice: this.hasChoices ? this._choice : undefined }
        }));
    }

    handleKeydown(event) {
        if (event.key === 'Escape') {
            this.handleCancel();
        }
    }
}