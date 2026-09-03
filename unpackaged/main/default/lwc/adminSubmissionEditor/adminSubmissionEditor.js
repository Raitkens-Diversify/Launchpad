import { LightningElement, api } from 'lwc';
import { slugify } from 'c/slugUtil';
import getAuthoringMeta from '@salesforce/apex/ArticleAdminController.getAuthoringMeta';
import getSubmission from '@salesforce/apex/ArticleSubmissionController.getSubmission';
import saveSubmission from '@salesforce/apex/ArticleSubmissionController.saveSubmission';
import submitForReview from '@salesforce/apex/ArticleSubmissionController.submitForReview';
import { messageFrom, toast } from 'c/messageUtil';

/**
 * adminSubmissionEditor — the contributor flavor of the guided article form.
 * Identical inputs to adminArticleEditor (same tree/linkers/slug helper) minus
 * Featured and Publish: the rail is Save / Submit for review, and the reviewer
 * promotes+publishes. Emits `back`.
 */
export default class AdminSubmissionEditor extends LightningElement {
    /** Article_Submission__c Id to edit; null/undefined = create. */
    @api submissionId;

    recordId; // internal copy — set after create
    meta;
    loading = true;
    saving = false;
    errorMessage;

    status = 'Draft';
    reviewNotes = '';
    title = '';
    urlName = '';
    summary = '';
    recordTypeName = 'Standard';
    content = '';
    question = '';
    answer = '';
    keywords = '';
    embedUrl = '';
    categoryNames = [];
    suggestedItems = [];
    resourceItems = [];

    urlNameTouched = false;

    async connectedCallback() {
        try {
            this.recordId = this.submissionId;
            this.meta = await getAuthoringMeta();
            if (this.recordId) {
                await this.loadSubmission();
            }
        } catch (e) {
            this.errorMessage = messageFrom(e);
        } finally {
            this.loading = false;
        }
    }

    async loadSubmission() {
        const s = await getSubmission({ submissionId: this.recordId });
        this.status = s.status;
        this.reviewNotes = s.reviewNotes || '';
        this.title = s.title || '';
        this.urlName = s.proposedUrlName || '';
        this.summary = s.summary || '';
        this.recordTypeName = s.recordTypeName || 'Standard';
        this.content = s.content || '';
        this.question = s.question || '';
        this.answer = s.answer || '';
        this.keywords = s.keywords || '';
        this.embedUrl = s.embedUrl || '';
        this.categoryNames = s.categoryNames || [];
        this.urlNameTouched = !!this.urlName;
        this.suggestedItems = (s.suggestedUrlNames || []).map((u) => ({
            value: u,
            label: u,
            sublabel: 'article'
        }));
        // Labels for previously attached resources aren't stored on the
        // submission; show the Ids until re-picked (promotion resolves them).
        this.resourceItems = (s.relatedResourceIds || []).map((id) => ({
            value: id,
            label: id,
            sublabel: 'resource'
        }));
    }

    // ---- Derived ------------------------------------------------------------------

    get isNew() {
        return !this.recordId;
    }

    get headerTitle() {
        return this.isNew ? 'New submission' : this.title || 'Edit submission';
    }

    get statusNote() {
        if (this.isNew) {
            return 'Not saved yet. Submissions go to a Knowledge reviewer who publishes them.';
        }
        if (this.status === 'Changes requested') {
            return 'The reviewer sent this back — see their notes below, then resubmit.';
        }
        return 'Save as often as you like; Submit for review when it’s ready.';
    }

    get showReviewNotes() {
        return this.status === 'Changes requested' && this.reviewNotes;
    }

    get recordTypeOptions() {
        return (this.meta ? this.meta.recordTypes : []).map((rt) => ({
            label: rt.label,
            value: rt.developerName
        }));
    }

    get recordTypeDescription() {
        const rt = (this.meta ? this.meta.recordTypes : []).find(
            (r) => r.developerName === this.recordTypeName
        );
        return rt ? rt.description : '';
    }

    get isFaq() {
        return this.recordTypeName === 'FAQ';
    }

    get categoryTree() {
        return this.meta ? this.meta.categoryTree : [];
    }

    get busy() {
        return this.loading || this.saving;
    }

    // ---- Field handlers ---------------------------------------------------------------

    handleTitleChange(event) {
        this.title = event.target.value;
        if (this.isNew && !this.urlNameTouched) {
            this.urlName = slugify(this.title);
        }
    }
    handleUrlNameChange(event) {
        this.urlName = event.target.value;
        this.urlNameTouched = true;
    }
    handleUrlNameBlur() {
        this.urlName = slugify(this.urlName);
    }
    handleSummaryChange(event) {
        this.summary = event.target.value;
    }
    handleRecordTypeChange(event) {
        this.recordTypeName = event.detail.value;
    }
    handleContentChange(event) {
        this.content = event.target.value;
    }
    handleQuestionChange(event) {
        this.question = event.target.value;
    }
    handleAnswerChange(event) {
        this.answer = event.target.value;
    }
    handleKeywordsChange(event) {
        this.keywords = event.target.value;
    }
    handleEmbedUrlChange(event) {
        this.embedUrl = event.target.value;
    }
    handleCategoryChange(event) {
        this.categoryNames = event.detail.names;
    }
    handleSuggestedChange(event) {
        this.suggestedItems = event.detail.items;
    }
    handleResourcesChange(event) {
        this.resourceItems = event.detail.items;
    }
    handleBack() {
        this.dispatchEvent(new CustomEvent('back'));
    }

    // ---- Save / submit ------------------------------------------------------------------

    validate() {
        if (!this.title.trim()) {
            toast(this, 'error', 'Title is required.');
            return false;
        }
        if (!this.urlName.trim()) {
            toast(this, 'error', 'URL Name is required (it becomes the article link).');
            return false;
        }
        if (this.embedUrl && !this.embedUrl.trim().toLowerCase().startsWith('https://')) {
            toast(this, 'error', 'Embed URL must start with https://.');
            return false;
        }
        return true;
    }

    buildInput() {
        return {
            id: this.recordId,
            title: this.title,
            proposedUrlName: this.urlName,
            summary: this.summary,
            content: this.content,
            question: this.isFaq ? this.question : this.question || null,
            answer: this.isFaq ? this.answer : this.answer || null,
            keywords: this.keywords,
            embedUrl: this.embedUrl || null,
            recordTypeName: this.recordTypeName,
            categoryNames: this.categoryNames,
            suggestedUrlNames: this.suggestedItems.map((i) => i.value),
            relatedResourceIds: this.resourceItems.map((i) => i.value)
        };
    }

    async save() {
        // JSON-string transport: custom-Apex-type @AuraEnabled params arrive
        // null/blank from LWC in this org.
        const id = await saveSubmission({ inputJson: JSON.stringify(this.buildInput()) });
        this.recordId = id;
        return id;
    }

    async handleSave() {
        if (!this.validate()) {
            return;
        }
        this.saving = true;
        try {
            await this.save();
            toast(this, 'success', 'Submission saved.');
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
        }
    }

    async handleSubmit() {
        if (!this.validate()) {
            return;
        }
        this.saving = true;
        try {
            const id = await this.save();
            await submitForReview({ submissionId: id });
            toast(this, 'success', 'Submitted — a Knowledge reviewer will take it from here.');
            this.dispatchEvent(new CustomEvent('back'));
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
        }
    }

    // ---- Utils ---------------------------------------------------------------------

}