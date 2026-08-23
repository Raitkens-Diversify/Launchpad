import { LightningElement, api, track, wire } from 'lwc';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import { EnclosingTabId, openSubtab } from 'lightning/platformWorkspaceApi';
import getTasks from '@salesforce/apex/MainTrackTasksController.getTasks';

export default class MainTrackTasks extends LightningElement {
   
    @api recordId;

    @track tasks = [];

    @wire(EnclosingTabId)
    enclosingTabId;

    _channelName = '/event/Refresh_Detail__e';

    connectedCallback() {debugger
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
                console.error('MainTrackTasks – error fetching tasks:', error);
            });
    }

    _subscribeToEmpApi() {
        subscribe(this._channelName, -1, () => {
            this._loadTasks();
        })
        .then(subscription => {
            this._empSubscription = subscription;
            console.log('MainTrackTasks - subscribed to', this._channelName, subscription);
        });

        onError(error => {
            console.error('MainTrackTasks - EMP API error:', JSON.stringify(error));
        });
    }

    _unsubscribeFromEmpApi() {
        if (this._empSubscription) {
            unsubscribe(this._empSubscription, response => {
                console.log('MainTrackTasks - unsubscribed from EMP API:', response);
            });
            this._empSubscription = null;
        }
    }

    _handleCaseStatusMessage(message) {
        if (!message || !message.recordId) {
            return;
        }
        if (!this.recordId || this.recordId === message.recordId) {
            this._loadTasks();
        }
    }

    navigateToTask(event) {
        const taskId  = event.currentTarget.dataset.taskid;
        const taskSub = event.currentTarget.dataset.tasksub;

        const parentTabId = this.enclosingTabId?.data;

        if (parentTabId) {
            // Inside a Salesforce Console – open as a sub-tab
            openSubtab(this, {
                parentTabId : parentTabId,
                recordId    : taskId,
                focus       : true,
                label       : taskSub
            }).catch(error => {
                console.error('MainTrackTasks – error opening subtab:', error);
            });
        } else {
            // Outside a console (e.g. Experience Cloud) – navigate to record URL
            window.location.href = `/${taskId}`;
        }
    }
}