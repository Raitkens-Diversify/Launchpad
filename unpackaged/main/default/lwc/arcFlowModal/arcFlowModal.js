/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-13
 */
import { LightningElement, api } from 'lwc';
import { loadStyle } from 'lightning/platformResourceLoader';
import diversifyStyles from '@salesforce/resourceUrl/diversifyStyles';

const FINISHED_STATUSES = new Set(['FINISHED', 'FINISHED_SCREEN', 'ERROR']);

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

    _isOpen = false;
    _stylesLoaded = false;
    isFlowFinished = false;
    flowKey = 0;
    lastFlowStatus = null;

    connectedCallback() {
        if (this._stylesLoaded) {
            return;
        }

        this._stylesLoaded = true;
        loadStyle(this, diversifyStyles).catch(() => {
            this._stylesLoaded = false;
        });
    }

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

        this.isFlowFinished = false;
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

    get showFlow() {
        return this._isOpen && Boolean(this.flowName);
    }

    get dialogLabel() {
        return this.title || 'Flow';
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

        if (FINISHED_STATUSES.has(status)) {
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