import { LightningElement, api } from 'lwc';
import {
    applyInputMask,
    COMMIT_IDLE_MS,
    draftValuesEqual,
    isFormatValid
} from 'c/envelopeFormSchema';

/**
 * envelopeFieldControl — V2 dynamic-form field renderer. Renders a single metadata-driven field with
 * the V2 control set: text/number/date/boolean inputs, textarea, multi-select checkbox group or
 * dual listbox, and single-select picklists rendered as either a radio group (few options) or the
 * searchable combobox (many options). Emits `valuechange` with `{ field, value }`. The V2 counterpart of
 * `envelopeDynamicFormField`, which stays on the base `lightning-combobox` for the v1 forms.
 */

// Fallback control choice when a field carries no explicit `inputType` hint (e.g. Apex emits
// 'combobox' for picklists): at most this many options render as a radio group, larger lists use the
// searchable dropdown. An explicit `inputType` of 'radio' or 'select' always wins over this heuristic.
const RADIO_MAX_OPTIONS = 4;

// Radio groups with at most this many options lay their radios out in a single row; more stack.
const INLINE_RADIO_MAX_OPTIONS = 3;

export default class EnvelopeFieldControl extends LightningElement {
    @api field;

    // When true, the control hides its built-in label (parent renders the label separately).
    _hideLabel = false;

    @api
    get hideLabel() {
        return this._hideLabel;
    }
    set hideLabel(value) {
        this._hideLabel = value === true || value === 'true' || value === '';
    }

    // When true, value typography aligns right for inline record-detail rows.
    _inlineLayout = false;

    @api
    get inlineLayout() {
        return this._inlineLayout;
    }
    set inlineLayout(value) {
        this._inlineLayout = value === true || value === 'true' || value === '';
    }

    // The value this control last emitted, so a re-render driven by the user's own typing can be
    // told apart from a value arriving from the form draft.
    _editedValue;

    // A keystroke a buffered control is still holding (see _buffersEdits), with the idle timer that
    // commits it if the blur never comes. The flag is kept separately so an empty value can be held.
    _pendingValue;
    _hasPendingValue = false;
    _commitTimer = null;

    connectedCallback() {
        if (this.isUnsupported) {
            console.warn(
                `envelopeFieldControl: no control for ${this.unsupportedMessage}; rendering it read-only.`
            );
        }
    }

    disconnectedCallback() {
        this._clearCommitTimer();
    }

    renderedCallback() {
        this._reportRestoredValue();
    }

    // Label shown on the control. Required fields are the unmarked default (the required asterisk is
    // hidden form-wide); optional fields are called out with a trailing "(optional)". Checkboxes are
    // skipped — a checkbox is inherently optional-looking, so the suffix only adds noise there.
    get displayLabel() {
        const label = this.field?.label || '';
        return this.field?.required || this.isBoolean ? label : `${label} (optional)`;
    }

    // A "Key Point" field (Key_Decision__c) is highlighted: its label moves to a header row with a
    // "Key Point" badge, and the control below hides its own label (the header is the label).
    get isKeyPoint() {
        return !!this.field?.keyDecision;
    }

    get controlVariant() {
        if (this.isKeyPoint || this.hideLabel) {
            return 'label-hidden';
        }
        return 'standard';
    }

    // Label forwarded to child controls for accessibility when the visible label is rendered externally.
    get controlLabel() {
        return this.displayLabel;
    }

    get showKeyPointHeader() {
        return this.isKeyPoint && !this.hideLabel;
    }

    // "Updated" marker under the control: this field holds something other than the value the
    // request it belongs to started from. Only set on an interview that was given a baseline to
    // compare against (see envelopeFormSchema.markUpdatedFields).
    get isUpdated() {
        return this.field?.updated === true;
    }

    // A radio group has no native way to deselect, so a "Clear" link is offered to reset an accidental
    // pick. It shows only once the group holds a value (nothing to clear otherwise) and hides again
    // after clearing.
    get canClear() {
        return this.isRadioPicklist && !!this.field?.value;
    }

    // Non-Key-Point radios render their label in a row of our own (so the Clear link can sit beside it)
    // and the control's built-in label is hidden. Key Point radios already have a header row, so they
    // reuse it instead of adding a second one.
    get showRadioLabelRow() {
        return this.isRadioPicklist && !this.isKeyPoint && !this.hideLabel;
    }

    // TYPE HANDLERS
    get isText() {
        return ['STRING', 'EMAIL', 'PHONE', 'URL'].includes(this.field.type);
    }

    get isTextarea() {
        return this.field.type === 'TEXTAREA';
    }

    get isNumber() {
        return ['DOUBLE', 'INTEGER', 'CURRENCY', 'PERCENT'].includes(this.field.type);
    }

    get isBoolean() {
        return this.field.type === 'BOOLEAN';
    }

    get isDate() {
        return this.field.type === 'DATE';
    }

    get isDateTime() {
        return this.field.type === 'DATETIME';
    }

    get isPicklist() {
        return this.field.type === 'PICKLIST';
    }

    // Render as a radio group when the design calls for it. An explicit `inputType` hint wins; without
    // one, fall back to the option-count heuristic (few options → radio for at-a-glance selection).
    get isRadioPicklist() {
        if (!this.isPicklist || this.inlineLayout) {
            return false;
        }
        if (this.field.inputType === 'radio') {
            return true;
        }
        if (this.field.inputType === 'select') {
            return false;
        }
        return (this.field.picklistOptions || []).length <= RADIO_MAX_OPTIONS;
    }

    // Any single-select picklist not rendered as a radio group falls back to the searchable dropdown.
    get isSelectPicklist() {
        return this.isPicklist && !this.isRadioPicklist;
    }

    // Lay a short radio group out horizontally; the inline modifier is themed from the shared sheet.
    get radioGroupClass() {
        return (this.field.picklistOptions || []).length <= INLINE_RADIO_MAX_OPTIONS
            ? 'field-radio field-radio_inline'
            : 'field-radio';
    }

    // Checkbox list for a multipicklist — the control Apex asks for on every MULTIPICKLIST field
    // (inputType 'checkboxGroup'), so this is what a multi-select renders as unless it is overridden.
    get isMultiPicklist() {
        return this.field.type === 'MULTIPICKLIST' && this.field.inputType === 'checkboxGroup';
    }

    // Dueling lists for a multipicklist, reached only through a 'Dual Listbox' Field Type Override
    // (see isMultiPicklist for the default). The cap on how many options may be chosen comes from the
    // field's maxSelections (unset → uncapped).
    get isDualListbox() {
        return this.field.type === 'MULTIPICKLIST' && this.field.inputType !== 'checkboxGroup';
    }

    get maxSelections() {
        return this.field.maxSelections || undefined;
    }

    get isInput() {
        return this.isText || this.isNumber || this.isBoolean || this.isDate || this.isDateTime;
    }

    // Add-record rows are synthetic controls that spawn a nested record rather than edit a value;
    // their UI is a separate concern, so they are not treated as an unhandled type here.
    get isAddRecord() {
        return this.field?.type === 'ADD_RECORD' || !!this.field?.addRecord;
    }

    // A field whose type matches no control above would otherwise render as nothing at all, hiding a
    // configured field with no clue why. Surface it instead: a disabled control that names the type.
    // Lookups land here until an option source is supplied for them (see
    // envelopeFormSchema.applyLookupOptions).
    get isUnsupported() {
        return (
            !!this.field &&
            !this.isAddRecord &&
            !this.isInput &&
            !this.isTextarea &&
            !this.isPicklist &&
            !this.isMultiPicklist &&
            !this.isDualListbox
        );
    }

    get unsupportedMessage() {
        return `Unsupported field type: ${this.field?.type} (${this.field?.apiName})`;
    }

    get inputType() {
        if (this.isText) {
            // Map field types to input types
            if (this.field.type === 'EMAIL') return 'email';
            if (this.field.type === 'PHONE') return 'tel';
            return 'text';
        }
        if (this.isNumber) return 'number';
        if (this.isBoolean) return 'checkbox';
        if (this.isDate) return 'date';
        if (this.isDateTime) return 'datetime';
        return 'text';
    }

    get placeholder() {
        if (this.isDate) {
            return 'Select a date';
        }
        if (this.isDateTime) {
            return 'Select a date & time';
        }
        if (this.isText || this.isNumber || this.isTextarea) {
            return `Enter ${this._humanizeLabel(this.field?.label)}`;
        }
        return undefined;
    }

    // VALIDATION ATTRIBUTES — sourced from the field's describe metadata so the base components enforce
    // the same constraints as the record. Bound only where they apply; undefined otherwise (no-op).

    // Character cap for text and textarea inputs; only meaningful when the field has a real length.
    get maxLength() {
        return (this.isText || this.isTextarea) && this.field.maxLength > 0
            ? this.field.maxLength
            : undefined;
    }

    // Numeric step from the field's decimal scale: scale 2 → '0.01', scale 0 → '1'.
    get numberStep() {
        const scale = this.field.scale;
        return scale > 0 ? `0.${'0'.repeat(scale - 1)}1` : '1';
    }

    // Number formatting: currency fields render formatted. Percent is intentionally excluded —
    // lightning-input's percent formatter treats 1 as 100%, which mismatches how Salesforce stores
    // PERCENT values (whole numbers), so percent fields render as plain numbers.
    get numberFormatter() {
        return this.field.type === 'CURRENCY' ? 'currency' : undefined;
    }

    // Format mask from Envelope_Field__mdt.Pattern__c, bound only on text-family inputs
    // (text/email/tel/url). Radio, dual-listbox, checkbox-group, combobox, number and date controls
    // never receive a pattern, so a Field Type Override can never collide with a format rule.
    get pattern() {
        return this.isText && this.field.pattern ? this.field.pattern : undefined;
    }

    get patternMismatchMessage() {
        return this.pattern
            ? this.field.patternError || 'Please match the requested format.'
            : undefined;
    }

    // Bounds from Min__c/Max__c for number and date inputs only (Apex resolves the TODAY token to an
    // ISO date before it reaches the client).
    get minValue() {
        return (this.isNumber || this.isDate) && this.field.minValue
            ? this.field.minValue
            : undefined;
    }

    get maxValue() {
        return (this.isNumber || this.isDate) && this.field.maxValue
            ? this.field.maxValue
            : undefined;
    }

    // Pattern_Error__c doubles as the out-of-range message for bounded number/date fields.
    get rangeMessage() {
        return this.minValue || this.maxValue ? this.field.patternError || undefined : undefined;
    }

    // HANDLERS
    handleChange(event) {
        let value = this._normalizeValue(event);

        // Named formats hard-mask as the user types: strip disallowed characters, auto-insert
        // separators, and write the result back so the visible input updates mid-keystroke.
        if (this.field?.format && this.isText) {
            const masked = applyInputMask(this.field.format, value, this._currentValue);
            if (masked !== value) {
                event.target.value = masked;
            }
            value = masked;
        }

        if (this._buffersEdits) {
            this._holdEdit(value);
            return;
        }
        this._emitChange(value);
    }

    // Commit whatever the control is still buffering, then show the field's validation message the
    // moment the user leaves it (a mask can't prevent an incomplete value, e.g. a 3-digit zip),
    // instead of waiting for the submit gate.
    handleBlur() {
        this.flushPendingEdits();
        this.reportValidity();
    }

    // Reset a radio group to no selection. Emits the same `valuechange` an ordinary edit would, with the
    // empty value for a single-select picklist, so the draft, autosave, visibility rules and missing-input
    // count all update through the existing path.
    handleClear() {
        this._emitChange('');
    }

    /**
     * Commit a keystroke this control is still holding (see _buffersEdits), so a save or a validity
     * sweep can never read a draft that is a character behind what the user typed. Safe to call at any
     * time and a no-op when nothing is buffered.
     */
    @api
    flushPendingEdits() {
        this._clearCommitTimer();
        if (!this._hasPendingValue) {
            return;
        }
        const value = this._pendingValue;
        this._hasPendingValue = false;
        this._pendingValue = undefined;
        this._emitChange(value);
    }

    /**
     * Put the rendered control back on the value the draft holds, discarding an edit the page declined
     * to apply — a Key Point change the user backed out of. The draft never changed, so nothing
     * re-renders on its own and the control would otherwise keep showing the uncommitted answer.
     */
    @api
    resetValue() {
        this._clearCommitTimer();
        this._hasPendingValue = false;
        this._pendingValue = undefined;
        // Realign the echo bookkeeping too, so _reportRestoredValue is not left comparing against a
        // value the user has backed out of.
        this._editedValue = this.field?.value;
        const control = this._renderedControl();
        if (!control) {
            return;
        }
        if (control.type === 'checkbox') {
            control.checked = !!this.field?.value;
            return;
        }
        control.value = this.field?.value;
    }

    /**
     * Public method to report validity of the field.
     * Can be called from parent component.
     */
    @api
    reportValidity() {
        const inputElement = this._renderedControl();
        if (inputElement && typeof inputElement.reportValidity === 'function') {
            return inputElement.reportValidity();
        }
        return true;
    }

    /**
     * Public method to check validity of the field.
     * Can be called from parent component.
     */
    @api
    checkValidity() {
        const inputElement = this._renderedControl();
        if (inputElement && typeof inputElement.checkValidity === 'function') {
            return inputElement.checkValidity();
        }
        return true;
    }

    // Whichever control this field's type rendered, whatever it is — the single element that owns the
    // displayed value and the validity API.
    _renderedControl() {
        return this.template.querySelector(
            'lightning-input, lightning-textarea, lightning-checkbox-group, lightning-dual-listbox, lightning-radio-group, c-envelope-searchable-combobox'
        );
    }

    // Read the new value off a control's change event. The shape differs by control, so each case is
    // resolved here rather than at the call site.
    _normalizeValue(event) {
        const target = event.target;

        if (event.detail && Array.isArray(event.detail.value)) {
            // lightning-checkbox-group (multi-select): detail.value is the selected array.
            return event.detail.value;
        }
        if (target.type === 'checkbox') {
            return target.checked;
        }
        if (event.detail && event.detail.value !== undefined) {
            // lightning-radio-group / c-envelope-searchable-combobox re-target across their shadow
            // boundary, so target.value reads the stale value; the new value is carried in detail.
            return event.detail.value;
        }
        return target.value;
    }

    // Whether this control holds keystrokes back and commits them on blur (or after a short idle
    // window) instead of reporting every character. Only a text-family Key Point does: an edit to a
    // Key Point can rebuild the questions below it and raise the change confirmation, which belongs to
    // the answer, not to each character of it. Every other control reports immediately.
    get _buffersEdits() {
        return this.isKeyPoint && (this.isText || this.isNumber || this.isTextarea);
    }

    // The value the user is currently looking at: the buffered keystroke while one is held, else the
    // draft's. The input mask reads this as its previous value, which would otherwise lag a character
    // behind on a buffered control and break its separator-backspace handling.
    get _currentValue() {
        return this._hasPendingValue ? this._pendingValue : this.field?.value;
    }

    // Hold a keystroke, replacing whatever was held before, and restart the idle window.
    _holdEdit(value) {
        this._pendingValue = value;
        this._hasPendingValue = true;
        this._clearCommitTimer();
        // Fallback for a blur that never comes — the user navigates away, or a save reads the draft
        // while the field still has focus — so a held edit can't sit uncommitted indefinitely.
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._commitTimer = setTimeout(() => {
            this._commitTimer = null;
            this.flushPendingEdits();
        }, COMMIT_IDLE_MS);
    }

    _clearCommitTimer() {
        if (this._commitTimer) {
            clearTimeout(this._commitTimer);
            this._commitTimer = null;
        }
    }

    _emitChange(value) {
        // Recorded before the guard: _reportRestoredValue uses this to tell the user's own typing apart
        // from a value that arrived from the draft, and an echo is still "what this control reported".
        this._editedValue = value;
        // A control reporting the value it was already given is not an edit. This is the outermost of
        // the codebase's echo guards, and the one that matters for an untouched multi-select: every
        // rebuild of the form used to hand it a brand-new empty array, and passing that back up
        // replaced the whole draft and restarted the shell's save cycle for no reason.
        if (draftValuesEqual(this.field?.value, value)) {
            return;
        }
        this.dispatchEvent(
            new CustomEvent('valuechange', {
                detail: {
                    field: this.field.apiName,
                    value
                }
            })
        );
    }

    // A value restored from the form draft
    _reportRestoredValue() {
        if (this.field?.value === this._editedValue || isFormatValid(this.field)) {
            return;
        }
        this.reportValidity();
    }

    // Lowercases a label for placeholder text while preserving all-caps acronyms (SSN, EIN, IRA),
    // so "First Name" → "first name" but "EIN Number" → "EIN number".
    _humanizeLabel(label) {
        if (!label) {
            return '';
        }
        return label
            .split(' ')
            .map((word) => {
                const isAcronym = word === word.toUpperCase() && /[A-Z]/.test(word);
                return isAcronym ? word : word.toLowerCase();
            })
            .join(' ');
    }
}