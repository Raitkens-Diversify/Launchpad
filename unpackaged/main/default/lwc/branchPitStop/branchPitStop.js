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
import getTasks from '@salesforce/apex/BranchPitStopController.getTasks';
import { buildRecordNavigationReference } from 'c/recordNavigationCommunityUtils';

// Milestone field names → display labels (order preserved)
const MILESTONES = [
    { field: 'Home_Office_Submission_Milestone__c', label: 'Home Office Submission Milestone', prefix: 'sub'  },
    { field: 'Home_Office_Approval_Milestone__c',   label: 'Home Office Approval Milestone',   prefix: 'app'  },
    { field: 'Branch_Goal_Milestone__c',             label: 'Branch Goal Milestone',             prefix: 'bgm'  },
    { field: 'Home_Office_Goal_Milestone__c',        label: 'Home Office Goal Milestone',        prefix: 'hgm'  },
];

/*
 * Re-read schedule after a CaseStatusUpdated message. The save that publishes
 * the message returns before the server is finished with the case: the Task
 * trigger's @future work, the pit stop flows and Batch_TaskUpdate stamp the
 * next task's owner and the case's current task a beat later, so a single
 * immediate reload showed the old rows and only a page reload caught up. The
 * Refresh_Detail__e event that marks the end of that work needs
 * lightning/empApi, which the LWR site does not deliver, so the tile re-reads
 * a few more times instead.
 */
const SETTLE_DELAYS_MS = [2000, 5000, 10000];

export default class BranchPitStop extends NavigationMixin(LightningElement) {

    @api recordId;

    @track tasks = [];

    /** Disables the refresh control while a load is in flight. */
    isRefreshing = false;

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
        this._subscribeToVisibility();
    }

    disconnectedCallback() {
        this._unsubscribeFromEmpApi();
        this._unsubscribeFromLms();
        this._unsubscribeFromVisibility();
        this._clearSettleTimers();
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

            // Milestone banner rows (appear immediately after their task)
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

    /* Returns the promise so handleRefresh can tell when the load has
       settled and re-enable its control. */
    _loadTasks() {
        return getTasks({ recordId: this.recordId })
            .then(result => {
                this.tasks = result;
            })
            .catch(error => {
                // Leave the rows that are already on screen: stale tasks are
                // more use than an empty tile, and this fires on every platform
                // event too, not just a button press.
                console.error('BranchPitStop – error fetching tasks:', error);
            });
    }

    /**
     * Re-reads this tile's tasks without reloading the page, for a task someone
     * else has just added or completed.
     *
     * getTasks is not cacheable, so calling it again genuinely goes back to the
     * server. refreshApex is neither needed nor possible here: the call is
     * imperative, and refreshApex only works on a wired result.
     */
    handleRefresh() {
        if (this.isRefreshing) {
            return;
        }

        this.isRefreshing = true;

        this._loadTasks().finally(() => {
            this.isRefreshing = false;
        });
    }

    _subscribeToEmpApi() {
        subscribe(this._channelName, -1, message => {
            console.log('BranchPitStop – platform event received:', message);
            this._loadTasks();
        })
        .then(subscription => {
            this._empSubscription = subscription;
            console.log('BranchPitStop – subscribed to channel:', subscription.channel);
        });

        onError(error => {
            console.error('BranchPitStop – EMP API error:', JSON.stringify(error));
        });
    }

    _unsubscribeFromEmpApi() {
        if (this._empSubscription) {
            unsubscribe(this._empSubscription, response => {
                console.log('BranchPitStop – unsubscribed from EMP API:', response);
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
            this._reloadUntilSettled();
        }
    }

    _settleTimers = [];

    /** Reloads now and again at each SETTLE_DELAYS_MS step; see that constant. */
    _reloadUntilSettled() {
        this._clearSettleTimers();
        this._loadTasks();
        this._settleTimers = SETTLE_DELAYS_MS.map((delay) =>
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => this._loadTasks(), delay)
        );
    }

    _clearSettleTimers() {
        this._settleTimers.forEach((timer) => clearTimeout(timer));
        this._settleTimers = [];
    }

    /*
     * Re-read when the reader comes back to this tab or window (2026-09-08).
     * Nothing here is cached -- getTasks is not cacheable and the call is
     * imperative -- but a read only happens when something asks for one, and
     * neither refresh path above reaches a change made anywhere else:
     * lightning/empApi does not deliver on the LWR site, and CaseStatusUpdated
     * is only published by actions on this page. A task completed from its own
     * record page in another tab, or by another user, showed here as "stale"
     * until a reload.
     */
    _visibilityHandler = null;

    _subscribeToVisibility() {
        if (typeof document === 'undefined') {
            return;
        }
        this._visibilityHandler = () => {
            if (document.visibilityState === 'visible') {
                this._loadTasks();
            }
        };
        document.addEventListener('visibilitychange', this._visibilityHandler);
    }

    _unsubscribeFromVisibility() {
        if (this._visibilityHandler) {
            document.removeEventListener('visibilitychange', this._visibilityHandler);
            this._visibilityHandler = null;
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