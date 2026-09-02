import { LightningElement, api, wire } from 'lwc';

import getCurrentTask from '@salesforce/apex/CaseCurrentTaskController.getCurrentTask';
import markComplete from '@salesforce/apex/CaseCurrentTaskController.markComplete';
import updateTask from '@salesforce/apex/CaseCurrentTaskController.updateTask';
import searchUsers from '@salesforce/apex/CaseCurrentTaskController.searchUsers';
import isCurrentUserMemberOfQueue from '@salesforce/apex/CaseCurrentTaskController.isCurrentUserMemberOfQueue';
import { RefreshEvent } from 'lightning/refresh';
import {
    publish,
    subscribe as subscribeToMessageChannel,
    unsubscribe as unsubscribeFromMessageChannel,
    MessageContext,
    APPLICATION_SCOPE
} from 'lightning/messageService';
import CASE_STATUS_UPDATED from '@salesforce/messageChannel/CaseStatusUpdated__c';
import { subscribe, unsubscribe } from 'lightning/empApi';
import USER_ID from '@salesforce/user/Id';

export default class CaseCurrentTask extends LightningElement {
    currentUserId = USER_ID;
    channelName = '/event/Refresh_Detail__e';
    task;
    subscription;
    caseStatusSubscription;

    // Imperative-load state (see loadCurrentTask)
    _recordId;
    hasLoaded = false;
    retryCount = 0;
    retryTimeoutId;
    RETRY_LIMIT = 6;
    RETRY_INTERVAL_MS = 20000;

    /*
     * Loaded imperatively rather than through a cacheable @wire. On the ARC LWR
     * site the cacheable wire served a stale null and only revalidated minutes
     * later, so the tile read "No current task available" long after the case
     * had one. Re-fetching on every recordId change keeps it live.
     */
    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        const changed = this._recordId !== value;
        this._recordId = value;
        if (value && changed) {
            this.retryCount = 0;
            this.loadCurrentTask();
        }
    }

    // Edit State
    isEditingOwner = false;
    isEditingDueDate = false;

    // Editable Fields
    editedOwnerId;
    editedDueDate;

    // Lookup
    assigneeSearchTerm = '';
    assigneeSearchResults = [];
    isAssigneeDropdownOpen = false;

    // Queue Permission
    isQueueMember = false;

    @wire(MessageContext)
    messageContext;

    /* ================= LIFECYCLE ================= */

    connectedCallback() {
        this.subscribePlatformEvent();
        this.subscribeCaseStatusChannel();
        if (this._recordId && !this.hasLoaded) {
            this.loadCurrentTask();
        }
    }

    disconnectedCallback() {
        this.unsubscribePlatformEvent();
        this.unsubscribeCaseStatusChannel();
        this.clearRetry();
    }

    /* ================= GETTERS ================= */

    get hasTask() {
        return Boolean(this.task);
    }

    get isCompleted() {
        return this.task?.Status === 'Completed';
    }

    get isOwnedByCurrentUser() {
        return String(this.task?.OwnerId) === String(this.currentUserId);
    }

    get isAnyFieldEditing() {
        return this.isOwnedByCurrentUser &&
            (this.isEditingOwner || this.isEditingDueDate);
    }

    get isOwnerQueue() {
        return String(this.task?.OwnerId ?? '').startsWith('00G');
    }

    get canAssignToMe() {
        if (this.isOwnedByCurrentUser) return false;
        return this.isOwnerQueue ? this.isQueueMember : true;
    }

    /* ================= INITIALIZE ================= */

    initializeTaskData() {

        this.editedOwnerId = this.task.OwnerId;
        this.editedDueDate = this.task.ActivityDate;
        this.assigneeSearchTerm = this.task.Owner?.Name;
    }

    async checkQueueMembership() {
        try {
            this.isQueueMember =
                await isCurrentUserMemberOfQueue({
                    ownerId: this.task.OwnerId
                });

        } catch (error) {
            console.error(error);
        }
    }

    /* ================= PLATFORM EVENT ================= */

    subscribePlatformEvent() {
        subscribe(
            this.channelName,
            -1,
            () => this.refreshTask()
        ).then(response => {
            this.subscription = response;
        });
    }

    unsubscribePlatformEvent() {
        if (this.subscription) {
            unsubscribe(this.subscription);
        }
    }

    /* ================= MESSAGE CHANNEL ================= */
    /*
     * The empApi platform-event subscription above does not deliver inside the
     * ARC LWR site, so the tile also listens on the CaseStatusUpdated message
     * channel. arcCaseDetail publishes it whenever a flow finishes -- including
     * after a Branch or Home Office Pit Stop is created -- so the current task
     * refreshes without a page reload.
     */
    subscribeCaseStatusChannel() {
        if (this.caseStatusSubscription) {
            return;
        }
        this.caseStatusSubscription = subscribeToMessageChannel(
            this.messageContext,
            CASE_STATUS_UPDATED,
            (message) => this.handleCaseStatusUpdate(message),
            { scope: APPLICATION_SCOPE }
        );
    }

    unsubscribeCaseStatusChannel() {
        if (this.caseStatusSubscription) {
            unsubscribeFromMessageChannel(this.caseStatusSubscription);
            this.caseStatusSubscription = null;
        }
    }

    handleCaseStatusUpdate(message) {
        if (!message || String(message.recordId) !== String(this.recordId)) {
            return;
        }
        this.refreshTask();
    }

    /* ================= LOAD / REFRESH ================= */

    /*
     * Fetches the current task fresh from the server. Current_Task_Id__c can be
     * stamped a little after the tasks exist (sync triggers, the pit stop flows,
     * or the async Batch_TaskUpdate job), so when nothing comes back the tile
     * retries a few times and fills in on its own instead of waiting for a
     * manual reload.
     */
    async loadCurrentTask() {
        if (!this._recordId) {
            return;
        }
        try {
            const data = await getCurrentTask({ caseId: this._recordId });
            this.hasLoaded = true;
            this.task = data;
            if (data) {
                this.retryCount = 0;
                this.clearRetry();
                this.initializeTaskData();
                this.checkQueueMembership();
            } else {
                this.scheduleRetry();
            }
        } catch (error) {
            console.error(error);
        }
    }

    scheduleRetry() {
        if (this.retryTimeoutId || this.retryCount >= this.RETRY_LIMIT) {
            return;
        }
        this.retryCount += 1;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.retryTimeoutId = setTimeout(() => {
            this.retryTimeoutId = null;
            this.loadCurrentTask();
        }, this.RETRY_INTERVAL_MS);
    }

    clearRetry() {
        if (this.retryTimeoutId) {
            clearTimeout(this.retryTimeoutId);
            this.retryTimeoutId = null;
        }
    }

    async refreshTask() {
        await this.loadCurrentTask();
        this.dispatchEvent(new RefreshEvent());
    }

    publishRefreshMessage() {
        publish(
            this.messageContext,
            CASE_STATUS_UPDATED,
            {
                recordId: this.recordId
            }
        );
    }

    /* ================= EDIT ================= */

    editOwner() {
       this.isEditingOwner = this.isEditingDueDate = true;
    }

    editDueDate() {
       this.isEditingOwner = this.isEditingDueDate = true;
    }

    handleCancel() {

        this.isEditingOwner = false;
        this.isEditingDueDate = false;
        this.initializeTaskData();
    }

    /* ================= ASSIGNEE SEARCH ================= */

    async handleAssigneeSearch(event) {

        const value = event.target.value?.trim();
        this.assigneeSearchTerm = value;
        if (!value) {
            this.assigneeSearchResults = [];
            this.isAssigneeDropdownOpen = false;
            return;
        }
        try {

            this.assigneeSearchResults =
                await searchUsers({
                    searchKey: value
                });

            this.isAssigneeDropdownOpen =
                this.assigneeSearchResults.length > 0;
        } catch (error) {
            console.error(error);
        }
    }

    handleAssigneeSelect(event) {
        this.editedOwnerId = event.currentTarget.dataset.value;
        this.assigneeSearchTerm = event.currentTarget.dataset.label;
        this.isAssigneeDropdownOpen = false;
    }

    /* ================= DUE DATE ================= */

    handleDueDateChange(event) {
        this.editedDueDate = event.target.value;
    }

    /* ================= SAVE ================= */

    async handleSave() {

        try {
            await updateTask({
                taskId: this.task.Id,
                ownerId: this.editedOwnerId,
                dueDate: this.editedDueDate
            });
            this.isEditingOwner = false;
            this.isEditingDueDate = false;
            await this.refreshTask();
            this.publishRefreshMessage();
        } catch (error) {
            console.error(error);
        }
    }

    /* ================= ASSIGN TO ME ================= */

    async handleAssignToMe() {
        this.editedOwnerId = this.currentUserId;
        await this.handleSave();
    }

    /* ================= MARK COMPLETE ================= */

    async handleMarkComplete() {
        try {
            await markComplete({
                taskId: this.task.Id
            });
            await this.refreshTask();
            this.publishRefreshMessage();
        } catch (error) {
            console.error(error);
        }
    }
}