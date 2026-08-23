import { LightningElement, api, wire } from 'lwc';

import getCurrentTask from '@salesforce/apex/CaseCurrentTaskController.getCurrentTask';
import markComplete from '@salesforce/apex/CaseCurrentTaskController.markComplete';
import updateTask from '@salesforce/apex/CaseCurrentTaskController.updateTask';
import searchUsers from '@salesforce/apex/CaseCurrentTaskController.searchUsers';
import isCurrentUserMemberOfQueue from '@salesforce/apex/CaseCurrentTaskController.isCurrentUserMemberOfQueue';
import { RefreshEvent } from 'lightning/refresh';
import { refreshApex } from '@salesforce/apex';
import { publish, MessageContext } from 'lightning/messageService';
import CASE_STATUS_UPDATED from '@salesforce/messageChannel/CaseStatusUpdated__c';
import { subscribe, unsubscribe } from 'lightning/empApi';
import USER_ID from '@salesforce/user/Id';

export default class CaseCurrentTask extends LightningElement {
    @api recordId;
    currentUserId = USER_ID;
    channelName = '/event/Refresh_Detail__e';
    task;
    wiredTaskResult;
    subscription;

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

    /* ================= WIRE ================= */

    @wire(getCurrentTask, { caseId: '$recordId' })
    wiredTask(result) {

        this.wiredTaskResult = result;
        const { data, error } = result;

        if (data) {
            this.task = data;
            this.initializeTaskData();
            this.checkQueueMembership();
        } else if (error) {
            console.error(error);
        }
    }

    /* ================= LIFECYCLE ================= */

    connectedCallback() {
        this.subscribePlatformEvent();
    }

    disconnectedCallback() {
        this.unsubscribePlatformEvent();
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

    /* ================= REFRESH ================= */
    async refreshTask() {
        await refreshApex(this.wiredTaskResult);
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