import { LightningElement } from 'lwc';
import { slugify } from 'c/slugUtil';
import { categoryIconOptions } from 'c/rcIcons';
import { indexTree, findNode, applyMove, optionsFor } from 'c/treeUtil';
import getCategoryTree from '@salesforce/apex/ResourceAdminController.getCategoryTree';
import saveCategory from '@salesforce/apex/ResourceAdminController.saveCategory';
import moveCategory from '@salesforce/apex/ResourceAdminController.moveCategory';
import isCategorySlugAvailable from '@salesforce/apex/ResourceAdminController.isCategorySlugAvailable';
import getHelpTopicTree from '@salesforce/apex/NexSKnowledgeController.getCategoryTree';
import canEditTopics from '@salesforce/apex/HelpTopicAdminController.canEditTopics';
import addTopicApex from '@salesforce/apex/HelpTopicAdminController.addTopic';
import renameTopicApex from '@salesforce/apex/HelpTopicAdminController.renameTopic';
import moveTopicApex from '@salesforce/apex/HelpTopicAdminController.moveTopic';
import getCategoryDeleteImpact from '@salesforce/apex/ResourceAdminController.getCategoryDeleteImpact';
import deleteCategoryApex from '@salesforce/apex/ResourceAdminController.deleteCategory';
import getTopicDeleteImpact from '@salesforce/apex/HelpTopicAdminController.getTopicDeleteImpact';
import deleteTopicApex from '@salesforce/apex/HelpTopicAdminController.deleteTopic';
import { messageFrom, toast } from 'c/messageUtil';

const plural = (n, one, many) => (n === 1 ? one : many);
const MODE_REPARENT = 'reparent';
const MODE_BLOCK = 'block';
const CHOICE_KEEP = 'keep';

/**
 * adminCategoryManager — the two taxonomies, side by side and clearly labeled,
 * both rendered by the shared c-admin-tree-editor (any depth up to the limit
 * the server sends with each tree; never hard-coded here):
 *  - Resource Categories (Resource_Category__c): create anywhere, rename
 *    (inline or in the dialog), re-parent by drag or from the dialog's parent
 *    picker (which only offers parents the subtree fits under), reorder
 *    (moveCategory persists parent + Display_Order__c in one call), icon
 *    picker, active flag, delete.
 *  - Help Topics (Knowledge data categories): via the SOAP Metadata channel
 *    (HelpTopicAdminController) — add under any topic, rename labels, move,
 *    reorder, delete. API-name rename stays in Setup. New topics show a
 *    generic icon on the Help Center until nexsTopicIcons.js gets a mapping.
 *
 * Delete never cascades. It lives in each edit dialog and always goes through
 * the shared c-admin-confirm-modal: the dialog closes, a pre-flight impact
 * call decides between a "blocked" notice (content on the node itself, or
 * content below a childless node) and a confirm; a node WITH subtopics asks
 * the admin to choose — move the subtopics up to its parent, or keep the
 * node until it is emptied — and the server re-validates the chosen mode.
 */
export default class AdminCategoryManager extends LightningElement {
    categoryRoots = [];
    categoryMaxDepth = 5;
    _categoryTree = indexTree([]);
    helpRoots = [];
    helpMaxDepth = 5;
    _helpTree = indexTree([]);
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

    // Delete confirm state: null, or { action: 'blocked'|'delete', kind:
    // 'category'|'topic', id, header, message, confirmLabel, variant,
    // choices?, choice?, mode }.
    confirm = null;
    confirmBusy = false;

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

    /**
     * quiet = refresh in place: no spinner, so a drag's optimistic tree stays
     * on screen while the server answer (fresh order values, paths, counts)
     * is fetched. A blanked pane after every move would read as a flicker.
     */
    async load(quiet = false) {
        this.loading = !quiet;
        try {
            const [cats, topics] = await Promise.all([
                getCategoryTree(),
                getHelpTopicTree().catch(() => null)
            ]);
            this.setCategoryTree(cats);
            this.helpRoots = topics ? topics.roots || [] : [];
            this.helpMaxDepth = topics && topics.maxDepth ? topics.maxDepth : 5;
            this._helpTree = indexTree(this.helpRoots);
            this.errorMessage = undefined;
        } catch (e) {
            this.errorMessage = messageFrom(e, 'Could not load categories.');
        } finally {
            this.loading = false;
        }
    }

    setCategoryTree(dto) {
        this.categoryRoots = dto ? dto.roots || [] : [];
        this.categoryMaxDepth = dto && dto.maxDepth ? dto.maxDepth : 5;
        this._categoryTree = indexTree(this.categoryRoots);
    }

    get hasCategories() {
        return this.categoryRoots.length > 0;
    }

    get hasHelpTopics() {
        return this.helpRoots.length > 0;
    }

    get topicsSubtitle() {
        return this.topicsEditable
            ? `Editable — add, rename, move and reorder topics up to ${this.helpMaxDepth} levels deep. Organizes Help Center articles.`
            : 'Read-only — organizes Help Center articles. Editing needs Modify Metadata access.';
    }

    get confirmOpen() {
        return this.confirm !== null;
    }

    get isEditingCategory() {
        return Boolean(this.editingId);
    }

    get topicModalIsRename() {
        return this.topicModalMode === 'rename';
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

    /** Any category the edited one (with its subtree) fits under — never itself
        or its own descendants, never deeper than the limit allows. */
    get parentOptions() {
        const options = [{ label: 'None (top level)', value: '' }];
        optionsFor(this._categoryTree, this.editingId, this.categoryMaxDepth).forEach((o) => {
            options.push({ label: o.label, value: o.value });
        });
        return options;
    }

    get parentHelp() {
        return `Pick any category to file this one under it — up to ${this.categoryMaxDepth} levels deep. `
            + 'Moving a category takes its subtopics with it.';
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

    /** "+" on any node: new category with the parent preset. */
    handleAddSubcategory(event) {
        this.handleNew();
        this.formParentId = event.detail.parentKey || '';
    }

    handleEdit(event) {
        const node = findNode(this._categoryTree, event.detail.key);
        if (!node) {
            return;
        }
        this.editingId = node.id;
        this.formName = node.label;
        this.formSlug = node.slug;
        this.formIcon = node.iconName || '';
        this.formOrder = node.displayOrder;
        this.formParentId = node.parentId || '';
        this.formActive = node.active !== false;
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
            toast(this, 'error', messageFrom(e, 'Could not save the category.'));
        }
    }

    /** Inline rename from the tree: everything else on the record is echoed. */
    async handleCategoryRename(event) {
        const node = findNode(this._categoryTree, event.detail.key);
        if (!node) {
            return;
        }
        this.categoriesBusy = true;
        try {
            await saveCategory({
                inputJson: JSON.stringify({
                    id: node.id,
                    name: event.detail.label,
                    slug: node.slug,
                    iconName: node.iconName || null,
                    displayOrder: node.displayOrder,
                    parentId: node.parentId || null,
                    active: node.active !== false
                })
            });
            toast(this, 'success', 'Category renamed.');
            await this.load();
        } catch (e) {
            toast(this, 'error', messageFrom(e, 'Could not rename the category.'));
        } finally {
            this.categoriesBusy = false;
        }
    }

    // ---- Resource-category moves (reorder or re-parent; persists both) ------------

    /**
     * Apply the move locally, then persist. Optimistic: the server rejects the
     * save unless the submitted sibling set exactly matches the live one, so a
     * success means this tree IS the persisted tree; reload afterwards for the
     * fresh order values and counts. On failure, reload to roll back.
     */
    async handleCategoryMove(event) {
        const { key, newParentKey, orderedSiblingKeys } = event.detail;
        const moved = applyMove(this._categoryTree, key, newParentKey, orderedSiblingKeys);
        this._categoryTree = moved;
        this.categoryRoots = moved.roots;
        this.categoriesBusy = true;
        try {
            await moveCategory({
                categoryId: key,
                newParentId: newParentKey,
                orderedSiblingIdsJson: JSON.stringify(orderedSiblingKeys)
            });
        } catch (e) {
            toast(this, 'error', messageFrom(e, 'Could not move the category.'));
        } finally {
            this.categoriesBusy = false;
            await this.load(true);
        }
    }

    // ---- Help-topic editing (via the SOAP Metadata channel) --------------------------

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

    /** Inline rename from the tree (display label only, like the dialog). */
    async handleTopicInlineRename(event) {
        this.topicsBusy = true;
        try {
            await renameTopicApex({ name: event.detail.key, newLabel: event.detail.label });
            toast(this, 'success', 'Topic renamed.');
            await this.load();
        } catch (e) {
            toast(this, 'error', messageFrom(e, 'Could not rename the topic.'));
        } finally {
            this.topicsBusy = false;
        }
    }

    /**
     * Optimistic help-topic move (see handleCategoryMove for the pattern; a
     * reload here is a slow Metadata API round trip, so success skips it).
     */
    async handleTopicMove(event) {
        const { key, newParentKey, orderedSiblingKeys } = event.detail;
        const moved = applyMove(this._helpTree, key, newParentKey, orderedSiblingKeys);
        this._helpTree = moved;
        this.helpRoots = moved.roots;
        this.topicsBusy = true;
        try {
            // JSON-string transport (org gotcha: non-primitive params arrive null).
            await moveTopicApex({
                name: key,
                newParentName: newParentKey,
                orderedNamesJson: JSON.stringify(orderedSiblingKeys)
            });
        } catch (e) {
            toast(this, 'error', messageFrom(e, 'Could not move the topic.'));
            await this.load(true);
        } finally {
            this.topicsBusy = false;
        }
    }

    // ---- Delete (both panes; blocked notice, plain confirm, or a choice) ---------

    /**
     * Delete from the category edit dialog. The dialog closes first (two
     * overlays would fight over focus and Escape); its form state stays so
     * Cancel or the blocked "OK" reopens it exactly as it was.
     */
    async handleCategoryDeleteClick() {
        const node = findNode(this._categoryTree, this.editingId);
        if (!node) {
            return;
        }
        this.modalOpen = false;
        this.categoriesBusy = true;
        try {
            const impact = await getCategoryDeleteImpact({ categoryId: node.id });
            this.confirm = this.buildCategoryConfirm(node, impact);
        } catch (e) {
            toast(this, 'error', messageFrom(e, 'Could not check the category.'));
            this.modalOpen = true;
        } finally {
            this.categoriesBusy = false;
        }
    }

    buildCategoryConfirm(node, impact) {
        const name = impact.name || node.label;
        const subs = impact.childCount || 0;
        const base = { kind: 'category', id: node.id };
        const blocked = (message) => ({
            ...base, action: 'blocked', variant: 'brand', header: `Can't delete: ${name}`,
            message, confirmLabel: 'OK'
        });
        // Content on the node itself blocks either way.
        if (impact.ownResourceCount > 0) {
            const n = impact.ownResourceCount;
            return blocked(`${n} resource${plural(n, ' lives', 's live')} in this category. `
                + 'Move or delete those resources first.');
        }
        if (impact.ownSecondaryCount > 0) {
            const n = impact.ownSecondaryCount;
            return blocked(`${n} resource${plural(n, ' is', 's are')} also shown in this category. `
                + 'Remove it from those resources first.');
        }
        if (impact.ownGuideOptionCount > 0) {
            const n = impact.ownGuideOptionCount;
            return blocked(`${n} help guide option${plural(n, ' links', 's link')} to this category. `
                + `Retarget or remove ${plural(n, 'it', 'them')} in the Help Guide Builder first.`);
        }
        if (subs === 0) {
            return {
                ...base, action: 'delete', mode: MODE_BLOCK,
                header: `Delete category: ${name}`,
                message: 'Deletes this category. No resources live under it or are shown in it. '
                    + 'This cannot be undone.',
                confirmLabel: 'Delete'
            };
        }
        // Has subtopics: never a cascade — the admin chooses.
        const where = impact.parentName ? `up to ${impact.parentName}` : 'up to the top level';
        const below = [];
        if (impact.resourceCount > 0) {
            below.push(`${impact.resourceCount} resource${plural(impact.resourceCount, '', 's')}`);
        }
        if (impact.secondaryCount > 0) {
            below.push(`${impact.secondaryCount} "also shown in" placement${plural(impact.secondaryCount, '', 's')}`);
        }
        if (impact.guideOptionCount > 0) {
            below.push(`${impact.guideOptionCount} help guide link${plural(impact.guideOptionCount, '', 's')}`);
        }
        const deeper = (impact.descendantCount || 0) - subs;
        return {
            ...base, action: 'delete', mode: MODE_REPARENT,
            header: `Delete category: ${name}`,
            message: `This category has ${subs} subtopic${plural(subs, '', 's')}`
                + `${deeper > 0 ? ` (${deeper} more below them)` : ''}`
                + `${below.length ? `, holding ${below.join(', ')}` : ''}. `
                + 'Nothing is deleted with it: the subtopics keep their content. This cannot be undone.',
            confirmLabel: 'Continue',
            choices: [
                { label: `Move the subtopics ${where}, then delete "${name}"`, value: MODE_REPARENT },
                { label: `Keep "${name}" — I'll empty it first`, value: CHOICE_KEEP }
            ]
        };
    }

    /** Delete from the topic Rename dialog; same close-then-confirm choreography. */
    async handleTopicDeleteClick() {
        const name = this.topicModalTarget;
        if (!name) {
            return;
        }
        this.topicModalOpen = false;
        this.topicsBusy = true;
        try {
            const impact = await getTopicDeleteImpact({ name });
            this.confirm = this.buildTopicConfirm(name, impact);
        } catch (e) {
            toast(this, 'error', messageFrom(e, 'Could not check the topic.'));
            this.topicModalOpen = true;
        } finally {
            this.topicsBusy = false;
        }
    }

    buildTopicConfirm(name, impact) {
        const label = impact.label || this.topicModalValue || name;
        const subs = impact.childCount || 0;
        const base = { kind: 'topic', id: name };
        if (impact.ownArticleCount > 0) {
            const n = impact.ownArticleCount;
            return {
                ...base, action: 'blocked', variant: 'brand',
                header: `Can't delete: ${label}`,
                message: `${n} article version${plural(n, ' is', 's are')} filed on this topic `
                    + '(drafts and archived versions included). Move those articles to another topic first.',
                confirmLabel: 'OK'
            };
        }
        if (subs === 0) {
            if (impact.articleCount > 0) {
                const n = impact.articleCount;
                return {
                    ...base, action: 'blocked', variant: 'brand',
                    header: `Can't delete: ${label}`,
                    message: `${n} article version${plural(n, ' is', 's are')} filed under this topic `
                        + '(drafts and archived versions included). Move those articles to another topic first.',
                    confirmLabel: 'OK'
                };
            }
            return {
                ...base, action: 'delete', mode: MODE_BLOCK,
                header: `Delete topic: ${label}`,
                message: 'Removes this topic from the Help Topics group. No articles are filed under it. '
                    + 'This cannot be undone.',
                confirmLabel: 'Delete'
            };
        }
        const where = impact.parentLabel ? `up to ${impact.parentLabel}` : 'up to the top level';
        const filed = impact.articleCount > 0
            ? `, with ${impact.articleCount} article version${plural(impact.articleCount, '', 's')} filed under them`
            : '';
        return {
            ...base, action: 'delete', mode: MODE_REPARENT,
            header: `Delete topic: ${label}`,
            message: `This topic has ${subs} subtopic${plural(subs, '', 's')}${filed}. `
                + 'Nothing is removed with it: the subtopics keep their articles. This cannot be undone.',
            confirmLabel: 'Continue',
            choices: [
                { label: `Move the subtopics ${where}, then delete "${label}"`, value: MODE_REPARENT },
                { label: `Keep "${label}" — I'll empty it first`, value: CHOICE_KEEP }
            ]
        };
    }

    /** Cancel (or the blocked notice's OK) returns to the dialog it came from. */
    handleConfirmCancel() {
        const pending = this.confirm;
        this.confirm = null;
        if (!pending) {
            return;
        }
        if (pending.kind === 'category') {
            this.modalOpen = true;
        } else {
            this.topicModalOpen = true;
        }
    }

    async handleConfirmProceed(event) {
        const pending = this.confirm;
        if (!pending || pending.action !== 'delete') {
            this.handleConfirmCancel();
            return;
        }
        const choice = event && event.detail ? event.detail.choice : undefined;
        if (pending.choices && choice === CHOICE_KEEP) {
            this.handleConfirmCancel();
            return;
        }
        const mode = pending.choices ? (choice || pending.mode) : pending.mode;
        const isCategory = pending.kind === 'category';
        this.confirmBusy = true;
        if (isCategory) {
            this.categoriesBusy = true;
        } else {
            this.topicsBusy = true;
        }
        try {
            if (isCategory) {
                await deleteCategoryApex({ categoryId: pending.id, mode });
            } else {
                await deleteTopicApex({ name: pending.id, mode });
            }
            this.confirm = null;
            toast(this, 'success', isCategory ? 'Category deleted.' : 'Topic deleted.');
            await this.load();
        } catch (e) {
            // Keep the confirm open so the admin reads why and can back out.
            toast(this, 'error', messageFrom(e, 'Could not delete.'));
        } finally {
            this.confirmBusy = false;
            this.categoriesBusy = false;
            this.topicsBusy = false;
        }
    }
}