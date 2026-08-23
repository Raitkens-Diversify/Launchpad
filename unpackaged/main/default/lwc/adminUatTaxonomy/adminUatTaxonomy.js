import { LightningElement } from 'lwc';
import getTaxonomy from '@salesforce/apex/UatTaxonomyAdminController.getTaxonomy';
import saveSystem from '@salesforce/apex/UatTaxonomyAdminController.saveSystem';
import saveModuleGroup from '@salesforce/apex/UatTaxonomyAdminController.saveModuleGroup';
import saveModule from '@salesforce/apex/UatTaxonomyAdminController.saveModule';
import getTaxonomyDeleteImpact from '@salesforce/apex/UatTaxonomyAdminController.getTaxonomyDeleteImpact';
import deleteSystem from '@salesforce/apex/UatTaxonomyAdminController.deleteSystem';
import deleteModuleGroup from '@salesforce/apex/UatTaxonomyAdminController.deleteModuleGroup';
import deleteModule from '@salesforce/apex/UatTaxonomyAdminController.deleteModule';
import getGroupBookPreview from '@salesforce/apex/UatBookAdminController.getGroupBookPreview';
import createBookFromModuleGroup from '@salesforce/apex/UatBookAdminController.createBookFromModuleGroup';
import { messageFrom, toast } from 'c/messageUtil';

/**
 * adminUatTaxonomy — the UAT Taxonomy section of the Admin Console: a
 * three-column cascading browser (Systems -> Module Groups -> Modules) with
 * "+ New" / "Edit" / "Delete" per column, following adminCategoryManager's
 * pane + inline modal conventions. Selection filters the next column. Delete
 * (2026-08-05, superseding the old deferred decision): a node deletes only
 * when no test case lives under it — the impact fetch turns that into a
 * blocked dialog; empty descendants cascade and the confirm counts them.
 *
 * One getTaxonomy() payload holds the whole tree; columns filter client-side.
 */
const LEVELS = {
    system: {
        title: 'New system', editTitle: 'Edit system', noun: 'system',
        save: saveSystem, remove: deleteSystem
    },
    group: {
        title: 'New module group', editTitle: 'Edit module group', noun: 'module group',
        save: saveModuleGroup, remove: deleteModuleGroup
    },
    module: {
        title: 'New module', editTitle: 'Edit module', noun: 'module',
        save: saveModule, remove: deleteModule
    }
};

export default class AdminUatTaxonomy extends LightningElement {
    systems = [];
    loading = true;
    errorMessage;

    selectedSystemId = null;
    selectedGroupId = null;

    // Inline modal state: null when closed, else { level, id, parentId, ... }
    modal = null;
    saving = false;

    // Delete confirm: null when closed, else { action, level, id, ... }
    confirm = null;

    // Create-book-from-group modal: null when closed
    bookModal = null;

    connectedCallback() {
        this.load();
    }

    async load() {
        this.loading = true;
        try {
            this.systems = await getTaxonomy();
            this.errorMessage = undefined;
            // Selections can go stale after a reload (edited names re-sort).
            if (this.selectedSystemId && !this.findSystem(this.selectedSystemId)) {
                this.selectedSystemId = null;
                this.selectedGroupId = null;
            }
            if (this.selectedGroupId && !this.findGroup(this.selectedGroupId)) {
                this.selectedGroupId = null;
            }
        } catch (e) {
            this.errorMessage = messageFrom(e);
        } finally {
            this.loading = false;
        }
    }

    // ---- Derived state ----------------------------------------------------------

    get busy() {
        return this.loading || this.saving;
    }

    get systemRows() {
        return this.systems.map((s) => ({
            ...s,
            rowClass: s.id === this.selectedSystemId ? 'aut__row aut__row--active' : 'aut__row',
            sublabel: s.code
        }));
    }

    get selectedSystem() {
        return this.findSystem(this.selectedSystemId);
    }

    get selectedGroup() {
        return this.findGroup(this.selectedGroupId);
    }

    get groupRows() {
        const sys = this.selectedSystem;
        if (!sys) {
            return [];
        }
        return sys.groups.map((g) => ({
            ...g,
            rowClass: g.id === this.selectedGroupId ? 'aut__row aut__row--active' : 'aut__row'
        }));
    }

    get moduleRows() {
        const grp = this.selectedGroup;
        return grp ? grp.modules.map((m) => ({ ...m, rowClass: 'aut__row aut__row--static' })) : [];
    }

    get hasSystems() {
        return this.systemRows.length > 0;
    }

    get hasGroups() {
        return this.groupRows.length > 0;
    }

    get hasModules() {
        return this.moduleRows.length > 0;
    }

    get groupsDisabled() {
        return !this.selectedSystemId;
    }

    get modulesDisabled() {
        return !this.selectedGroupId;
    }

    get groupsEmptyText() {
        return this.selectedSystemId
            ? 'No module groups in this system yet.'
            : 'Select a system to see its module groups.';
    }

    get modulesEmptyText() {
        return this.selectedGroupId
            ? 'No modules in this group yet.'
            : 'Select a module group to see its modules.';
    }

    get modalOpen() {
        return this.modal !== null;
    }

    get modalTitle() {
        if (!this.modal) {
            return '';
        }
        const level = LEVELS[this.modal.level];
        return this.modal.id ? level.editTitle : level.title;
    }

    get modalIsSystem() {
        return this.modal && this.modal.level === 'system';
    }

    // ---- Selection ---------------------------------------------------------------

    handleSystemSelect(event) {
        this.selectedSystemId = event.currentTarget.dataset.id;
        this.selectedGroupId = null;
    }

    handleGroupSelect(event) {
        this.selectedGroupId = event.currentTarget.dataset.id;
    }

    // ---- Modal open/close ----------------------------------------------------------

    handleNewSystem() {
        this.modal = { level: 'system', id: null, parentId: null, name: '', code: '', description: '' };
    }

    handleNewGroup() {
        this.modal = { level: 'group', id: null, parentId: this.selectedSystemId, name: '', description: '' };
    }

    handleNewModule() {
        this.modal = { level: 'module', id: null, parentId: this.selectedGroupId, name: '', description: '' };
    }

    handleEditSystem(event) {
        event.stopPropagation();
        const s = this.findSystem(event.currentTarget.dataset.id);
        this.modal = { level: 'system', id: s.id, parentId: null, name: s.name, code: s.code, description: s.description || '' };
    }

    handleEditGroup(event) {
        event.stopPropagation();
        const g = this.findGroup(event.currentTarget.dataset.id);
        this.modal = { level: 'group', id: g.id, parentId: null, name: g.name, description: g.description || '' };
    }

    handleEditModule(event) {
        event.stopPropagation();
        const m = this.findModule(event.currentTarget.dataset.id);
        this.modal = { level: 'module', id: m.id, parentId: null, name: m.name, description: m.description || '' };
    }

    handleModalCancel() {
        this.modal = null;
    }

    // ---- Create book from module group ------------------------------------------------

    get bookModalOpen() {
        return this.bookModal !== null;
    }

    get bookModalCopy() {
        const m = this.bookModal;
        if (!m) {
            return '';
        }
        if (m.completeCaseCount === 0) {
            return `No Complete test cases live under "${m.groupName}" yet — finish some `
                + 'case definitions first, or create an empty book from the Books section.';
        }
        const skipped = m.totalCaseCount - m.completeCaseCount;
        return `Adds all ${m.completeCaseCount} Complete test case${m.completeCaseCount === 1 ? '' : 's'} `
            + `under "${m.groupName}", in Case ID order.`
            + (skipped > 0 ? ` ${skipped} draft/retired case${skipped === 1 ? ' is' : 's are'} skipped.` : '');
    }

    get bookCreateDisabled() {
        return this.saving || !this.bookModal || this.bookModal.completeCaseCount === 0;
    }

    async handleCreateBookClick(event) {
        event.stopPropagation();
        const groupId = event.currentTarget.dataset.id;
        this.saving = true;
        try {
            const preview = await getGroupBookPreview({ groupId });
            this.bookModal = {
                groupId,
                groupName: preview.groupName,
                name: preview.groupName,
                completeCaseCount: preview.completeCaseCount,
                totalCaseCount: preview.totalCaseCount
            };
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
        }
    }

    handleBookNameChange(event) {
        this.bookModal = { ...this.bookModal, name: event.target.value };
    }

    handleBookModalCancel() {
        this.bookModal = null;
    }

    async handleBookModalCreate() {
        const m = this.bookModal;
        if (!m.name || !m.name.trim()) {
            toast(this, 'error', 'Give the book a name.');
            return;
        }
        this.saving = true;
        try {
            const bookId = await createBookFromModuleGroup({
                groupId: m.groupId, bookName: m.name
            });
            this.bookModal = null;
            toast(this, 'success', `Book "${m.name.trim()}" created with ${m.completeCaseCount} case${m.completeCaseCount === 1 ? '' : 's'}.`);
            this.dispatchEvent(new CustomEvent('uatnavigate', {
                detail: { section: 'uatBooks', recordId: bookId }
            }));
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
        }
    }

    // ---- Delete ---------------------------------------------------------------------

    get confirmOpen() {
        return this.confirm !== null;
    }

    handleDeleteSystem(event) {
        event.stopPropagation();
        this.openDeleteConfirm('system', event.currentTarget.dataset.id,
            this.findSystem(event.currentTarget.dataset.id));
    }

    handleDeleteGroup(event) {
        event.stopPropagation();
        this.openDeleteConfirm('group', event.currentTarget.dataset.id,
            this.findGroup(event.currentTarget.dataset.id));
    }

    handleDeleteModule(event) {
        event.stopPropagation();
        this.openDeleteConfirm('module', event.currentTarget.dataset.id,
            this.findModule(event.currentTarget.dataset.id));
    }

    async openDeleteConfirm(level, nodeId, node) {
        const noun = LEVELS[level].noun;
        this.saving = true;
        try {
            const impact = await getTaxonomyDeleteImpact({ level, nodeId });
            if (impact.caseCount > 0) {
                this.confirm = {
                    action: 'blocked',
                    variant: 'brand',
                    header: `Can't delete: ${node.name}`,
                    message: `${impact.caseCount} test case${impact.caseCount === 1 ? ' lives' : 's live'} `
                        + `under this ${noun}. Delete or move those cases first.`,
                    confirmLabel: 'OK'
                };
            } else {
                const children = [];
                if (impact.groupCount > 0) {
                    children.push(`${impact.groupCount} module group${impact.groupCount === 1 ? '' : 's'}`);
                }
                if (impact.moduleCount > 0) {
                    children.push(`${impact.moduleCount} module${impact.moduleCount === 1 ? '' : 's'}`);
                }
                this.confirm = {
                    action: 'delete',
                    level,
                    id: nodeId,
                    header: `Delete ${noun}: ${node.name}`,
                    message: (children.length
                        ? `Deletes this ${noun} and its ${children.join(' and ')} (all empty). `
                        : `Deletes this ${noun}. `)
                        + 'No test cases exist under it. This cannot be undone.',
                    confirmLabel: 'Delete'
                };
            }
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
        }
    }

    handleConfirmCancel() {
        this.confirm = null;
    }

    async handleConfirmProceed() {
        const c = this.confirm;
        if (c.action === 'blocked') {
            this.confirm = null;
            return;
        }
        this.saving = true;
        try {
            await LEVELS[c.level].remove(this.deleteArgs(c.level, c.id));
            if (c.level === 'system' && this.selectedSystemId === c.id) {
                this.selectedSystemId = null;
                this.selectedGroupId = null;
            } else if (c.level === 'group' && this.selectedGroupId === c.id) {
                this.selectedGroupId = null;
            }
            this.confirm = null;
            toast(this, 'success', 'Deleted.');
            await this.load();
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
        }
    }

    deleteArgs(level, id) {
        if (level === 'system') {
            return { systemId: id };
        }
        if (level === 'group') {
            return { groupId: id };
        }
        return { moduleId: id };
    }

    // ---- Modal form -----------------------------------------------------------------

    handleNameChange(event) {
        this.modal = { ...this.modal, name: event.target.value };
    }

    handleCodeChange(event) {
        this.modal = { ...this.modal, code: event.target.value };
    }

    handleDescriptionChange(event) {
        this.modal = { ...this.modal, description: event.target.value };
    }

    async handleModalSave() {
        const m = this.modal;
        if (!m || !m.name || !m.name.trim()) {
            toast(this, 'error', 'Name is required.');
            return;
        }
        if (m.level === 'system' && (!m.code || !m.code.trim())) {
            toast(this, 'error', 'System code is required — it becomes part of every Case ID.');
            return;
        }
        this.saving = true;
        try {
            // Serialized to JSON: custom-Apex-type @AuraEnabled params arrive
            // null/blank from LWC in this org.
            const inputJson = JSON.stringify({
                id: m.id,
                name: m.name,
                code: m.code,
                description: m.description,
                parentId: m.parentId
            });
            const savedId = await LEVELS[m.level].save({ inputJson });
            // Keep the browser focused on what was just touched.
            if (m.level === 'system' && !m.id) {
                this.selectedSystemId = savedId;
                this.selectedGroupId = null;
            } else if (m.level === 'group' && !m.id) {
                this.selectedGroupId = savedId;
            }
            this.modal = null;
            toast(this, 'success', 'Saved.');
            await this.load();
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
        }
    }

    // ---- Internals --------------------------------------------------------------------

    findSystem(id) {
        return this.systems.find((s) => s.id === id) || null;
    }

    findGroup(id) {
        for (const s of this.systems) {
            const g = s.groups.find((x) => x.id === id);
            if (g) {
                return g;
            }
        }
        return null;
    }

    findModule(id) {
        for (const s of this.systems) {
            for (const g of s.groups) {
                const m = g.modules.find((x) => x.id === id);
                if (m) {
                    return m;
                }
            }
        }
        return null;
    }

}