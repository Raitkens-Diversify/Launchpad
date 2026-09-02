/**
 * ARC (LWR) replacement for aura/cmp_FlowCreateMultiple as the Advertising
 * Review flows use it: an inline editor for cost line items — rows of
 * Name of Party + Amount — saved against the running flow interview
 * (Flow_Interview_ID__c = $Flow.InterviewGuid) so the flow gathers them after
 * the screen, exactly like the Aura original. Property names match the Aura
 * component so the ARC flow copies only swap the extension name.
 */
import { LightningElement, api, track } from 'lwc';
import getLineItems from '@salesforce/apex/ArcCostLineItemController.getLineItems';
import saveLineItem from '@salesforce/apex/ArcCostLineItemController.saveLineItem';
import deleteLineItem from '@salesforce/apex/ArcCostLineItemController.deleteLineItem';

const SAVE_DEBOUNCE_MS = 800;

export default class ArcFlowCostLineItems extends LightningElement {
    @api sObjectName = '';
    @api sObjectFields = '';
    @api recordTypeName = '';
    @api recordId;
    @api parentRecordId = '';
    @api parentLookupFieldName = '';
    @api MaximumNumberofRecords = 10;
    @api LinestoShow = 4;

    @track rows = [];
    errorMessage = '';
    _rowKey = 0;
    _saveTimers = {};

    async connectedCallback() {
        try {
            const existing = await getLineItems({
                objectApiName: this.sObjectName,
                parentId: this.parentRecordId
            });
            this.rows = (existing || []).map((row) => this.makeRow(row));
        } catch (error) {
            this.rows = [];
        }
        const linesToShow = Math.max(1, parseInt(this.LinestoShow, 10) || 1);
        while (this.rows.length < linesToShow) {
            this.rows = [...this.rows, this.makeRow()];
        }
    }

    makeRow(saved) {
        this._rowKey += 1;
        return {
            key: `row-${this._rowKey}`,
            recordId: saved?.recordId || null,
            nameOfParty: saved?.nameOfParty || '',
            amount: saved?.amount ?? null,
            saving: false
        };
    }

    get hasError() {
        return Boolean(this.errorMessage);
    }

    get canAddRow() {
        const max = parseInt(this.MaximumNumberofRecords, 10) || 10;
        return this.rows.length < max;
    }

    get addDisabled() {
        return !this.canAddRow;
    }

    handleFieldChange(event) {
        const { key } = event.currentTarget.dataset;
        const field = event.currentTarget.name;
        const value = event.target.value;
        this.rows = this.rows.map((row) =>
            row.key === key ? { ...row, [field]: value } : row
        );
        // Autosave, the way the Aura grid persisted rows as they were typed.
        window.clearTimeout(this._saveTimers[key]);
        this._saveTimers[key] = window.setTimeout(() => this.saveRow(key), SAVE_DEBOUNCE_MS);
    }

    async saveRow(key) {
        const row = this.rows.find((entry) => entry.key === key);
        if (!row) {
            return;
        }
        const hasContent = (row.nameOfParty || '').trim() || row.amount;
        if (!hasContent) {
            return;
        }
        try {
            const recordId = await saveLineItem({
                objectApiName: this.sObjectName,
                parentId: this.parentRecordId,
                recordId: row.recordId,
                nameOfParty: row.nameOfParty,
                amount: row.amount === '' || row.amount === null ? null : row.amount
            });
            this.errorMessage = '';
            this.rows = this.rows.map((entry) =>
                entry.key === key ? { ...entry, recordId } : entry
            );
        } catch (error) {
            this.errorMessage =
                error?.body?.message || 'Could not save this line item.';
        }
    }

    handleAddRow() {
        // The Aura footer button: persist what is typed, then a fresh row.
        this.rows.forEach((row) => this.saveRow(row.key));
        if (this.canAddRow) {
            this.rows = [...this.rows, this.makeRow()];
        }
    }

    async handleRemoveRow(event) {
        const { key } = event.currentTarget.dataset;
        const row = this.rows.find((entry) => entry.key === key);
        if (!row) {
            return;
        }
        window.clearTimeout(this._saveTimers[key]);
        if (row.recordId) {
            try {
                await deleteLineItem({
                    objectApiName: this.sObjectName,
                    recordId: row.recordId
                });
            } catch (error) {
                this.errorMessage =
                    error?.body?.message || 'Could not remove this line item.';
                return;
            }
        }
        this.rows = this.rows.filter((entry) => entry.key !== key);
        if (!this.rows.length) {
            this.rows = [this.makeRow()];
        }
    }
}