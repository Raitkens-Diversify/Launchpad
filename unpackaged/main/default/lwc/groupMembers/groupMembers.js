import { LightningElement, api, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getGroupMembers from '@salesforce/apex/GroupMembersController.getGroupMembers';

export default class GroupMembers extends NavigationMixin(LightningElement) {
    @api recordId; // Account recordId passed automatically from Lightning Page
    @track members = [];
    isLoading = true;

    @wire(getGroupMembers, { accountId: '$recordId' })
    wiredMembers({ error, data }) {
        this.isLoading = false;
        if (data) {
            this.members = data;
        } else if (error) {
            console.error('Error fetching group members:', error);
            this.members = [];
        }
    }

    get memberCount() {
        return this.members ? this.members.length : 0;
    }

    navigateToRecord(event) {
        const accountId = event.target.dataset.id;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: accountId,
                actionName: 'view'
            }
        });
    }  
}