import { LightningElement, api } from 'lwc';
import getCaseList from '@salesforce/apex/UatCaseAdminController.getCaseList';
import getNextSequence from '@salesforce/apex/UatCaseAdminController.getNextSequence';
import saveCase from '@salesforce/apex/UatCaseAdminController.saveCase';
import moveCasesToModule from '@salesforce/apex/UatCaseAdminController.moveCasesToModule';
import getBooks from '@salesforce/apex/UatBookAdminController.getBooks';
import getTaxonomy from '@salesforce/apex/UatTaxonomyAdminController.getTaxonomy';
import { messageFrom, toast } from 'c/messageUtil';
import { TESTING_SURFACES, EXECUTION_STATUSES, toOptions, toFilterOptions, flattenModules } from 'c/uatConstants';
import { humanizeCaseCode, buildCaseCode } from 'c/uatTitleUtil';

/**
 * adminUatCases — the UAT Test Cases section of the Admin Console. Internal
 * view machine (adminAnalytics pattern): list <-> detail, with the New Case
 * modal (cascading taxonomy dropdowns, editable suggested sequence, live
 * Case ID preview mirroring the Case_ID__c formula).
 *
 * List columns Latest Run / Assigned / Status / Result are execution-derived
 * (live since the execution engine shipped); unscheduled cases read
 * "Not scheduled".
 *
 * The Test case column leads with Title__c and shows the Case_ID__c formula
 * beneath it — the formula alone is a long slug that reads as noise, and an
 * admin scanning the list is looking for the human name.
 */
const SURFACE_OPTIONS = toOptions(TESTING_SURFACES);

export default class AdminUatCases extends LightningElement {
    view = 'list'; // list | detail
    detailCaseId = null;
    detailExecutionId = null;
    originCycleId = null;
    originCycleName = null;

    /** Container-driven deep link (uatnavigate from a cycle's execution chip):
     *  open a case's detail viewing a specific run, with the cycle breadcrumb. */
    @api
    get openContext() {
        return null;
    }
    set openContext(value) {
        if (value && value.caseId) {
            this.detailCaseId = value.caseId;
            this.detailExecutionId = value.executionId || null;
            this.originCycleId = value.cycleId || null;
            this.originCycleName = value.cycleName || null;
            this.view = 'detail';
        }
    }

    rows = [];
    taxonomy = [];
    loading = true;
    errorMessage;

    searchTerm = '';
    systemFilter = '';
    statusFilter = '';
    showRetired = false; // list filter: retired cases hidden by default

    // New Case modal state: null when closed
    modal = null;
    saving = false;
    bookOptions = null; // lazy-loaded once for the "Add to book" picker

    // Bulk re-file. Selection is intersected with filteredRows at every read,
    // so a row scrolled out of view by a filter can never be moved by a
    // checkbox the admin can no longer see.
    selectedIds = [];
    bulkModuleId = '';
    confirm = null;

    connectedCallback() {
        this.load();
    }

    async load() {
        this.loading = true;
        try {
            const [rows, taxonomy] = await Promise.all([getCaseList(), getTaxonomy()]);
            this.rows = rows;
            this.taxonomy = taxonomy;
            this.errorMessage = undefined;
        } catch (e) {
            this.errorMessage = messageFrom(e);
        } finally {
            this.loading = false;
        }
    }

    // ---- View machine -------------------------------------------------------------

    get isList() {
        return this.view === 'list';
    }

    get isDetail() {
        return this.view === 'detail';
    }

    handleOpenDetail(event) {
        this.detailCaseId = event.currentTarget.dataset.id;
        this.detailExecutionId = null;
        this.originCycleId = null;
        this.originCycleName = null;
        this.view = 'detail';
    }

    handleDetailBack() {
        this.detailCaseId = null;
        this.detailExecutionId = null;
        this.originCycleId = null;
        this.originCycleName = null;
        this.view = 'list';
        this.load();
    }

    /** Breadcrumb "All Test Cycles / [Cycle]" from the detail page. */
    handleNavigateCycle(event) {
        this.dispatchEvent(new CustomEvent('uatnavigate', {
            detail: { section: 'uatCycles', view: 'editor', recordId: event.detail.cycleId }
        }));
    }

    // ---- List ----------------------------------------------------------------------

    get systemOptions() {
        return [{ label: 'All systems', value: '' }].concat(
            this.taxonomy.map((s) => ({ label: s.name, value: s.id }))
        );
    }

    get statusOptions() {
        // Filters the latest RUN's testing status, not Creation status —
        // the label says so now that both statuses are columns.
        return toFilterOptions('All run statuses', EXECUTION_STATUSES, '');
    }

    get filteredRows() {
        const term = (this.searchTerm || '').toLowerCase();
        const selected = new Set(this.selectedIds);
        return this.rows
            .filter((r) => {
                if (!this.showRetired && r.creationStatus === 'Retired') {
                    return false;
                }
                if (this.systemFilter && r.systemId !== this.systemFilter) {
                    return false;
                }
                if (this.statusFilter && r.testingStatus !== this.statusFilter) {
                    return false;
                }
                if (term) {
                    // Title is searchable now that it's the column's primary
                    // label — an admin who can read a title expects to find it.
                    const hay = ((r.title || '') + ' ' + (r.caseCode || '')
                        + ' ' + (r.moduleName || '')).toLowerCase();
                    if (!hay.includes(term)) {
                        return false;
                    }
                }
                return true;
            })
            .map((r) => ({
                ...r,
                selected: selected.has(r.id),
                selectLabel: 'Select ' + (r.title || r.caseCode),
                // Identity cell: the human title leads and the Case_ID__c
                // formula reads as secondary. Same headline expression the
                // tester surfaces use (uatQueue/uatPool/uatDashboard), so an
                // admin sees the label testers will see — including the
                // humanized fallback when Title__c is still blank.
                titleDisplay: r.title || humanizeCaseCode(r.caseCode),
                latestRunDisplay: r.latestRunLabel || '—',
                assignedDisplay: r.assignedLabel || 'Not scheduled',
                // Two distinct statuses on purpose: creationDisplay is the
                // definition's authoring progress (what the detail page's
                // Creation status control edits); statusDisplay is the
                // latest RUN's testing status. Same picklist words,
                // different records — keep both visible.
                creationDisplay: r.creationStatus || 'Draft',
                creationClass: r.creationStatus === 'Retired'
                    ? 'auc__creation auc__creation--retired' : 'auc__creation',
                statusDisplay: r.testingStatus || '—',
                resultDisplay: r.testingResult || '—'
            }));
    }

    get hasRows() {
        return this.filteredRows.length > 0;
    }

    get retiredCount() {
        return this.rows.filter((r) => r.creationStatus === 'Retired').length;
    }

    get hasRetiredRows() {
        return this.retiredCount > 0;
    }

    get showRetiredLabel() {
        return `Show retired (${this.retiredCount})`;
    }

    // ---- Bulk re-file -------------------------------------------------------------

    /** Only rows the admin can currently see count as selected — the checkbox
     *  is the promise, and a filter hiding a row withdraws it. */
    get selectedRows() {
        return this.filteredRows.filter((r) => r.selected);
    }

    get selectedCount() {
        return this.selectedRows.length;
    }

    get hasSelection() {
        return this.selectedCount > 0;
    }

    get selectedCountLabel() {
        return this.selectedCount === 1 ? '1 case selected' : `${this.selectedCount} cases selected`;
    }

    get allSelected() {
        const rows = this.filteredRows;
        return rows.length > 0 && rows.every((r) => r.selected);
    }

    get bulkModuleOptions() {
        return [{ label: 'Move to module…', value: '' }].concat(
            flattenModules(this.taxonomy).map((r) => ({ label: r.label, value: r.value }))
        );
    }

    get moveDisabled() {
        return this.saving || !this.hasSelection || !this.bulkModuleId;
    }

    handleToggleRow(event) {
        const id = event.currentTarget.dataset.id;
        const next = new Set(this.selectedIds);
        if (event.target.checked) {
            next.add(id);
        } else {
            next.delete(id);
        }
        this.selectedIds = [...next];
    }

    handleToggleAll(event) {
        this.selectedIds = event.target.checked ? this.filteredRows.map((r) => r.id) : [];
    }

    handleClearSelection() {
        this.selectedIds = [];
    }

    handleBulkModuleChange(event) {
        this.bulkModuleId = event.detail.value;
    }

    handleMoveClick() {
        const option = this.bulkModuleOptions.find((o) => o.value === this.bulkModuleId);
        const count = this.selectedCount;
        this.confirm = {
            variant: 'brand',
            header: `Move ${count} test ${count === 1 ? 'case' : 'cases'}`,
            message: `Re-files ${count === 1 ? 'this case' : 'these cases'} under `
                + `"${option ? option.label : 'that module'}". Each one is renumbered in `
                + 'the destination, so their Case IDs change. Test books, cycles and '
                + 'recorded runs are not affected.',
            confirmLabel: 'Move'
        };
    }

    get confirmOpen() {
        return this.confirm !== null;
    }

    handleConfirmCancel() {
        this.confirm = null;
    }

    async handleConfirmProceed() {
        this.saving = true;
        try {
            const moved = await moveCasesToModule({
                caseIds: this.selectedRows.map((r) => r.id),
                moduleId: this.bulkModuleId
            });
            this.confirm = null;
            this.selectedIds = [];
            this.bulkModuleId = '';
            toast(this, 'success', moved === 1
                ? 'Moved 1 test case.'
                : `Moved ${moved} test cases.`);
            await this.load();
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
        }
    }

    handleShowRetiredToggle(event) {
        this.showRetired = event.target.checked;
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
    }

    handleSystemFilterChange(event) {
        this.systemFilter = event.detail.value;
    }

    handleStatusFilterChange(event) {
        this.statusFilter = event.detail.value;
    }

    // ---- New Case modal ---------------------------------------------------------------

    async handleNewCase() {
        this.modal = {
            systemId: '',
            groupId: '',
            moduleId: '',
            version: 'v1.0',
            sequence: null,
            testingSurface: 'Lightning App (Internal)',
            targetBookId: ''
        };
        if (!this.bookOptions) {
            try {
                const books = await getBooks();
                this.bookOptions = [{ label: '— none —', value: '' }]
                    .concat(books.map((b) => ({ label: b.name, value: b.id })));
            } catch (e) {
                this.bookOptions = [{ label: '— none —', value: '' }];
            }
        }
    }

    get modalBookOptions() {
        return this.bookOptions || [{ label: '— none —', value: '' }];
    }

    handleModalBookChange(event) {
        this.modal = { ...this.modal, targetBookId: event.detail.value };
    }

    get surfaceOptions() {
        return SURFACE_OPTIONS;
    }

    get modalOpen() {
        return this.modal !== null;
    }

    get modalSystemOptions() {
        return this.taxonomy.map((s) => ({ label: s.name, value: s.id }));
    }

    get modalGroupOptions() {
        const sys = this.taxonomy.find((s) => s.id === this.modal.systemId);
        return sys ? sys.groups.map((g) => ({ label: g.name, value: g.id })) : [];
    }

    get modalModuleOptions() {
        const sys = this.taxonomy.find((s) => s.id === this.modal.systemId);
        const grp = sys ? sys.groups.find((g) => g.id === this.modal.groupId) : null;
        return grp ? grp.modules.map((m) => ({ label: m.name, value: m.id })) : [];
    }

    get groupDisabled() {
        return !this.modal.systemId;
    }

    get moduleDisabled() {
        return !this.modal.groupId;
    }

    /** Mirrors the Case_ID__c formula so the preview matches what saves. */
    get caseIdPreview() {
        const m = this.modal;
        const sys = this.taxonomy.find((s) => s.id === m.systemId);
        const grp = sys ? sys.groups.find((g) => g.id === m.groupId) : null;
        const mod = grp ? grp.modules.find((x) => x.id === m.moduleId) : null;
        return buildCaseCode({
            systemCode: sys ? sys.code : null,
            groupName: grp ? grp.name : null,
            moduleName: mod ? mod.name : null,
            version: m.version,
            sequence: m.sequence
        });
    }

    handleModalSystemChange(event) {
        this.modal = { ...this.modal, systemId: event.detail.value, groupId: '', moduleId: '', sequence: null };
    }

    handleModalGroupChange(event) {
        this.modal = { ...this.modal, groupId: event.detail.value, moduleId: '', sequence: null };
    }

    async handleModalModuleChange(event) {
        this.modal = { ...this.modal, moduleId: event.detail.value };
        try {
            const next = await getNextSequence({ moduleId: this.modal.moduleId });
            this.modal = { ...this.modal, sequence: next };
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        }
    }

    handleModalVersionChange(event) {
        this.modal = { ...this.modal, version: event.target.value };
    }

    handleModalSequenceChange(event) {
        this.modal = { ...this.modal, sequence: event.target.value };
    }

    handleModalSurfaceChange(event) {
        this.modal = { ...this.modal, testingSurface: event.detail.value };
    }

    handleModalCancel() {
        this.modal = null;
    }

    async handleModalCreate() {
        const m = this.modal;
        if (!m.moduleId) {
            toast(this, 'error', 'Pick a system, module group, and module.');
            return;
        }
        if (!m.version || !m.version.trim()) {
            toast(this, 'error', 'Version is required.');
            return;
        }
        this.saving = true;
        try {
            // Serialized to JSON: custom-Apex-type @AuraEnabled params arrive
            // null/blank from LWC in this org.
            const caseId = await saveCase({
                inputJson: JSON.stringify({
                    moduleId: m.moduleId,
                    version: m.version,
                    sequence: m.sequence === '' ? null : m.sequence,
                    testingSurface: m.testingSurface,
                    creationStatus: 'Draft',
                    targetBookId: m.targetBookId || null
                })
            });
            this.modal = null;
            toast(this, 'success', 'Test case created.');
            // Land directly on the detail page, per spec.
            this.detailCaseId = caseId;
            this.view = 'detail';
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
        }
    }

    // ---- Internals -----------------------------------------------------------------------

}