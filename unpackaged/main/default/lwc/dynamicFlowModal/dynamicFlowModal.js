import { LightningElement, api } from 'lwc';

export default class DynamicFlowModal extends LightningElement {

    // Configured from Experience Builder
    @api flowApiName;
    @api buttonLabel;
    @api recordId;

    isModalOpen = false;

    get flowInputVariables() {
        console.log('this.recordId'+this.recordId);
        return [
            {
                name: 'recordId',
                type: 'String',
                value: this.recordId
            }
        ];
    }
    handleOpenFlow() {
        this.isModalOpen = true;
    }

    handleClose() {
        this.isModalOpen = false;
    }

    handleFlowStatus(event) {
        debugger
        const status = event.detail.status;

        if (status === 'FINISHED' || status === 'FINISHED_SCREEN') {
            this.isModalOpen = false;
        }
    }
}