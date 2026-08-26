import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import {
    subscribe as lmsSubscribe,
    unsubscribe as lmsUnsubscribe,
    MessageContext
} from 'lightning/messageService';
import { EnclosingTabId, openSubtab } from 'lightning/platformWorkspaceApi';
import CASE_STATUS_UPDATED from '@salesforce/messageChannel/CaseStatusUpdated__c';
import getTasks from '@salesforce/apex/HomeOfficePitStopController.getTasks';
import { buildRecordNavigationReference } from 'c/recordNavigationCommunityUtils';

const MILESTONES = [
    { field: 'Home_Office_Submission_Milestone__c', label: 'Home Office Submission Milestone', prefix: 'sub' },
    { field: 'Home_Office_Approval_Milestone__c',   label: 'Home Office Approval Milestone',   prefix: 'app' },
    { field: 'Branch_Goal_Milestone__c',             label: 'Branch Goal Milestone',             prefix: 'bgm' },
    { field: 'Home_Office_Goal_Milestone__c',        label: 'Home Office Goal Milestone',        prefix: 'hgm' },
];

export default class HomeOfficePitStop extends NavigationMixin(LightningElement) {

    @api recordId;

    @track tasks = [];

    @wire(MessageContext)
    messageContext;

    _lmsSubscription = null;

    @wire(EnclosingTabId)
    enclosingTabId;

    _empSubscription = null;
    _channelName = '/event/Refresh_Detail__e';

    connectedCallback() {
        this._loadTasks();
        this._subscribeToEmpApi();
        this._subscribeToLms();
    }

    disconnectedCallback() {
        this._unsubscribeFromEmpApi();
        this._unsubscribeFromLms();
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
                console.error('HomeOfficePitStop – error fetching tasks:', error);
            });
    }

    _subscribeToEmpApi() {
        subscribe(this._channelName, -1, message => {
            console.log('HomeOfficePitStop – platform event received:', message);
            this._loadTasks();
        })
        .then(subscription => {
            this._empSubscription = subscription;
            console.log('HomeOfficePitStop – subscribed to channel:', subscription.channel);
        });

        onError(error => {
            console.error('HomeOfficePitStop – EMP API error:', JSON.stringify(error));
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

    _subscribeToLms() {
        this._lmsSubscription = lmsSubscribe(
            this.messageContext,
            CASE_STATUS_UPDATED,
            message => this._handleCaseStatusMessage(message)
        );
    }

    _unsubscribeFromLms() {
        lmsUnsubscribe(this._lmsSubscription);
        this._lmsSubscription = null;
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
        /*
         * The anchor is href="javascript:void(0);", which the LWR site's CSP
         * refuses to run — so without preventDefault the browser tried to
         * follow it, the navigation below never got the chance, and the click
         * did nothing at all.
         */
        event.preventDefault();

        const taskId  = event.currentTarget.dataset.taskid;
        const taskSub = event.currentTarget.dataset.tasksub;

        if (!taskId) {
            return;
        }

        /*
         * `/<recordId>` is a Lightning Experience convention and is not a route
         * on an LWR site, so on the ARC site that landed on Invalid Page.
         * buildRecordNavigationReference resolves the site's own record path
         * (/ARC/task/<id>) and falls back to the standard record page anywhere
         * that is not an Experience site. Built up front because the console
         * branch needs the same reference.
         */
        const pageReference = buildRecordNavigationReference(taskId, 'Task');

        if (!pageReference) {
            return;
        }

        const parentTabId = this.enclosingTabId?.data;

        if (parentTabId) {
            /*
             * Console app - open as a sub-tab. openSubtab takes the parent tab
             * id as its first argument and a pageReference in its options; it
             * was previously called as openSubtab(this, { recordId }), the old
             * Aura workspaceAPI shape, which rejected every time and left the
             * click doing nothing wherever a console tab existed.
             */
            openSubtab(parentTabId, {
                pageReference,
                focus: true,
                label: taskSub,
            }).catch(() => {
                /* A console that will not open the sub-tab should still get the
                   user to the task rather than nowhere. */
                this[NavigationMixin.Navigate](pageReference);
            });
            return;
        }

        this[NavigationMixin.Navigate](pageReference);
    }
}