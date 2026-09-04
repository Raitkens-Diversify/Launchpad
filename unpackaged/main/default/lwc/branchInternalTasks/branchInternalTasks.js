import { LightningElement, api, track, wire } from 'lwc';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import { EnclosingTabId, openSubtab } from 'lightning/platformWorkspaceApi';
import getTasks from '@salesforce/apex/BranchInternalTaskController.getTasks';

export default class BranchInternalTasks extends LightningElement {

    @api recordId;

    @track tasks = [];

    @wire(EnclosingTabId)
    enclosingTabId;

    _empSubscription = null;
    _channelName = '/event/Refresh_Detail__e';

    connectedCallback() {
        this._loadTasks();
        this._subscribeToEmpApi();
    }

    disconnectedCallback() {
        this._unsubscribeFromEmpApi();
    }

    get hasTasks() {
        return this.tasks && this.tasks.length > 0;
    }

    _loadTasks() {
        getTasks({ recordId: this.recordId })
            .then(result => {
                this.tasks = result;
            })
            .catch(error => {
                console.error('BranchInternalTask - error fetching tasks:', error);
            });
    }

    _subscribeToEmpApi() {
        subscribe(this._channelName, -1, message => {
            console.log('BranchInternalTask - platform event received:', message);
            this._loadTasks();
        })
        .then(subscription => {
            this._empSubscription = subscription;
            console.log('BranchInternalTask - subscribed to channel:', subscription.channel);
        });

        onError(error => {
            console.error('BranchInternalTask - EMP API error:', JSON.stringify(error));
        });
    }

    _unsubscribeFromEmpApi() {
        if (this._empSubscription) {
            unsubscribe(this._empSubscription, response => {
                console.log('BranchInternalTask - unsubscribed from EMP API:', response);
            });
            this._empSubscription = null;
        }
    }

    navigateToTask(event) {
        const taskId  = event.currentTarget.dataset.taskid;
        const taskSub = event.currentTarget.dataset.tasksub;

        const parentTabId = this.enclosingTabId?.data;

        if (parentTabId) {
            // Console app – open as a sub-tab
            openSubtab(this, {
                parentTabId,
                recordId : taskId,
                focus    : true,
                label    : taskSub,
            }).catch(error => {
                console.error('BranchInternalTask - error opening subtab:', error);
            });
        } else {
            // Experience Cloud / standard nav – navigate to the record URL
            window.location.href = `/${taskId}`;
        }
    }
}