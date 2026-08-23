import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getDraftGuides from '@salesforce/apex/HelpGuideAdminController.getDraftGuides';
import getDraftGuide from '@salesforce/apex/HelpGuideAdminController.getDraftGuide';
import saveDraftGuide from '@salesforce/apex/HelpGuideAdminController.saveDraftGuide';
import deleteDraftGuide from '@salesforce/apex/HelpGuideAdminController.deleteDraftGuide';
import deleteDraftNode from '@salesforce/apex/HelpGuideAdminController.deleteDraftNode';
import publish from '@salesforce/apex/HelpGuideAdminController.publish';

/**
 * helpGuideBuilder — admin authoring app for Get Help guides. Lists draft
 * guides, edits a guide's nodes/options (via helpGuideNodeEditor), and publishes
 * to custom metadata via the Apex Metadata API (polling for the async result).
 */
export default class HelpGuideBuilder extends LightningElement {
    @track guides = [];
    @track selected; // GuideDraftDTO
    @track editingNode; // node DTO or {} for new
    showEditor = false;

    showGuideForm = false;
    formKey = '';
    formLabel = '';
    formActive = true;

    publishing = false;
    _pollCount = 0;

    connectedCallback() {
        this.loadGuides();
    }

    async loadGuides() {
        try {
            this.guides = await getDraftGuides();
        } catch (e) {
            this.toast('error', this.msg(e));
        }
    }

    async openGuide(event) {
        const id = event.currentTarget.dataset.id;
        await this.refreshSelected(id);
    }

    async refreshSelected(id) {
        try {
            this.selected = await getDraftGuide({ guideId: id });
            this.showEditor = false;
            this.editingNode = undefined;
        } catch (e) {
            this.toast('error', this.msg(e));
        }
    }

    get hasGuides() {
        return this.guides && this.guides.length > 0;
    }
    get nodes() {
        return this.selected ? this.selected.nodes : [];
    }
    get publishDisabled() {
        return this.publishing || !this.selected;
    }

    // ---- Guide create --------------------------------------------------------

    newGuide() {
        this.showGuideForm = true;
        this.formKey = '';
        this.formLabel = '';
        this.formActive = true;
    }
    handleFormKey(e) { this.formKey = e.target.value; }
    handleFormLabel(e) { this.formLabel = e.target.value; }
    handleFormActive(e) { this.formActive = e.target.checked; }

    async saveGuide() {
        try {
            const id = await saveDraftGuide({
                recordId: null, guideKey: this.formKey, label: this.formLabel,
                active: this.formActive, version: 1
            });
            this.showGuideForm = false;
            await this.loadGuides();
            await this.refreshSelected(id);
            this.toast('success', 'Guide created.');
        } catch (e) {
            this.toast('error', this.msg(e));
        }
    }
    cancelGuideForm() { this.showGuideForm = false; }

    async removeGuide() {
        if (!this.selected) {
            return;
        }
        try {
            await deleteDraftGuide({ guideId: this.selected.recordId });
            this.selected = undefined;
            await this.loadGuides();
            this.toast('success', 'Guide deleted.');
        } catch (e) {
            this.toast('error', this.msg(e));
        }
    }

    // ---- Node editing --------------------------------------------------------

    addNode() {
        this.editingNode = undefined;
        this.showEditor = true;
    }
    editNode(event) {
        const id = event.currentTarget.dataset.id;
        this.editingNode = this.nodes.find((n) => n.recordId === id);
        this.showEditor = true;
    }
    async removeNode(event) {
        const id = event.currentTarget.dataset.id;
        try {
            await deleteDraftNode({ nodeId: id });
            await this.refreshSelected(this.selected.recordId);
        } catch (e) {
            this.toast('error', this.msg(e));
        }
    }
    async handleEditorSaved() {
        this.showEditor = false;
        await this.refreshSelected(this.selected.recordId);
    }
    handleEditorCancel() {
        this.showEditor = false;
    }

    // ---- Publish (async, polled) --------------------------------------------

    async doPublish() {
        if (!this.selected) {
            return;
        }
        this.publishing = true;
        try {
            await publish({ guideId: this.selected.recordId });
            this._pollCount = 0;
            this.pollPublish();
        } catch (e) {
            this.publishing = false;
            this.toast('error', this.msg(e));
        }
    }

    pollPublish() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(async () => {
            this._pollCount++;
            try {
                const g = await getDraftGuide({ guideId: this.selected.recordId });
                this.selected = g;
                if (g.published) {
                    this.publishing = false;
                    this.toast('success', 'Guide published.');
                    return;
                }
                if (g.publishError) {
                    this.publishing = false;
                    this.toast('error', 'Publish failed: ' + g.publishError);
                    return;
                }
            } catch (e) {
                // keep polling
            }
            if (this._pollCount < 20) {
                this.pollPublish();
            } else {
                this.publishing = false;
                this.toast('warning', 'Still publishing — check back shortly.');
            }
        }, 3000);
    }

    msg(e) {
        return (e && e.body && e.body.message) || 'Something went wrong.';
    }
    toast(variant, message) {
        this.dispatchEvent(new ShowToastEvent({
            title: variant === 'error' ? 'Error' : (variant === 'warning' ? 'Heads up' : 'Success'),
            message, variant
        }));
    }
}