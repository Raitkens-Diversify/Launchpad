import { LightningElement, api } from 'lwc';
import { slugify } from 'c/slugUtil';
import getAuthoringMeta from '@salesforce/apex/ArticleAdminController.getAuthoringMeta';
import getArticleForEdit from '@salesforce/apex/ArticleAdminController.getArticleForEdit';
import saveArticle from '@salesforce/apex/ArticleAdminController.saveArticle';
import publishArticleApex from '@salesforce/apex/ArticleAdminController.publishArticle';
import isUrlNameAvailable from '@salesforce/apex/ArticleAdminController.isUrlNameAvailable';
import getResourceLinkBase from '@salesforce/apex/ResourceCenterService.getResourceLinkBase';
import { messageFrom, toast } from 'c/messageUtil';

/**
 * adminArticleEditor — one-screen guided Knowledge authoring for the Admin
 * Console: basics, rich-text content, discovery fields, the Help-Topics
 * category tree, and related-content linkers, with Save Draft / Publish.
 *
 * Editing a published article transparently works on its draft (spawned
 * server-side, categories carried over); readers keep seeing the published
 * version until Publish. Emits `back` and `saved`.
 */
export default class AdminArticleEditor extends LightningElement {
    /** KnowledgeArticleId to edit; null/undefined = create a new article. */
    @api kaId;

    articleKaId; // internal copy — updated after a create without mutating @api
    meta;
    loading = true;
    saving = false;
    errorMessage;

    versionId = null;
    hasOnlineVersion = false;

    title = '';
    urlName = '';
    summary = '';
    recordTypeId = '';
    content = '';
    question = '';
    answer = '';
    keywords = '';
    featured = false;
    embedUrl = '';
    categoryNames = [];
    suggestedItems = [];
    resourceItems = [];

    urlNameTouched = false;
    urlNameError = '';
    resourceLinkBase = null; // enables "Copy link" on attached resources

    async connectedCallback() {
        getResourceLinkBase()
            .then((base) => {
                this.resourceLinkBase = base || null;
            })
            .catch(() => {
                this.resourceLinkBase = null;
            });
        try {
            this.articleKaId = this.kaId;
            this.meta = await getAuthoringMeta();
            if (this.articleKaId) {
                await this.loadArticle();
            } else if (this.meta.recordTypes.length) {
                this.recordTypeId = this.meta.recordTypes[0].id;
            }
        } catch (e) {
            this.errorMessage = messageFrom(e);
        } finally {
            this.loading = false;
        }
    }

    async loadArticle() {
        const detail = await getArticleForEdit({ kaId: this.articleKaId });
        this.versionId = detail.versionId;
        this.hasOnlineVersion = detail.hasOnlineVersion;
        this.title = detail.title || '';
        this.urlName = detail.urlName || '';
        this.summary = detail.summary || '';
        this.recordTypeId = detail.recordTypeId || '';
        this.content = detail.content || '';
        this.question = detail.question || '';
        this.answer = detail.answer || '';
        this.keywords = detail.keywords || '';
        this.featured = detail.featured === true;
        this.embedUrl = detail.embedUrl || '';
        this.categoryNames = detail.categoryNames || [];
        this.urlNameTouched = true; // never overwrite an existing UrlName from the title
        this.suggestedItems = (detail.suggestedUrlNames || []).map((u) => ({
            value: u,
            label: u,
            sublabel: 'article'
        }));
        this.resourceItems = (detail.relatedResources || []).map((r) => ({
            value: r.resourceId,
            label: r.name,
            sublabel: r.resourceType,
            slug: r.slug
        }));
    }

    // ---- Derived ------------------------------------------------------------------

    get isNew() {
        return !this.versionId;
    }

    get headerTitle() {
        return this.isNew ? 'New article' : this.title || 'Edit article';
    }

    get statusNote() {
        if (this.isNew) {
            return 'Not saved yet — Save Draft creates the article as a draft nobody sees.';
        }
        return this.hasOnlineVersion
            ? 'You are editing a draft. Readers keep seeing the published version until you publish.'
            : 'Draft only — readers cannot see this article until you publish.';
    }

    get recordTypeOptions() {
        return (this.meta ? this.meta.recordTypes : []).map((rt) => ({
            label: rt.label,
            value: rt.id
        }));
    }

    get recordTypeDescription() {
        const rt = (this.meta ? this.meta.recordTypes : []).find(
            (r) => r.id === this.recordTypeId
        );
        return rt ? rt.description : '';
    }

    get isFaq() {
        const rt = (this.meta ? this.meta.recordTypes : []).find(
            (r) => r.id === this.recordTypeId
        );
        return !!rt && rt.developerName === 'FAQ';
    }

    get categoryTree() {
        return this.meta ? this.meta.categoryTree : [];
    }

    get busy() {
        return this.loading || this.saving;
    }

    get publishLabel() {
        return this.hasOnlineVersion ? 'Publish changes' : 'Publish';
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
        this.urlNameError = '';
    }

    async handleUrlNameBlur() {
        const clean = slugify(this.urlName);
        if (clean !== this.urlName) {
            this.urlName = clean;
        }
        if (!clean) {
            return;
        }
        try {
            const available = await isUrlNameAvailable({
                urlName: clean,
                kaId: this.articleKaId || null
            });
            this.urlNameError = available
                ? ''
                : 'Another article already uses this URL name — pick a different one.';
        } catch (e) {
            this.urlNameError = '';
        }
    }

    handleSummaryChange(event) {
        this.summary = event.target.value;
    }
    handleRecordTypeChange(event) {
        this.recordTypeId = event.detail.value;
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
    handleFeaturedChange(event) {
        this.featured = event.target.checked;
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

    // ---- Save / publish ------------------------------------------------------------------

    validate() {
        if (!this.title.trim()) {
            toast(this, 'error', 'Title is required.');
            return false;
        }
        if (!this.urlName.trim()) {
            toast(this, 'error', 'URL Name is required (it becomes the article link).');
            return false;
        }
        if (this.urlNameError) {
            toast(this, 'error', this.urlNameError);
            return false;
        }
        if (this.embedUrl && !this.embedUrl.trim().toLowerCase().startsWith('https://')) {
            toast(this, 'error', 'Embed URL must start with https:// — the viewer refuses anything else.');
            return false;
        }
        return true;
    }

    buildInput() {
        // Serialized to JSON: custom-Apex-type @AuraEnabled params arrive
        // null/blank from LWC in this org.
        return {
            versionId: this.versionId,
            recordTypeId: this.recordTypeId || null,
            title: this.title,
            urlName: this.urlName,
            summary: this.summary,
            content: this.content,
            question: this.isFaq ? this.question : this.question || null,
            answer: this.isFaq ? this.answer : this.answer || null,
            keywords: this.keywords,
            featured: this.featured,
            embedUrl: this.embedUrl || null,
            suggestedUrlNames: this.suggestedItems.map((i) => i.value),
            categoryNames: this.categoryNames,
            relatedResourceIds: this.resourceItems.map((i) => i.value)
        };
    }

    async handleSaveDraft() {
        if (!this.validate()) {
            return;
        }
        this.saving = true;
        try {
            const res = await saveArticle({ inputJson: JSON.stringify(this.buildInput()) });
            this.versionId = res.versionId;
            this.articleKaId = res.kaId;
            toast(this, 'success', 'Draft saved.');
            this.dispatchEvent(new CustomEvent('saved', { detail: { kaId: res.kaId } }));
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
        }
    }

    async handlePublish() {
        if (!this.validate()) {
            return;
        }
        this.saving = true;
        try {
            const res = await saveArticle({ inputJson: JSON.stringify(this.buildInput()) });
            this.versionId = res.versionId;
            this.articleKaId = res.kaId;
            await publishArticleApex({ kaId: res.kaId });
            toast(this, 'success', 'Published — the article is live on the Help Center.');
            this.dispatchEvent(new CustomEvent('saved', { detail: { kaId: res.kaId } }));
            this.dispatchEvent(new CustomEvent('back'));
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
        }
    }

    // ---- Utils ---------------------------------------------------------------------

}