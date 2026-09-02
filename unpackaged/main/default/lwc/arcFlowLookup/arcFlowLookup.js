/**
 * Flow-screen lookup for the ARC (LWR) site.
 *
 * Replaces flowruntime:lookup in the ARC-site flow copies: that component
 * renders in LWR but its inline TypeAhead returns nothing for these objects,
 * so every pick took a detour through "Show more results". This one shows the
 * top matches inline as you type (ArcFlowLookupController.search) and exposes
 * the same recordId output the flows already reference.
 */
import { LightningElement, api } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import search from '@salesforce/apex/ArcFlowLookupController.search';
import getRecordLabel from '@salesforce/apex/ArcFlowLookupController.getRecordLabel';

const SEARCH_DEBOUNCE_MS = 300;

export default class ArcFlowLookup extends LightningElement {
    @api label = '';
    @api objectApiName = '';
    @api placeholder = 'Search…';
    @api required = false;
    /** Default selection handed in by the flow (first id wins). */
    @api recordIds = [];

    @api recordId = null;
    @api recordName = '';

    searchTerm = '';
    results = [];
    isOpen = false;
    errorMessage = '';
    _debounce;
    _seeded = false;

    connectedCallback() {
        const seedId = (this.recordIds || [])[0];
        if (seedId && !this._seeded) {
            this._seeded = true;
            getRecordLabel({ objectApiName: this.objectApiName, recordId: seedId })
                .then((name) => {
                    if (name) {
                        this.applySelection(seedId, name);
                    }
                })
                .catch(() => {});
        }
    }

    get isRequired() {
        return this.required === true || this.required === 'true';
    }

    get hasSelection() {
        return Boolean(this.recordId);
    }

    get hasError() {
        return Boolean(this.errorMessage);
    }

    get comboClass() {
        return this.hasError
            ? 'arc-flow-lookup__input arc-flow-lookup__input--error'
            : 'arc-flow-lookup__input';
    }

    handleSearchChange(event) {
        const value = event.target.value || '';
        this.searchTerm = value;
        window.clearTimeout(this._debounce);
        if (!value.trim()) {
            this.results = [];
            this.isOpen = false;
            return;
        }
        this._debounce = window.setTimeout(() => this.runSearch(value.trim()), SEARCH_DEBOUNCE_MS);
    }

    async runSearch(term) {
        try {
            const results = await search({
                objectApiName: this.objectApiName,
                searchTerm: term
            });
            this.results = (results || []).map((row) => ({
                ...row,
                hasSublabel: Boolean(row.sublabel)
            }));
            this.isOpen = this.results.length > 0;
        } catch (error) {
            this.results = [];
            this.isOpen = false;
        }
    }

    handleSelect(event) {
        const { value, label } = event.currentTarget.dataset;
        this.applySelection(value, label);
    }

    handleClear() {
        this.recordId = null;
        this.recordName = '';
        this.searchTerm = '';
        this.results = [];
        this.isOpen = false;
        this.dispatchEvent(new FlowAttributeChangeEvent('recordId', null));
        this.dispatchEvent(new FlowAttributeChangeEvent('recordName', ''));
    }

    applySelection(recordId, recordName) {
        this.recordId = recordId;
        this.recordName = recordName;
        this.errorMessage = '';
        this.isOpen = false;
        this.results = [];
        this.dispatchEvent(new FlowAttributeChangeEvent('recordId', recordId));
        this.dispatchEvent(new FlowAttributeChangeEvent('recordName', recordName));
    }

    /** Flow runtime validation hook: a required lookup needs a selection. */
    @api
    validate() {
        if (this.isRequired && !this.recordId) {
            this.errorMessage = 'Complete this field.';
            return { isValid: false, errorMessage: 'Complete this field.' };
        }
        this.errorMessage = '';
        return { isValid: true };
    }
}