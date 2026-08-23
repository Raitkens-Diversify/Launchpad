import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import saveDraftNode from '@salesforce/apex/HelpGuideAdminController.saveDraftNode';
import saveDraftOption from '@salesforce/apex/HelpGuideAdminController.saveDraftOption';
import deleteDraftOption from '@salesforce/apex/HelpGuideAdminController.deleteDraftOption';

const TYPE_OPTIONS = [
    { label: 'Go to another question (node)', value: 'node' },
    { label: 'Open a resource category', value: 'category' },
    { label: 'Open a Knowledge article', value: 'article' },
    { label: 'Open a resource', value: 'resource' },
    { label: 'Create a case / contact us', value: 'case' }
];

/**
 * helpGuideNodeEditor — edits one draft node (question, root flag) and its
 * options, saving to the draft objects via HelpGuideAdminController. Emits
 * `saved` when the builder should refresh, `cancel` to close.
 */
export default class HelpGuideNodeEditor extends LightningElement {
    @api guideId;

    _node;
    nodeId;
    question = '';
    isRoot = false;
    @track options = [];
    removedOptionIds = [];
    _seq = 0;
    saving = false;

    typeOptions = TYPE_OPTIONS;

    @api
    get node() {
        return this._node;
    }
    set node(value) {
        this._node = value;
        if (value) {
            this.nodeId = value.recordId;
            this.question = value.question || '';
            this.isRoot = !!value.isRoot;
            this.options = (value.options || []).map((o) => ({
                _key: `k${this._seq++}`,
                recordId: o.recordId,
                label: o.label,
                targetType: o.targetType || 'node',
                targetValue: o.targetValue
            }));
        } else {
            this.nodeId = undefined;
            this.question = '';
            this.isRoot = false;
            this.options = [];
        }
    }

    get title() {
        return this.nodeId ? 'Edit question' : 'New question';
    }

    handleQuestion(event) {
        this.question = event.target.value;
    }
    handleRoot(event) {
        this.isRoot = event.target.checked;
    }
    handleOptionChange(event) {
        const key = event.currentTarget.dataset.key;
        const field = event.currentTarget.dataset.field;
        const value = event.detail ? event.detail.value : event.target.value;
        this.options = this.options.map((o) =>
            o._key === key ? { ...o, [field]: value } : o
        );
    }
    addOption() {
        this.options = [
            ...this.options,
            { _key: `k${this._seq++}`, recordId: null, label: '', targetType: 'node', targetValue: '' }
        ];
    }
    removeOption(event) {
        const key = event.currentTarget.dataset.key;
        const removed = this.options.find((o) => o._key === key);
        if (removed && removed.recordId) {
            this.removedOptionIds = [...this.removedOptionIds, removed.recordId];
        }
        this.options = this.options.filter((o) => o._key !== key);
    }

    async handleSave() {
        if (!this.question || !this.question.trim()) {
            this.toast('error', 'A question is required.');
            return;
        }
        this.saving = true;
        try {
            const nodeId = await saveDraftNode({
                recordId: this.nodeId,
                guideId: this.guideId,
                nodeKey: this._node ? this._node.nodeKey : null,
                question: this.question,
                nodeOrder: this._node ? this._node.nodeOrder : null,
                isRoot: this.isRoot
            });

            for (const id of this.removedOptionIds) {
                await deleteDraftOption({ optionId: id });
            }
            let order = 1;
            for (const o of this.options) {
                await saveDraftOption({
                    recordId: o.recordId,
                    nodeId,
                    optionOrder: order++,
                    label: o.label,
                    targetType: o.targetType,
                    targetValue: o.targetValue
                });
            }
            this.toast('success', 'Question saved.');
            this.dispatchEvent(new CustomEvent('saved'));
        } catch (e) {
            this.toast('error', this.msg(e));
        } finally {
            this.saving = false;
        }
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('cancel'));
    }

    msg(e) {
        return (e && e.body && e.body.message) || 'Could not save.';
    }
    toast(variant, message) {
        this.dispatchEvent(new ShowToastEvent({
            title: variant === 'error' ? 'Error' : 'Success', message, variant
        }));
    }
}