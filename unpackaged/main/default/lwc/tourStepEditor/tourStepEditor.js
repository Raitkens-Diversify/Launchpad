import { LightningElement, api } from 'lwc';

const CONVENTION = /^\[data-tour-id="[^"]+"\]$/;

/**
 * Per-step form for the Tour Builder. Purely local editing state — the parent
 * owns persistence and hears about intent via events:
 *   stepchange { step }    Save clicked, payload is the edited step DTO
 *   stepdelete { recordId }
 */
export default class TourStepEditor extends LightningElement {
    title = '';
    targetSelector = '';
    body = '';
    placement = 'auto';
    advanceOn = 'button';
    selectorInvalid = false;
    _step = null;
    _confirmingDelete = false;

    @api
    get step() {
        return this._step;
    }
    set step(value) {
        this._step = value;
        this._confirmingDelete = false;
        this.title = value ? value.title || '' : '';
        this.targetSelector = value ? value.targetSelector || '' : '';
        this.body = value ? value.body || '' : '';
        this.placement = value && value.placement ? value.placement : 'auto';
        this.advanceOn = value && value.advanceOn ? value.advanceOn : 'button';
        this.selectorInvalid = false;
    }

    get placementOptions() {
        return ['auto', 'top', 'bottom', 'left', 'right'].map((v) => ({ label: v, value: v }));
    }

    get advanceOptions() {
        return [
            { label: 'button — Next button advances', value: 'button' },
            { label: 'click — clicking the target advances', value: 'click' },
            { label: 'none — informational only', value: 'none' }
        ];
    }

    get richFormats() {
        return ['bold', 'italic', 'link', 'list', 'clean'];
    }

    get canDelete() {
        return Boolean(this._step && this._step.recordId);
    }

    get deleteLabel() {
        return this._confirmingDelete ? 'Confirm delete' : 'Delete step';
    }

    get saveDisabled() {
        return !this.title.trim() || !this.targetSelector.trim() || this.selectorInvalid;
    }

    get selectorOffConvention() {
        const sel = this.targetSelector.trim();
        return Boolean(sel) && !this.selectorInvalid && !CONVENTION.test(sel);
    }

    handleTitle(event) {
        this.title = event.detail.value;
    }

    handleSelector(event) {
        this.targetSelector = event.detail.value;
        const sel = this.targetSelector.trim();
        if (!sel) {
            this.selectorInvalid = false;
            return;
        }
        try {
            document.createDocumentFragment().querySelector(sel);
            this.selectorInvalid = false;
        } catch (e) {
            this.selectorInvalid = true;
        }
    }

    handleBody(event) {
        this.body = event.detail.value;
    }

    handlePlacement(event) {
        this.placement = event.detail.value;
    }

    handleAdvance(event) {
        this.advanceOn = event.detail.value;
    }

    handleSave() {
        if (this.saveDisabled) {
            return;
        }
        this.dispatchEvent(
            new CustomEvent('stepchange', {
                detail: {
                    step: {
                        recordId: this._step ? this._step.recordId : null,
                        stepOrder: this._step ? this._step.stepOrder : null,
                        title: this.title.trim(),
                        targetSelector: this.targetSelector.trim(),
                        body: this.body,
                        placement: this.placement,
                        advanceOn: this.advanceOn
                    }
                }
            })
        );
    }

    // Two-click confirm instead of a blocking dialog.
    handleDelete() {
        if (!this._confirmingDelete) {
            this._confirmingDelete = true;
            return;
        }
        this._confirmingDelete = false;
        this.dispatchEvent(
            new CustomEvent('stepdelete', { detail: { recordId: this._step.recordId } })
        );
    }
}