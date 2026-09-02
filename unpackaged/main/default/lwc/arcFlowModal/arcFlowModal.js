/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-13
 */
import { LightningElement, api } from 'lwc';

/*
 * A flow that reaches its end is done with the dialog, and a flow that faults
 * is not: the fault message is rendered by lightning-flow itself, so the
 * interview has to stay mounted for anyone to read it. The two cases are
 * therefore kept apart rather than lumped into one "finished" set.
 */
const COMPLETED_STATUSES = new Set(['FINISHED', 'FINISHED_SCREEN']);
const ERROR_STATUSES = new Set(['ERROR']);

const inferFlowVariableType = (value) => {
    if (typeof value === 'number') {
        return 'Number';
    }
    if (typeof value === 'boolean') {
        return 'Boolean';
    }
    return 'String';
};

const normalizeFlowInputVariables = (params) => {
    if (!params) {
        return [];
    }

    if (Array.isArray(params)) {
        return params.map((entry) => ({
            name: entry.name,
            type: entry.type || inferFlowVariableType(entry.value),
            value: entry.value
        }));
    }

    if (typeof params === 'object') {
        return Object.entries(params).map(([name, value]) => ({
            name,
            type: inferFlowVariableType(value),
            value
        }));
    }

    return [];
};

export default class ArcFlowModal extends LightningElement {
    @api title = '';
    @api subtitle = '';
    @api flowName = '';
    @api params = [];
    /** "" (default width) or "large" — the launchpad-modal proportions the
     *  Log a Check dialog uses. */
    @api size = '';

    _isOpen = false;
    /** True once the flow faulted, which is the only state that needs a Close. */
    isFlowFinished = false;
    /** True once the flow ran to the end; unmounts the interview, see showFlow. */
    _completed = false;
    flowKey = 0;
    lastFlowStatus = null;

    @api
    get isOpen() {
        return this._isOpen;
    }

    set isOpen(value) {
        this._isOpen = Boolean(value);
    }

    @api
    open(options = {}) {
        if (options.flowName) {
            this.flowName = options.flowName;
        }
        if (options.title) {
            this.title = options.title;
        }
        if (options.subtitle !== undefined) {
            this.subtitle = options.subtitle;
        }
        if (options.params !== undefined) {
            this.params = options.params;
        }
        if (options.size !== undefined) {
            this.size = options.size;
        }

        this.isFlowFinished = false;
        this._completed = false;
        this.lastFlowStatus = null;
        this.flowKey += 1;
        this._isOpen = true;
    }

    @api
    close() {
        this._closeModal();
    }

    get hasSubtitle() {
        return Boolean(this.subtitle);
    }

    get flowInputVariables() {
        return normalizeFlowInputVariables(this.params);
    }

    /*
     * Unmounted the moment the flow completes. lightning-flow restarts its
     * interview when one finishes, so leaving it mounted put a blank copy of
     * the first screen back on the dialog underneath a Close button.
     */
    get showFlow() {
        return this._isOpen && Boolean(this.flowName) && !this._completed;
    }

    get dialogLabel() {
        return this.title || 'Flow';
    }

    /**
     * Always false. Guards the never-rendered block that statically names the
     * flow screen components (arcFlowLookup, etc.) so the LWR site compiler
     * bundles them into the published build — a flow's extensionName reference
     * is invisible to it, so without this they load in preview but 404 on the
     * published site.
     */
    get bundleFlowScreens() {
        return false;
    }

    get panelClass() {
        return this.size === 'large'
            ? 'arc-flow-modal__panel arc-flow-modal__panel--large'
            : 'arc-flow-modal__panel';
    }

    get overlayClass() {
        return this.size === 'large'
            ? 'arc-flow-modal arc-flow-modal--large'
            : 'arc-flow-modal';
    }

    handleFlowStatusChange(event) {
        const { status, outputVariables } = event.detail || {};
        this.lastFlowStatus = status;

        this.dispatchEvent(
            new CustomEvent('flowstatuschange', {
                detail: {
                    status,
                    outputVariables
                },
                bubbles: true,
                composed: true
            })
        );

        if (COMPLETED_STATUSES.has(status)) {
            this._completed = true;

            // The parent refreshes off this; without it a task created here did
            // not appear in the case's lists until the page was reloaded.
            this.dispatchEvent(
                new CustomEvent('flowfinished', {
                    detail: { status, outputVariables },
                    bubbles: true,
                    composed: true
                })
            );

            this._closeModal('finished');
            return;
        }

        if (ERROR_STATUSES.has(status)) {
            this.isFlowFinished = true;
        }
    }

    handleCancel() {
        this._closeModal('cancel');
    }

    handleClose() {
        this._closeModal('close');
    }

    handleBackdropClick() {
        if (this.isFlowFinished) {
            this.handleClose();
            return;
        }

        this.handleCancel();
    }

    _closeModal(reason = 'close') {
        this._isOpen = false;
        this.isFlowFinished = false;
        this._completed = false;
        this.lastFlowStatus = null;

        this.dispatchEvent(
            new CustomEvent('close', {
                detail: { reason },
                bubbles: true,
                composed: true
            })
        );
    }
}