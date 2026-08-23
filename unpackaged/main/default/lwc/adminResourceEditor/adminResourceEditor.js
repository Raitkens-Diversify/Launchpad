import { LightningElement, api } from 'lwc';
import { slugify } from 'c/slugUtil';
import { resourceDetailUrl, copyText } from 'c/rcLinkUtil';
import getResourceLinkBase from '@salesforce/apex/ResourceCenterService.getResourceLinkBase';
import getResource from '@salesforce/apex/ResourceAdminController.getResource';
import saveResource from '@salesforce/apex/ResourceAdminController.saveResource';
import isSlugAvailable from '@salesforce/apex/ResourceAdminController.isSlugAvailable';
import getResourceCategoryTree from '@salesforce/apex/ResourceAdminController.getResourceCategoryTree';
import getFiles from '@salesforce/apex/ResourceAdminController.getFiles';
import removeFile from '@salesforce/apex/ResourceAdminController.removeFile';
import { messageFrom, toast } from 'c/messageUtil';
import { FILE_TYPES, DEFAULT_TYPE } from 'c/rcConstants';

/**
 * adminResourceEditor — guided Resource__c form replacing addResourceAction:
 * type-first conditional fields, auto-suggested slug, single-select category
 * tree, explicit file management (the newest file is what downloads), and a
 * related-articles linker writing stable KA Ids. Emits `back`.
 */
const TYPE_OPTIONS = [
    { label: 'PDF (uploaded file)', value: 'PDF' },
    { label: 'Form (uploaded file)', value: 'Form' },
    { label: 'Template (uploaded file)', value: 'Template' },
    { label: 'Video (embedded)', value: 'Video' },
    { label: 'External Link', value: 'External Link' }
];
const ACCEPTED_FORMATS = [
    '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', '.png', '.jpg', '.zip'
];

export default class AdminResourceEditor extends LightningElement {
    /** Resource__c Id to edit; null/undefined = create. */
    @api resourceId;

    recordId; // internal copy — set after create
    loading = true;
    saving = false;
    errorMessage;

    categoryTree = [];
    name = '';
    slug = '';
    description = '';
    resourceType = DEFAULT_TYPE;
    categorySelection = [];
    externalUrl = '';
    videoEmbedUrl = '';
    featured = false;
    active = true;
    displayOrder;
    articleItems = [];
    files = [];

    slugTouched = false;
    slugError = '';
    linkBase = null; // enables the header "Copy link" action

    async connectedCallback() {
        getResourceLinkBase()
            .then((base) => {
                this.linkBase = base || null;
            })
            .catch(() => {
                this.linkBase = null;
            });
        try {
            this.recordId = this.resourceId;
            this.categoryTree = await getResourceCategoryTree();
            if (this.recordId) {
                await this.loadResource();
            }
        } catch (e) {
            this.errorMessage = messageFrom(e);
        } finally {
            this.loading = false;
        }
    }

    async loadResource() {
        const r = await getResource({ resourceId: this.recordId });
        this.name = r.name || '';
        this.slug = r.slug || '';
        this.description = r.description || '';
        this.resourceType = r.resourceType || DEFAULT_TYPE;
        this.categorySelection = r.categoryId ? [r.categoryId] : [];
        this.externalUrl = r.externalUrl || '';
        this.videoEmbedUrl = r.videoEmbedUrl || '';
        this.featured = r.featured === true;
        this.active = r.active !== false;
        this.displayOrder = r.displayOrder;
        this.slugTouched = true;
        this.files = this.decorateFiles(r.files || []);
        this.articleItems = (r.relatedArticles || []).map((a) => ({
            value: a.kaId,
            label: a.title || a.urlName || a.kaId,
            sublabel: a.urlName
        }));
    }

    decorateFiles(files) {
        return files.map((f) => ({
            ...f,
            label: f.title + (f.extension ? '.' + f.extension : ''),
            badge: f.isCurrent ? 'Serving' : 'Older'
        }));
    }

    // ---- Derived ------------------------------------------------------------------

    get isNew() {
        return !this.recordId;
    }

    get headerTitle() {
        return this.isNew ? 'New resource' : this.name || 'Edit resource';
    }

    get statusNote() {
        if (this.isNew) {
            return 'Save first, then upload the file (for file-backed types).';
        }
        return this.needsFile
            ? 'The newest uploaded file is what users download — remove older ones to be safe.'
            : 'This type doesn’t use uploaded files.';
    }

    get typeOptions() {
        return TYPE_OPTIONS;
    }

    get needsFile() {
        return FILE_TYPES.includes(this.resourceType);
    }

    get isVideo() {
        return this.resourceType === 'Video';
    }

    get isExternal() {
        return this.resourceType === 'External Link';
    }

    get showUpload() {
        return !this.isNew && this.needsFile;
    }

    get acceptedFormats() {
        return ACCEPTED_FORMATS;
    }

    get hasFiles() {
        return this.files.length > 0;
    }

    get busy() {
        return this.loading || this.saving;
    }

    get copyUrl() {
        // Only saved resources have a live page to link to.
        return this.isNew ? null : resourceDetailUrl(this.linkBase, this.slug);
    }

    // ---- Field handlers ---------------------------------------------------------------

    handleNameChange(event) {
        this.name = event.target.value;
        if (this.isNew && !this.slugTouched) {
            this.slug = slugify(this.name);
        }
    }

    handleSlugChange(event) {
        this.slug = event.target.value;
        this.slugTouched = true;
        this.slugError = '';
    }

    async handleSlugBlur() {
        const clean = slugify(this.slug);
        if (clean !== this.slug) {
            this.slug = clean;
        }
        if (!clean) {
            return;
        }
        try {
            const available = await isSlugAvailable({
                slug: clean,
                excludeId: this.recordId || null
            });
            this.slugError = available
                ? ''
                : 'Another resource already uses this slug — pick a different one.';
        } catch (e) {
            this.slugError = '';
        }
    }

    handleDescriptionChange(event) {
        this.description = event.target.value;
    }
    handleTypeChange(event) {
        this.resourceType = event.detail.value;
    }
    handleCategoryChange(event) {
        this.categorySelection = event.detail.names;
    }
    handleExternalUrlChange(event) {
        this.externalUrl = event.target.value;
    }
    handleVideoUrlChange(event) {
        this.videoEmbedUrl = event.target.value;
    }
    handleFeaturedChange(event) {
        this.featured = event.target.checked;
    }
    handleActiveChange(event) {
        this.active = event.target.checked;
    }
    handleOrderChange(event) {
        this.displayOrder = event.target.value ? Number(event.target.value) : null;
    }
    handleArticlesChange(event) {
        this.articleItems = event.detail.items;
    }
    handleBack() {
        this.dispatchEvent(new CustomEvent('back'));
    }

    async handleCopyLink() {
        const url = this.copyUrl;
        if (!url) {
            return;
        }
        try {
            await copyText(url);
            toast(this, 'success', 'Link copied — paste it anywhere, including article bodies.');
        } catch (e) {
            toast(this, 'error', 'Could not copy the link: ' + url);
        }
    }

    // ---- Save ---------------------------------------------------------------------

    validate() {
        if (!this.name.trim()) {
            toast(this, 'error', 'Name is required.');
            return false;
        }
        if (!this.slug.trim()) {
            toast(this, 'error', 'URL slug is required (it becomes the resource link).');
            return false;
        }
        if (this.slugError) {
            toast(this, 'error', this.slugError);
            return false;
        }
        if (this.categorySelection.length === 0) {
            toast(this, 'error', 'Pick a category — resources always live in one.');
            return false;
        }
        if (this.isVideo && !this.videoEmbedUrl.trim()) {
            toast(this, 'error', 'Video resources need a Video Embed URL.');
            return false;
        }
        if (this.isExternal && !this.externalUrl.trim()) {
            toast(this, 'error', 'External Link resources need an External URL.');
            return false;
        }
        return true;
    }

    async handleSave() {
        if (!this.validate()) {
            return;
        }
        this.saving = true;
        try {
            const wasNew = this.isNew;
            // JSON-string transport: custom-Apex-type @AuraEnabled params arrive
            // null/blank from LWC in this org.
            const id = await saveResource({
                inputJson: JSON.stringify({
                    id: this.recordId || null,
                    name: this.name,
                    slug: this.slug,
                    description: this.description,
                    resourceType: this.resourceType,
                    categoryId: this.categorySelection[0],
                    externalUrl: this.externalUrl || null,
                    videoEmbedUrl: this.videoEmbedUrl || null,
                    featured: this.featured,
                    active: this.active,
                    displayOrder: this.displayOrder,
                    relatedArticleKaIds: this.articleItems.map((i) => i.value)
                })
            });
            this.recordId = id;
            toast(this, 
                'success',
                wasNew && this.needsFile
                    ? 'Saved — now upload the file below.'
                    : 'Resource saved.'
            );
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
        }
    }

    // ---- Files --------------------------------------------------------------------

    async refreshFiles() {
        try {
            const files = await getFiles({ resourceId: this.recordId });
            this.files = this.decorateFiles(files || []);
        } catch (e) {
            // file list is auxiliary — leave the stale list rather than erroring
        }
    }

    handleUploadFinished() {
        toast(this, 'success', 'File uploaded — it is now what users download.');
        this.refreshFiles();
    }

    async handleRemoveFile(event) {
        const contentDocumentId = event.currentTarget.dataset.id;
        try {
            await removeFile({ resourceId: this.recordId, contentDocumentId });
            toast(this, 'success', 'File detached from this resource.');
            await this.refreshFiles();
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        }
    }

    // ---- Utils --------------------------------------------------------------------

}