import { LightningElement, api } from 'lwc';
import { RefreshEvent } from 'lightning/refresh';

export default class refreshFlowAction extends LightningElement {

    connectedCallback() {
        console.log('Hello from refresh Flow Action');
    }

    @api invoke() {
        // console.log('Hello from RefreshFlowAction');
        // This broadcasts the refresh signal to the entire record page
        this.dispatchEvent(new RefreshEvent());
    }
}