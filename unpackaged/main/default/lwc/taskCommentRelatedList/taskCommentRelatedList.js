import { LightningElement, api, track } from 'lwc';
import getComments from '@salesforce/apex/TaskCommentController.getComments';

// Number of rows shown in the collapsed "preview" view
const PREVIEW_COUNT = 5;

// Column definitions – static, mirrors the original Aura controller init
const COLUMNS = [
    { label: 'Created By',   fieldName: 'OwnerName__c',   type: 'text' },
    { label: 'Created Date', fieldName: 'CreatedDate',     type: 'date' },
    {
        label     : 'Comment',
        fieldName : 'CommentBody__c',
        type      : 'text',
        wrapText  : true,
    },
];

export default class TaskCommentRelatedList extends LightningElement {

    @api recordId;

    @api sobjectLabelPlural = 'Task Comments';

    @track _allData    = [];   // every record returned by Apex
    @track _firstFive  = [];   // first PREVIEW_COUNT records
    @track _showingAll = false; // toggle state

    dataCount = 0;

    columns = COLUMNS;

    connectedCallback() {
        this._loadData();
    }

    get displayedData() {
        return this._showingAll ? this._allData : this._firstFive;
    }

    get viewMinMax() {
        return this._showingAll ? 'View Less' : 'View All';
    }
     get showData() {
        return this.displayedData.length > 0;
    }

    _loadData() {
        getComments({ recordId: this.recordId })
            .then(result => {
                const data        = result || [];
                this._allData    = data;
                this._firstFive  = data.slice(0, PREVIEW_COUNT);
                this.dataCount   = data.length;
                this._showingAll = false;
            })
            .catch(error => {
                console.error('TaskCommentRelatedList - error fetching comments:', error);
            });
    }

    toggleViewAll() {
        this._showingAll = !this._showingAll;
    }
}