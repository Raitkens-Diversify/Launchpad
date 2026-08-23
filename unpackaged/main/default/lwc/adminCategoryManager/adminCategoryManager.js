import { LightningElement } from 'lwc';
import { slugify } from 'c/slugUtil';
import { categoryIconOptions } from 'c/rcIcons';
import listCategories from '@salesforce/apex/ResourceAdminController.listCategories';
import saveCategory from '@salesforce/apex/ResourceAdminController.saveCategory';
import reorderCategories from '@salesforce/apex/ResourceAdminController.reorderCategories';
import isCategorySlugAvailable from '@salesforce/apex/ResourceAdminController.isCategorySlugAvailable';
import getAuthoringMeta from '@salesforce/apex/ArticleAdminController.getAuthoringMeta';
import canEditTopics from '@salesforce/apex/HelpTopicAdminController.canEditTopics';
import addTopicApex from '@salesforce/apex/HelpTopicAdminController.addTopic';
import renameTopicApex from '@salesforce/apex/HelpTopicAdminController.renameTopic';
import reorderTopicsApex from '@salesforce/apex/HelpTopicAdminController.reorderTopics';
import { messageFrom, toast } from 'c/messageUtil';

/**
 * adminCategoryManager — the two taxonomies, side by side and clearly labeled,
 * both rendered by the shared c-admin-sortable-tree (drag/keyboard reorder):
 *  - Resource Categories (Resource_Category__c): editable — create, rename,
 *    re-parent, reorder (persists Display_Order__c), icon picker, active flag.
 *    Two levels: main topics with subtopics, mirroring Help topics.
 *  - Help Topics (Knowledge data categories): safe ops via the SOAP Metadata
 *    channel (HelpTopicAdminController) — add topic/subtopic, rename labels,
 *    reorder. Delete / API-name rename stay in Setup (they orphan article
 *    assignments). New topics show a generic icon on the Help Center until
 *    nexsTopicIcons.js gets a mapping (deploy).
 */
export default class AdminCategoryManager extends LightningElement {
    rows = [];
    helpTopics = [];
    loading = true;
    errorMessage;
    categoriesBusy = false;

    // Modal state (create/edit resource category)
    modalOpen = false;
    editingId = null;
    formName = '';
    formSlug = '';
    formIcon = '';
    formOrder;               // echoed on edit so saves don't jump position; drag owns order
    formParentId = '';
    formActive = true;
    slugTouched = false;
    slugError = '';

    // Help-topic editor state
    topicsEditable = false;
    topicsBusy = false;
    topicModalOpen = false;
    topicModalMode = 'add';      // 'add' | 'add-sub' | 'rename'
    topicModalTarget = null;     // parent name (add-sub) or topic name (rename)
    topicModalValue = '';

    connectedCallback() {
        this.load();
        canEditTopics()
            .then((editable) => {
                this.topicsEditable = editable === true;
            })
            .catch(() => {
                this.topicsEditable = false;
            });
    }

    async load() {
        this.loading = true;
        try {
            const [cats, meta] = await Promise.all([
                listCategories(),
                getAuthoringMeta().catch(() => null)
            ]);
            this.rows = (cats || []).map((c) => ({
                ...c,
                statusLabel: c.active ? 'Active' : 'Inactive',
                statusClass: c.active
                    ? 'acm-badge acm-badge--on'
                    : 'acm-badge acm-badge--off'
            }));
            this.helpTopics = meta ? meta.categoryTree : [];
            this.errorMessage = undefined;
        } catch (e) {
            this.errorMessage =
                (e && e.body && e.body.message) || 'Could not load categories.';
        } finally {
            this.loading = false;
        }
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get hasHelpTopics() {
        return this.helpTopics.length > 0;
    }

    get topicsSubtitle() {
        return this.topicsEditable
            ? 'Editable — add topics, rename labels, reorder. Organizes Help Center articles.'
            : 'Read-only — organizes Help Center articles. Editing needs Modify Metadata access.';
    }

    /** Two-level items for c-admin-sortable-tree, sorted like the server list. */
    get categoryItems() {
        const sortSiblings = (list) => [...list].sort((a, b) => {
            const ao = a.displayOrder == null ? Number.MAX_SAFE_INTEGER : a.displayOrder;
            const bo = b.displayOrder == null ? Number.MAX_SAFE_INTEGER : b.displayOrder;
            return ao - bo || a.name.localeCompare(b.name);
        });
        const toItem = (r) => ({
            key: r.id,
            label: r.name,
            sublabel: r.slug,
            badge: String(r.resourceCount),
            statusLabel: r.statusLabel,
            statusClass: r.statusClass,
            children: []
        });
        const tops = sortSiblings(this.rows.filter((r) => !r.parentId)).map(toItem);
        const topByKey = new Map(tops.map((t) => [t.key, t]));
        sortSiblings(this.rows.filter((r) => r.parentId)).forEach((r) => {
            const parent = topByKey.get(r.parentId);
            if (parent) {
                parent.children.push(toItem(r));
            } else {
                // Orphan (parent itself nested or missing) — keep it visible
                // and fixable rather than silently hiding it.
                tops.push(toItem(r));
            }
        });
        return tops;
    }

    get helpTopicItems() {
        return this.helpTopics.map((t) => ({
            key: t.name,
            label: t.label,
            children: (t.children || []).map((s) => ({ key: s.name, label: s.label }))
        }));
    }

    get topicModalTitle() {
        if (this.topicModalMode === 'rename') {
            return 'Rename topic';
        }
        return this.topicModalMode === 'add-sub' ? 'New subtopic' : 'New topic';
    }

    get topicModalInputLabel() {
        return this.topicModalMode === 'rename' ? 'New label' : 'Label';
    }

    get parentOptions() {
        const options = [{ label: 'None (top level)', value: '' }];
        this.rows
            .filter((c) => !c.parentId && c.id !== this.editingId)
            .forEach((c) => options.push({ label: c.name, value: c.id }));
        return options;
    }

    get editingHasChildren() {
        return Boolean(this.editingId)
            && this.rows.some((r) => r.parentId === this.editingId);
    }

    get parentDisabled() {
        return this.editingHasChildren;
    }

    get parentHelp() {
        return this.editingHasChildren
            ? 'This category has subtopics, so it must stay top level.'
            : 'Pick a main topic to file this category as its subtopic.';
    }

    get modalTitle() {
        if (this.editingId) {
            return 'Edit category';
        }
        return this.formParentId ? 'New subtopic' : 'New category';
    }

    handleRefresh() {
        this.load();
    }

    // ---- Modal -------------------------------------------------------------------

    handleNew() {
        this.editingId = null;
        this.formName = '';
        this.formSlug = '';
        this.formIcon = '';
        this.formOrder = undefined;
        this.formParentId = '';
        this.formActive = true;
        this.slugTouched = false;
        this.slugError = '';
        this.modalOpen = true;
    }

    /** "+" on a main topic: new category with the parent preset. */
    handleAddSubcategory(event) {
        this.handleNew();
        this.formParentId = event.detail.parentKey || '';
    }

    handleEdit(event) {
        const row = this.rows.find((c) => c.id === event.detail.key);
        if (!row) {
            return;
        }
        this.editingId = row.id;
        this.formName = row.name;
        this.formSlug = row.slug;
        this.formIcon = row.iconName || '';
        this.formOrder = row.displayOrder;
        this.formParentId = row.parentId || '';
        this.formActive = row.active;
        this.slugTouched = true;
        this.slugError = '';
        this.modalOpen = true;
    }

    handleModalCancel() {
        this.modalOpen = false;
    }

    handleNameChange(event) {
        this.formName = event.target.value;
        if (!this.editingId && !this.slugTouched) {
            this.formSlug = slugify(this.formName);
        }
    }

    handleSlugChange(event) {
        this.formSlug = event.target.value;
        this.slugTouched = true;
        this.slugError = '';
    }

    async handleSlugBlur() {
        const clean = slugify(this.formSlug);
        if (clean !== this.formSlug) {
            this.formSlug = clean;
        }
        if (!clean) {
            return;
        }
        try {
            const available = await isCategorySlugAvailable({
                slug: clean,
                excludeId: this.editingId || null
            });
            this.slugError = available
                ? ''
                : 'Another category already uses this slug — pick a different one.';
        } catch (e) {
            this.slugError = '';
        }
    }

    get iconOptions() {
        return categoryIconOptions().map((opt) => ({
            ...opt,
            selected: opt.value === this.formIcon,
            cssClass: opt.value === this.formIcon
                ? 'acm-icons__btn acm-icons__btn--selected'
                : 'acm-icons__btn'
        }));
    }
    get noIconSelected() {
        return !this.formIcon;
    }
    get noIconClass() {
        return this.noIconSelected
            ? 'acm-icons__btn acm-icons__btn--selected'
            : 'acm-icons__btn';
    }
    handleIconPick(event) {
        this.formIcon = event.currentTarget.dataset.value;
    }
    handleIconClear() {
        this.formIcon = '';
    }
    handleParentChange(event) {
        this.formParentId = event.detail.value;
    }
    handleActiveChange(event) {
        this.formActive = event.target.checked;
    }

    async handleModalSave() {
        if (!this.formName.trim() || !this.formSlug.trim()) {
            toast(this, 'error', 'Name and URL slug are required.');
            return;
        }
        if (this.slugError) {
            toast(this, 'error', this.slugError);
            return;
        }
        try {
            // JSON-string transport: custom-Apex-type @AuraEnabled params arrive
            // null/blank from LWC in this org. Order is owned by drag-reorder:
            // creates send null (server appends at the bottom of the sibling
            // list), edits echo the current order so the row keeps its place.
            await saveCategory({
                inputJson: JSON.stringify({
                    id: this.editingId || null,
                    name: this.formName,
                    slug: this.formSlug,
                    iconName: this.formIcon || null,
                    displayOrder: this.editingId ? this.formOrder : null,
                    parentId: this.formParentId || null,
                    active: this.formActive
                })
            });
            this.modalOpen = false;
            toast(this, 'success', 'Category saved.');
            this.load();
        } catch (e) {
            toast(this, 
                'error',
                (e && e.body && e.body.message) || 'Could not save the category.'
            );
        }
    }

    // ---- Resource-category reordering (persists Display_Order__c) ------------------

    /**
     * Apply the new order locally, then persist. Optimistic: the server
     * rejects the save unless the submitted Id set exactly matches the live
     * siblings, so a success means this order IS the persisted order. On
     * failure, reload to roll back to server truth.
     */
    async handleCategoryReorder(event) {
        const { parentKey, orderedKeys } = event.detail;
        const orderByKey = new Map(orderedKeys.map((k, i) => [k, i + 1]));
        this.rows = this.rows.map((r) =>
            orderByKey.has(r.id) ? { ...r, displayOrder: orderByKey.get(r.id) } : r
        );
        this.categoriesBusy = true;
        try {
            await reorderCategories({
                parentId: parentKey,
                orderedIdsJson: JSON.stringify(orderedKeys)
            });
        } catch (e) {
            toast(this, 'error', messageFrom(e, 'Could not reorder categories.'));
            await this.load();
        } finally {
            this.categoriesBusy = false;
        }
    }

    // ---- Help-topic editing (safe ops via the SOAP Metadata channel) ---------------

    handleTopicNew() {
        this.topicModalMode = 'add';
        this.topicModalTarget = null;
        this.topicModalValue = '';
        this.topicModalOpen = true;
    }

    handleSubtopicNew(event) {
        this.topicModalMode = 'add-sub';
        this.topicModalTarget = event.detail.parentKey;
        this.topicModalValue = '';
        this.topicModalOpen = true;
    }

    handleTopicRename(event) {
        this.topicModalMode = 'rename';
        this.topicModalTarget = event.detail.key;
        this.topicModalValue = event.detail.label || '';
        this.topicModalOpen = true;
    }

    handleTopicModalChange(event) {
        this.topicModalValue = event.target.value;
    }

    handleTopicModalCancel() {
        this.topicModalOpen = false;
    }

    async handleTopicModalSave() {
        const label = (this.topicModalValue || '').trim();
        if (!label) {
            toast(this, 'error', 'The label cannot be blank.');
            return;
        }
        this.topicsBusy = true;
        try {
            if (this.topicModalMode === 'rename') {
                await renameTopicApex({ name: this.topicModalTarget, newLabel: label });
                toast(this, 'success', 'Topic renamed.');
            } else {
                await addTopicApex({
                    parentName: this.topicModalMode === 'add-sub' ? this.topicModalTarget : null,
                    label
                });
                toast(this, 'success', 'Topic added — it is live for article filing now.');
            }
            this.topicModalOpen = false;
            await this.load();
        } catch (e) {
            toast(this, 'error', messageFrom(e, 'Could not update help topics.'));
        } finally {
            this.topicsBusy = false;
        }
    }

    /**
     * Optimistic help-topic reorder (see handleCategoryReorder for the
     * pattern; here a reload is also a slow Metadata API round trip, so
     * success skips it on purpose).
     */
    async handleTopicReorder(event) {
        const { parentKey, orderedKeys } = event.detail;
        const byName = new Map();
        (parentKey
            ? (this.helpTopics.find((t) => t.name === parentKey) || {}).children || []
            : this.helpTopics
        ).forEach((n) => byName.set(n.name, n));
        const reordered = orderedKeys.map((n) => byName.get(n));
        this.helpTopics = parentKey
            ? this.helpTopics.map((t) => (t.name === parentKey ? { ...t, children: reordered } : t))
            : reordered;
        this.topicsBusy = true;
        try {
            // JSON-string transport (org gotcha: non-primitive params arrive null).
            await reorderTopicsApex({
                parentName: parentKey,
                orderedNamesJson: JSON.stringify(orderedKeys)
            });
        } catch (e) {
            toast(this, 'error', messageFrom(e, 'Could not reorder help topics.'));
            await this.load();
        } finally {
            this.topicsBusy = false;
        }
    }

}