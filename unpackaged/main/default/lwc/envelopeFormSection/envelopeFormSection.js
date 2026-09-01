import { LightningElement, api } from 'lwc';

/**
 * envelopeFormSection — renders one section of a metadata-driven form: a heading above a column of
 * fields, each drawn by envelopeFieldControl. Presentational; it forwards field changes to its parent
 * via `valuechange` (envelopeFieldControl's own event doesn't bubble, so the section re-emits it).
 * The shaping and visibility of `section.fields` is done upstream (envelopeFormSchema.shapeVisibleFields).
 */
export default class EnvelopeFormSection extends LightningElement {
    // The section to render: { key, label, status?, fields: [shapedField] }, where each field is
    // already shaped for envelopeFieldControl (apiName, label, type, inputType, required, value, ...).
    @api section;

    // The active section's key (from the page). When it matches this section, the active marker shows.
    @api activeKey;

    get label() {
        return this.section?.label || '';
    }

    // The section renders its own heading unless the section opts out (hideHeader) — used when the
    // section stands alone in a group whose title already names it, so the two don't duplicate.
    get showHeader() {
        return !this.section?.hideHeader;
    }

    get fields() {
        return this.section?.fields || [];
    }

    // Root class carries the active state (drives the left marker).
    get sectionClass() {
        return this.section && this.section.key === this.activeKey
            ? 'section section_active'
            : 'section';
    }

    // Show the "Inputs missing" status while the section still owes input: an empty required field,
    // or a value that fails its configured format rule.
    get isIncomplete() {
        return this.section?.status === 'incomplete';
    }

    // Show the "Inputs updated" status when any of this section's fields has moved off the value
    // the request started from. Set upstream, alongside the per-field flags the marker reads from.
    // A section can owe input and carry changes at once, so this is independent of isIncomplete.
    get isUpdated() {
        return this.section?.updated === true;
    }

    get hasStatus() {
        return this.isIncomplete || this.isUpdated;
    }

    // A section that contains a Key Point field (Key_Decision__c) is marked with a "Key Point" badge
    // on its header.
    get hasKeyPoint() {
        return this.fields.some((field) => field.keyDecision);
    }

    // A custom section renders a dedicated body component (Trade Instructions, Related Parties)
    // instead of the metadata field loop; its whole value is stored under section.fieldKey.
    get isTradeInstructions() {
        return this.section?.type === 'tradeInstructions';
    }

    get isRelatedParties() {
        return this.section?.type === 'relatedParties';
    }

    // Validity sweep over this section's rendered field controls, completing the
    // envelopeActionDetails.reportValidity chain (which calls this on every section). Custom
    // bodies (trade instructions, related parties) render no field controls and pass.
    @api
    reportValidity() {
        let valid = true;
        this.template.querySelectorAll('c-envelope-field-control').forEach((control) => {
            // Only an explicit false is a failure — a control that can't answer doesn't block.
            if (typeof control.reportValidity === 'function' && control.reportValidity() === false) {
                valid = false;
            }
        });
        return valid;
    }

    @api
    checkValidity() {
        let valid = true;
        this.template.querySelectorAll('c-envelope-field-control').forEach((control) => {
            if (typeof control.checkValidity === 'function' && control.checkValidity() === false) {
                valid = false;
            }
        });
        return valid;
    }

    /**
     * Ask everything in this section to commit whatever it is still holding locally, completing the
     * envelopeActionDetails.flushPendingEdits chain (which calls this on every section). Trade
     * Instructions buffers its currency keystrokes, and a text-family Key Point field buffers its own.
     * Mirrors the reportValidity/checkValidity fan-out above so all three chains look the same.
     */
    @api
    flushPendingEdits() {
        this.template
            .querySelectorAll('c-envelope-trade-instructions, c-envelope-field-control')
            .forEach((body) => {
                if (typeof body.flushPendingEdits === 'function') {
                    body.flushPendingEdits();
                }
            });
    }

    /**
     * Put one field's control back on the value the draft holds, for an edit the page declined to
     * apply (a Key Point change the user backed out of). Addressed by API name because the page owns
     * the decision but only the control can rewrite what is rendered.
     */
    @api
    resetField(apiName) {
        const control = this.template.querySelector(
            `c-envelope-field-control[data-field="${apiName}"]`
        );
        if (control && typeof control.resetValue === 'function') {
            control.resetValue();
        }
    }

    // Re-dispatch a field's change so the page (which can't hear the non-bubbling child event) records
    // it in the form draft.
    handleFieldChange(event) {
        const { field, value } = event.detail || {};
        this.dispatchEvent(new CustomEvent('valuechange', { detail: { field, value } }));
    }

    // Re-dispatch a custom body's change as a normal field change, keyed by the section's fieldKey, so
    // the page stores the whole value object like any other field (and autosaves it).
    handleBodyChange(event) {
        this.dispatchEvent(
            new CustomEvent('valuechange', {
                detail: { field: this.section?.fieldKey, value: event.detail?.value }
            })
        );
    }

    // A related-party waiver is a field on the record rather than part of the section's composite
    // value, so it names its own field instead of the section's fieldKey and otherwise travels the
    // same path as any other answer.
    handleWaiverChange(event) {
        this.dispatchEvent(
            new CustomEvent('valuechange', {
                detail: {
                    field: event.detail?.field,
                    value: event.detail?.value
                }
            })
        );
    }
}