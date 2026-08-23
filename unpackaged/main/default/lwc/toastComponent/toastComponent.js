import { api, LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
export default class ToastComponent extends LightningElement {

    @api title;
    /* Title of the toast */
    @api message;
    /*
        Message of the toast. If you wanted to display the Clickable url in the toast then the message format will be
        'Record {0} created! See it {1}!'
        where {0} is the record Name and {1} is the url to the record.
        You also need to provide the recordName variable in the template so that the template can be parsed.
        For Example the message is Record {0} created! See it {1}!
        And the recordName is John Doe & the url is https://www.google.com & actionLabel is Here
        then message in the toast will look like Record John Doe created! See it Here!
     */
    @api variant;
    /* Variant of the toast. Should be one of the values, info, success, warning, error */
    @api iconName;
    /* Icon name of the toast. We are not using this variable */
    @api delay;
    /* Delay of the toast in milliseconds */
    @api recordName;
    /* Name of the record which will be displayed over the toast message */
    @api url;
    /* URL of the record where user will be redirected when user clicks on the url */
    @api actionLabel;
    /* Label of the clickable button. For Example Click Here, or Here */

    connectedCallback(){
        this.showToastMessage();
    }

    showToastMessage = () => {
        let toastMessage = {
            title: this.title,
            message: this.message,
            variant: this.variant?this.variant:'info'
        };
        if(this.recordName && this.url){
            toastMessage.messageData = [
                this.recordName,
                {
                    url: this.url,
                    label: this.actionLabel,
                },
            ]
        }
        if(this.delay){
            setTimeout(() => {
                this.fireToastMessage(toastMessage);
            } , this.delay);
        }else{
            this.fireToastMessage(toastMessage);
        }
    }

    fireToastMessage = (toastMessage) => {
        window.console.log('Toast Message: ', toastMessage);
        this.dispatchEvent(new ShowToastEvent(toastMessage) );
    }
}