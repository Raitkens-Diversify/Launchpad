import { LightningElement, api, track, wire } from 'lwc';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import { EnclosingTabId, openSubtab } from 'lightning/platformWorkspaceApi';
import getTasks from '@salesforce/apex/HomeOfficePitStopController.getTasks';

const MILESTONES = [
    { field: 'Home_Office_Submission_Milestone__c', label: 'Home Office Submission Milestone', prefix: 'sub' },
    { field: 'Home_Office_Approval_Milestone__c',   label: 'Home Office Approval Milestone',   prefix: 'app' },
    { field: 'Branch_Goal_Milestone__c',             label: 'Branch Goal Milestone',             prefix: 'bgm' },
    { field: 'Home_Office_Goal_Milestone__c',        label: 'Home Office Goal Milestone',        prefix: 'hgm' },
];

export default class HomeOfficePitStop extends LightningElement {

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

   
    get processedRows() {
        const rows = [];

        (this.tasks || []).forEach(task => {
            // Task data row
            rows.push({
                key    : `task_${task.Id}`,
                isTask : true,
                task,
            });

            // Milestone banner rows — appear immediately after their task row
            const item = task.Task_Template_Item__r || {};
            MILESTONES.forEach(({ field, label, prefix }) => {
                if (item[field]) {
                    rows.push({
                        key    : `${prefix}_${task.Id}`,
                        isTask : false,
                        label,
                    });
                }
            });
        });

        return rows;
    }

    _loadTasks() {
        getTasks({ recordId: this.recordId })
            .then(result => {
                this.tasks = result;
            })
            .catch(error => {
                console.error('HomeOfficePitStop - error fetching tasks:', error);
            });
    }

    _subscribeToEmpApi() {
        subscribe(this._channelName, -1, message => {
            console.log('HomeOfficePitStop - platform event received:', message);
            this._loadTasks();
        })
        .then(subscription => {
            this._empSubscription = subscription;
            console.log('HomeOfficePitStop - subscribed to channel:', subscription.channel);
        });

        onError(error => {
            console.error('HomeOfficePitStop - EMP API error:', JSON.stringify(error));
        });
    }

    _unsubscribeFromEmpApi() {
        if (this._empSubscription) {
            unsubscribe(this._empSubscription, response => {
                console.log('HomeOfficePitStop – unsubscribed from EMP API:', response);
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
                console.error('HomeOfficePitStop – error opening subtab:', error);
            });
        } else {
            // Experience Cloud / standard nav – navigate to the record URL
            window.location.href = `/${taskId}`;
        }
    }
}