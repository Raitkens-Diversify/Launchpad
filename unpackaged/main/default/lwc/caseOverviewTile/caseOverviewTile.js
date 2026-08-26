import { LightningElement, api, wire } from 'lwc';
import { subscribe as lmsSubscribe, unsubscribe as lmsUnsubscribe, MessageContext } from 'lightning/messageService';
import { getRecord } from 'lightning/uiRecordApi';
import { isValidSalesforceRecordId } from 'c/recordNavigationUtils';
import { NavigationMixin } from 'lightning/navigation';
import { subscribe, unsubscribe } from 'lightning/empApi';
import USER_ID from '@salesforce/user/Id';
import DIVERSIFY_ICONS from '@salesforce/resourceUrl/Diversify_Icons';
import getCaseStatusSummary from '@salesforce/apex/CaseStatusSummaryController.getCaseStatusSummary';
import CASE_NUMBER_FIELD from '@salesforce/schema/Case.CaseNumber';
import CASE_STATUS_UPDATED from '@salesforce/messageChannel/CaseStatusUpdated__c';
import CASE_SUBJECT_FIELD from '@salesforce/schema/Case.Subject';
import { registerRefreshHandler, unregisterRefreshHandler } from 'lightning/refresh';
import { RefreshEvent } from 'lightning/refresh';

const CASE_FIELDS = [CASE_NUMBER_FIELD, CASE_SUBJECT_FIELD];
const MILESTONE_STAGES = [
    { label: 'Home Office Submission' },
    { label: 'Home Office Approval' },
    { label: 'Branch Goal' },
    { label: 'Home Office Goal' }
];


export default class CaseOverviewTile extends NavigationMixin(LightningElement) {
    _recordId;
    /*
     * Initialised rather than left undefined: the template iterates it, and on a
     * case with no milestones processMilestones is never reached (the empty-state
     * path is taken instead), which made LWC throw "Invalid template iteration
     * for value `undefined`" on every render.
     */
    mileStoneDetails = [];
    channelName = '/event/Refresh_Detail__e';
    subscriptionRefresh = null;
    refreshHandlerID;

    @wire(MessageContext)
    messageContext;

    lmsSubscription = null;

    @api
    get recordId() {
        return this._recordId;
    }

    set recordId(value) {
        const nextRecordId = isValidSalesforceRecordId(value) ? value : null;
        if (nextRecordId !== this._recordId) {
            this._recordId = nextRecordId;
            if (this._recordId) {
                this.loadSummary();
            }
        }
    }
    userId = USER_ID;
    data;
    loaded = false;
    subscription = null;

    get wiredCaseRecordId() {
        return isValidSalesforceRecordId(this._recordId) ? this._recordId : undefined;
    }

    @wire(getRecord, { recordId: '$wiredCaseRecordId', fields: CASE_FIELDS })
    caseRecord;
    membership;
    messageContext;

    connectedCallback() {
        if (this.recordId) {
            this.loadSummary();
        }else{
            this.loaded = true;
        }
        this.refreshHandlerID = registerRefreshHandler(this.template.host,  this.handleRefreshView);
        this.handleSubscribe();
        this.subscribeToLMS();
    }

    disconnectedCallback() {
    }

    subscribeToLMS() {
        if (this.lmsSubscription) {
            return;
        }

        this.lmsSubscription = lmsSubscribe(
            this.messageContext,
            CASE_STATUS_UPDATED,
            (message) => {
                if (message.recordId === this.recordId) {
                    this.loadSummary(); // This refetches
                }
            }
        );
    }
    
    handleSubscribe() {
        const thisReference = this;
        const messageCallback = function (response) { 
        thisReference.handleRefreshView();
        thisReference.dispatchEvent(new CustomEvent("unsubscribemessagechannel"));
        unsubscribe(thisReference.subscription, response => {
            console.log('unsubscribe() response: ', JSON.stringify(response));
        }); 
    
        };    
        subscribe(this.channelName, -1, messageCallback ).then(response => {
            this.subscription = response;
            this.dispatchEvent(new CustomEvent("subscribemessagechannel"));
        });
    };

    handleRefreshView() {
        return new Promise((resolve) => {
            console.log('Refresh triggered from Flow!');
            this.loadSummary(); 
            resolve(true);    
        });
    }

    renderedCallback() {
        const circle = this.template.querySelector('.progress-circle');
        if (circle) {
            circle.style.setProperty('--progress-angle', `${this.percentComplete * 3.6}deg`);
            circle.style.setProperty('--progress-color', this.statusColorToken);
        }
        const statusIcon = this.template.querySelector('.case-tile__status-icon');
        if (statusIcon) {
            statusIcon.style.backgroundColor = this.statusColorToken;
            statusIcon.style.color = '#ffffff';
        }
        const customPillIcon = this.template.querySelector('.case-tile__pill-icon--custom');
        if (customPillIcon && this.statusIconUrl) {
            customPillIcon.style.setProperty('--icon-url', `url('${this.statusIconUrl}')`);
        }
    }

    @api
    refresh() {
        return this.loadSummary();
    }

    emptyState() {
        return {
            statusMessage: 'No data',
            waitingOn: '',
            submissionToHO: 0,
            hoApproval: 0,
            branchGoal: 0,
            completedTasks: 0,
            totalTasks: 0,
            nextAction: '',
            timeInStage: ''
        };
    }
    handleClick() {
        this.loadSummary();
    }

    loadSummary() {
        this.handleSubscribe();
        if (!this.recordId) {
            return Promise.resolve();
        }
        this.loaded = false;
        return getCaseStatusSummary({ 
            caseId: this.recordId, 
            userId: this.userId
            })
            .then((result) => {
                this.data = result;
                /*
                 * membership comes from Case_Branch_Name__c / Case_Home_Office_Name__c,
                 * and nothing populates either field in this org — so it arrives null.
                 * Calling .replace() on it threw, and because the catch below swallowed
                 * the error and swapped in the empty state, the whole tile went wrong at
                 * once: the badge fell through to "On Track" for a case that was actually
                 * in an HO pit stop, and the owner line, the task ratio and the milestones
                 * were all blank because the assignments after this one never ran.
                 */
                this.membership = (this.data.membership || '').replace(
                    /\s*\|\s*<\/br>\s*\|\s*/g,
                    ' </br> '
                );
                this.ownerDetails = this.data.formattedOwnerDetail || '';
                this.mileStoneDetails = this.processMilestones(
                    this.data.wrappedMilestones
                );
            })
            .catch((error) => {
                // Say so rather than showing a tile that looks like real data.
                // eslint-disable-next-line no-console
                console.error('[caseOverviewTile] Failed to load case summary', error);
                this.data = this.emptyState();
                this.data.statusMessage = 'Error loading data';
            })
            .finally(() => {
                this.loaded = true;
            });
    }

    handleEvent(message) {
        console.log('Event received:', message);
    }
    disconnectedCallback() {

        if (this.lmsSubscription) {
            lmsUnsubscribe(this.lmsSubscription);
            this.lmsSubscription = null;
        }
    }

    handleUnsubscribe() {
        if (this.subscription && Object.keys(this.subscription).length > 0) {
            unsubscribe(this.subscription, (response) => {
                console.log('Successfully unsubscribed: ', JSON.stringify(response));
                this.subscription = {}; // Clear the object
            });
        }
    }

    handleStatusMessage(message) {
        console.log('Received CaseStatusUpdated message', message?.recordId);
        if (message && message.recordId === this.recordId) {
            this.refresh();
        }
    }

    get caseNumber() {
        return this.caseRecord?.data?.fields?.CaseNumber?.value || '';
    }

    get statusText() {
        return (this.data?.statusMessage || '').toLowerCase();
    }

    get statusKind() {
        const status = this.statusText;
        // if (this.isCompleted || status.includes('completed') || status.includes('closed')) {
        //     return 'complete';
        // }
        // if (status.includes('blocked')) {
        //     return 'blocked';
        // }
        // if (this.isBranchPitstop || status.includes('waiting') || status.includes('pitstop')) {
        //     return 'waiting';
        // }
        if(status.includes('branch')) {
            return 'branchpstask';
        }
        if(status.includes('ho')) {
            return 'hopstask';
        }
        if(status.includes('completed')) {
            return 'completed';
        }
        return 'in-progress';
    }

    get statusBadgeLabel() {
        const map = {
            'completed': 'Completed',
            // 'blocked': 'Blocked',
            // 'waiting': 'Waiting',
            'in-progress': 'On Track',
            'hopstask': 'HO Pit Stop',
            'branchpstask': 'Branch Pit Stop'
        };

        return map[this.statusKind] || 'Status';
    }

    get statusBadgeClass() {
        return `case-tile__badge case-tile__badge--${this.statusKind}`;
    }

    get unifiedBadgeClass() {
        return `case-tile__pill case-tile__pill--${this.statusKind}`;
    }

    get isBranchPitstop() {
        return this.statusText.includes('branch pitstop');
    }

    get isOnTrack() {
        return this.statusText.includes('on track');
    }

    get completedTasks() {
        return this.data?.completedTasks ?? 0;
    }

    get totalTasks() {
        return this.data?.totalTasks ?? 0;
    }

    get isCompleted() {
        const total = this.totalTasks;
        return total > 0 && this.completedTasks >= total;
    }

    get percentComplete() {
        const total = this.totalTasks;
        if (!total) {
            return 0;
        }
        const done = this.completedTasks;
        const rawPercent = Math.round((done / total) * 100);
        return Math.min(100, Math.max(0, rawPercent));
    }

    get progressSummary() {
        return `${this.completedTasks} of ${this.totalTasks} main track tasks`;
    }

    get taskCompletionDisplay() {
        const total = this.totalTasks;
        const done = this.completedTasks;
        if (!total) {
            return `${done}/0`;
        }
        return `${done}/${total}`;
    }

    get statusIcon() {
        console.log('Hello from statusText ', this.statusText);
        const status = this.statusText;
        if (status.includes('branch pit stop')) {
            return 'utility:shortcuts';
        }
        if (status.includes('ho pit stop')) {
            return 'utility:custom_apps';
        }
        if (status.includes('on track')) {
            return 'standard:travel_mode';
        }
        if (status.includes('all tasks completed')) {
            return 'standard:goals'
        }
        return 'utility:ban';
    }

    get statusIconUrl() {
        const status = this.statusText;
        if (status.includes('branch pit stop')) {
            return `${DIVERSIFY_ICONS}/flag-05.svg`;
        }
        if (status.includes('ho pit stop')) {
            return `${DIVERSIFY_ICONS}/flag-05.svg`;
        }
        if (status.includes('on track')) {
            return `${DIVERSIFY_ICONS}/arrows-right.svg`;
        }
        if (status.includes('all tasks completed')) {
            return `${DIVERSIFY_ICONS}/check-circle.svg`;
        }
        return null;
    }

    get statusColorToken() {
        const status = this.statusText;
        if (this.isCompleted || status.includes('completed') || status.includes('closed')) {
            return '#2e844a';
        }
        if (this.isBranchPitstop) {
            return '#ffb75d';
        }
        if (status.includes('pitstop') || status.includes('waiting')) {
            return '#ffb75d';
        }
        if (status.includes('unspecified')) {
            return '#706e6b';
        }
        if (status.includes('error')) {
            return '#ba0517';
        }
        if (this.isOnTrack) {
            return '#1b96ff';
        }
        return '#1b96ff';
    }

    get progressCircleClass() {
        return `progress-circle progress-circle--${this.statusKind}`;
    }

    get statusIconClass() {
        return 'status-icon';
    }

    get statusIconStyle() {
        return this.statusColorToken;
    }

    get tileClass() {
        return 'case-tile slds-card slds-m-bottom_medium';
    }

    get accentClass() {
        return `case-tile__accent case-tile__accent--${this.statusKind}`;
    }

    get currentStageIndex() {
        const status = this.statusText;
        if (this.isCompleted) {
            return MILESTONE_STAGES.length - 1;
        }
        if (status.includes('home office')) {
            return 3;
        }
        if (status.includes('pitstop')) {
            return 2;
        }
        return 1;
    }

    processMilestones(detailsObject) {
        let milestones = detailsObject;
        let foundCurrent = false;

        for (let i = 0; i < milestones.length; i++) {
            let milestone = milestones[i];

            if (milestone.isCompleted === true) {
                milestone.class = 'milestone--complete';
            } else if (!foundCurrent) {
                milestone.class = 'milestone--current';
                foundCurrent = true; 
            } else {
                milestone.class = 'milestone--upcoming';
            }
        }

        return detailsObject;
    }

    /** No milestones means no track — an empty one draws a bare rule. */
    get hasMilestones() {
        return (this.mileStoneDetails || []).length > 0;
    }

    get milestoneStages() {
        const currentIndex = this.currentStageIndex;
        return MILESTONE_STAGES.map((stage, index) => {
            let state = 'upcoming';
            if (index < currentIndex) {
                state = 'complete';
            } else if (index === currentIndex) {
                state = 'current';
            }
            return {
                ...stage,
                state,
                className: `milestone ${state === 'current' ? 'milestone--current' : state === 'complete' ? 'milestone--complete' : 'milestone--upcoming'}`
            };
        });
    }
}