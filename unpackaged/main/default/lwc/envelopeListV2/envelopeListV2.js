import { LightningElement, track } from 'lwc';
import LightningToast from 'lightning/toast';
import getWizEnvelopes from '@salesforce/apex/EnvelopeLandingApex.getWizEnvelopes';
import getAllFormSchemas from '@salesforce/apex/FieldDetailController.getAllFormSchemas';
import getRegistrationTypeAttributes from '@salesforce/apex/EnvelopeISAController.getRegistrationTypeAttributes';
import getUserPreferences from '@salesforce/apex/WizardEnvelopeStateService.getUserPreferences';
import EMPTY_ENVELOPE from '@salesforce/resourceUrl/EmptyEnvelopeV2';
import ENVELOPE_NO_RESULTS from '@salesforce/resourceUrl/EnvelopeNoResults';
import {
    formatEnvelopeContentsLabel,
    missingInputsCountLabel,
    sumMissingInputs
} from 'c/envelopeFormSchema';

// Column config for c-ds-data-table-v2 (custom styled <table>). `wrapText` lets
// long names wrap; the whole row is clickable (see handleRowClick).
const COLUMNS = [
    { label: 'Envelope Name', fieldName: 'name', type: 'text', sortable: true, wrapText: true, primary: true },
    { label: 'Household', fieldName: 'household', type: 'text', sortable: true, wrapText: true },
    { label: 'Financial Advisor Team', fieldName: 'advisorTeam', type: 'text', sortable: true, wrapText: true },
    { label: 'Created', fieldName: 'created', type: 'text', sortable: true, sortFieldName: 'createdRaw', sortType: 'date', wrapText: true },
    { label: 'Action Items', fieldName: 'actionItems', type: 'text', sortable: true, wrapText: true },
    // Rendered as text so a gated count can carry its trailing '+', but sorted on the raw number.
    { label: 'Missing Items', fieldName: 'missingItems', type: 'text', sortable: true, sortFieldName: 'missingItemsCount', sortType: 'number', wrapText: true },
    { label: 'Last Activity', fieldName: 'lastActivity', type: 'text', sortable: true, sortFieldName: 'lastActivityRaw', sortType: 'date', wrapText: true }
];

// Per-row ⋮ menu actions (stubbed handlers fire toasts for now).
const ROW_ACTIONS = [
    { label: 'Rename', name: 'rename', iconName: 'utility:edit' },
    { label: 'Delete', name: 'delete', iconName: 'utility:delete' }
];

const TEAM_ALL = 'all';

export default class EnvelopeListV2 extends LightningElement {
    // Empty-state illustration (rings + envelope) exported from Figma; lives in
    // the EmptyEnvelopeV2 static resource.
    emptyEnvelopeIllustration = EMPTY_ENVELOPE;
    noResultsEnvelopeIllustration = ENVELOPE_NO_RESULTS;

    // Loaded from the same source the landing page uses. Households / advisor
    // teams feed the New Envelope dialog and the advisor-team column join;
    // envelopes + envelopeRecords build the table rows.
    @track households = [];
    @track financialAdvisorTeams = [];
    @track envelopes = [];
    @track envelopeRecords = [];

    // Table rows, built from the queried envelopes in loadData(). A rename/delete
    // updates this working copy in place (those handlers are still stubs).
    @track rows = [];

    // True while the envelope data is being fetched. Initialized true so the first
    // render shows the spinner instead of briefly flashing the empty state before
    // the Apex call resolves.
    @track isLoading = true;

    // Form context for the Action Items / Missing Items columns, fetched once in loadData and
    // reused for every row. These are the same envelope-independent sources the wizard shell uses
    // to compute its "N inputs missing" header, so the list's Missing Items count matches it.
    // Non-reactive: buildRows runs only after they resolve.
    _schemaCache = {};
    _registrationAttributes = {};
    _userContext = {};

    // Per-envelope metrics (entity counts + each unsubmitted action's form data) extracted
    // server-side, keyed by envelope id. Feeds the Action Items / Missing Items columns without
    // shipping each envelope's full saved-state blob.
    _metricsById = {};

    columns = COLUMNS;
    rowActions = ROW_ACTIONS;
    defaultSortField = 'lastActivity';
    defaultSortDirection = 'desc';

    searchTerm = '';
    teamFilter = TEAM_ALL;
    dateFilter = '';

    showCreateModal = false;

    showRenameModal = false;
    renameEnvelopeId = null;
    renameEnvelopeName = '';

    showDeleteModal = false;
    deleteEnvelopeId = null;
    deleteEnvelopeName = '';

    connectedCallback() {
        this.loadData();
    }

    loadData() {
        this.isLoading = true;
        // Fetch the envelopes and the form context (schemas, registration attributes, user
        // preferences) together; the context feeds the Action Items / Missing Items columns and is
        // the same data the wizard shell prefetches. Context loading is non-fatal on its own.
        return Promise.all([getWizEnvelopes(), this._loadFormContext()])
            .then(([result]) => {
                // Serialize so the console shows plain data instead of LWC read-only proxies.
                console.log('getWizEnvelopes →', JSON.parse(JSON.stringify(result)));
                this.households = result.households || [];
                this.financialAdvisorTeams = result.financialAdvisorTeams || [];
                this.envelopes = result.envelopes || [];
                this.envelopeRecords = result.envelopeRecords || [];
                this._metricsById = {};
                (result.envelopeMetrics || []).forEach((metric) => {
                    this._metricsById[metric.envelopeId] = metric;
                });
                this.buildRows();
            })
            .catch((error) => {
                console.error('Error fetching envelope data:', error);
                this.showToast('Error', 'Failed to load data', 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // Map the queried envelopes onto the table's column keys. The advisor team is
    // resolved with a client-side join: envelope -> envelopeRecord (Account) ->
    // household (Financial_Advisor_Team__c) -> financialAdvisorTeams (Name).
    // Action Items summarizes the envelope's contents ("N members • M ISAs"), counted server-side
    // from its records so the figure matches the wizard's Household Outline; it falls back to blank
    // only when that count could not be derived. Missing Items is the same "inputs missing" count
    // the wizard's Review Missing Items header shows — including its trailing '+' when an unfilled
    // Key Point gates further fields — computed from the saved model and the fetched form context,
    // and blank when there is no saved model.
    buildRows() {
        const recordToAccount = {};
        (this.envelopeRecords || []).forEach((r) => {
            recordToAccount[r.Envelope__c] = r.Account__c;
        });
        const accountToTeamId = {};
        (this.households || []).forEach((h) => {
            accountToTeamId[h.Id] = h.Financial_Advisor_Team__c;
        });
        const teamName = {};
        (this.financialAdvisorTeams || []).forEach((t) => {
            teamName[t.Id] = t.Name;
        });

        // Missing Items needs the field schema to count; without it, leave the cell blank rather
        // than reporting a misleading zero. Action Items needs only the record-derived counts.
        const hasSchema = Object.keys(this._schemaCache || {}).length > 0;
        const context = {
            schemaCache: this._schemaCache,
            registrationAttributes: this._registrationAttributes,
            userContext: this._userContext
        };

        this.rows = (this.envelopes || []).map((env) => {
            const teamId = accountToTeamId[recordToAccount[env.Id]];
            const metrics = this._metricsById[env.Id];
            const hasState = Boolean(metrics?.hasState);
            const hasCounts = Boolean(metrics?.hasCounts);
            const missing =
                hasState && hasSchema
                    ? sumMissingInputs(this._missingInputItems(metrics.actionSources), context)
                    : null;
            return {
                id: env.Id,
                name: env.Name || '',
                household: env.Household_Name__c || '',
                // Household Account id resolved via the envelope's content link; carried on the
                // row so opening the envelope can pass it to the shell's data load.
                householdId: recordToAccount[env.Id] || null,
                advisorTeam: teamName[teamId] || '',
                created: env.CreatedDate
                    ? `${this.formatDateTime(env.CreatedDate)} - ${env.CreatedBy ? env.CreatedBy.Name : ''}`
                    : '',
                // Raw datetime kept so the Created column sorts chronologically
                // rather than by its formatted display string.
                createdRaw: env.CreatedDate || null,
                actionItems: hasCounts
                    ? formatEnvelopeContentsLabel({
                          members: metrics.members,
                          isas: metrics.isas
                      })
                    : '',
                missingItems: missing
                    ? missingInputsCountLabel(missing.count, missing.hasPlus)
                    : null,
                // Raw count kept so the column sorts numerically rather than by its
                // display string (where "10" would order before "2").
                missingItemsCount: missing ? missing.count : null,
                lastActivity: env.LastModifiedDate
                    ? `${this.formatDateTime(env.LastModifiedDate)} - ${env.LastModifiedBy ? env.LastModifiedBy.Name : ''}`
                    : '',
                // Raw datetime feeding both the toolbar date filter and the
                // chronological sort of the Last Activity column.
                lastActivityRaw: env.LastModifiedDate || null
            };
        });
    }

    // Figma-style absolute timestamp, e.g. "May 26, 2026 12:31".
    formatDateTime(value) {
        const date = new Date(value);
        if (isNaN(date.getTime())) {
            return '';
        }
        const datePart = date.toLocaleDateString('en-US', {
            month: 'short',
            day: 'numeric',
            year: 'numeric'
        });
        const timePart = date.toLocaleTimeString('en-US', {
            hour: '2-digit',
            minute: '2-digit',
            hour12: false
        });
        return `${datePart} ${timePart}`;
    }

    // Reduce a datetime to a local YYYY-MM-DD key — matches both the day shown in the
    // Last Activity column (formatDateTime renders local time) and the lightning-input
    // date value, so the filter agrees with what the user sees.
    toLocalDateKey(value) {
        if (!value) {
            return '';
        }
        const date = new Date(value);
        if (isNaN(date.getTime())) {
            return '';
        }
        const year = date.getFullYear();
        const month = String(date.getMonth() + 1).padStart(2, '0');
        const day = String(date.getDate()).padStart(2, '0');
        return `${year}-${month}-${day}`;
    }

    get filteredRows() {
        const term = this.searchTerm.trim().toLowerCase();

        return this.rows.filter((row) => {
            const matchesSearch =
                !term ||
                row.name.toLowerCase().includes(term) ||
                row.household.toLowerCase().includes(term);
            const matchesTeam =
                this.teamFilter === TEAM_ALL || row.advisorTeam === this.teamFilter;
            const matchesDate =
                !this.dateFilter || this.toLocalDateKey(row.lastActivityRaw) === this.dateFilter;

            return matchesSearch && matchesTeam && matchesDate;
        });
    }

    // Raw data exists — drives toolbar visibility (nothing to filter when empty).
    get hasEnvelopes() {
        return this.rows.length > 0;
    }

    // Rows survive the active filter — drives table vs the "No results found" card.
    get hasResults() {
        return this.filteredRows.length > 0;
    }

    get teamOptions() {
        const teams = [...new Set(this.rows.map((row) => row.advisorTeam))].filter(Boolean).sort();
        return [
            { label: 'Team: All', value: TEAM_ALL },
            ...teams.map((team) => ({ label: team, value: team }))
        ];
    }

    get householdOptions() {
        return (this.households || []).map((hh) => ({ label: hh.Name, value: hh.Id }));
    }

    get advisorTeamOptions() {
        return (this.financialAdvisorTeams || []).map((t) => ({ label: t.Name, value: t.Id }));
    }

    handleSearchChange(event) {
        this.searchTerm = event.detail.value || '';
    }

    handleTeamChange(event) {
        this.teamFilter = event.detail.value || TEAM_ALL;
    }

    // Clear all filters back to defaults; the value bindings update the toolbar
    // controls and filteredRows recomputes to show the full list again.
    handleResetFilters() {
        this.searchTerm = '';
        this.teamFilter = TEAM_ALL;
        this.dateFilter = '';
    }

    handleDateChange(event) {
        // Selected day as YYYY-MM-DD; filteredRows matches it against each row's
        // Last Activity day (see toLocalDateKey).
        this.dateFilter = event.target.value || '';
    }

    handleRowAction(event) {
        const { action, row } = event.detail;

        if (action.name === 'rename') {
            this.renameEnvelopeId = row.id;
            this.renameEnvelopeName = row.name;
            this.showRenameModal = true;
        } else if (action.name === 'delete') {
            this.deleteEnvelopeId = row.id;
            this.deleteEnvelopeName = row.name;
            this.showDeleteModal = true;
        }
    }

    handleRowClick(event) {
        const { row } = event.detail;
        // Open the redesigned shellV2 working page — same route the create flow uses.
        this.dispatchEvent(
            new CustomEvent('opencreated', {
                detail: {
                    envelopeId: row.id || null,
                    title: row.name || '',
                    householdName: row.household || '',
                    householdId: row.householdId || null
                }
            })
        );
    }

    handleNewEnvelope() {
        this.showCreateModal = true;
    }

    handleCloseCreateModal() {
        this.showCreateModal = false;
    }

    // The dialog persists the create and shows its own error toast; the `created` event
    // only fires after a successful save. Close the dialog and route into the redesigned
    // shellV2 detail page for the new envelope.
    handleCreateEnvelope(event) {
        this.showCreateModal = false;
        this.dispatchEvent(new CustomEvent('opencreated', { detail: { ...event.detail } }));
    }

    handleCloseRenameModal() {
        this.showRenameModal = false;
    }

    // The dialog persists the rename and shows its own toasts; the `renamed` event only
    // fires after a successful save, so here we just close and reload from the source.
    handleRenameEnvelope() {
        this.showRenameModal = false;
        this.loadData();
    }

    handleCloseDeleteModal() {
        this.showDeleteModal = false;
    }

    // The dialog persists the delete and shows its own toasts; the `deleted` event only
    // fires after a successful delete, so here we just close and reload from the source.
    handleDeleteEnvelope() {
        this.showDeleteModal = false;
        this.loadData();
    }

    showToast(title, message, variant) {
        LightningToast.show({ label: title, message, variant }, this);
    }

    // Fetch the envelope-independent form context once per load. Each source is non-fatal: on
    // failure it falls back to an empty default, and buildRows simply leaves Missing Items blank
    // (see hasSchema) rather than reporting a misleading count. userContext mirrors the shape the
    // wizard shell builds so $User.<field> WHERE conditions resolve the same way.
    _loadFormContext() {
        return Promise.all([
            getAllFormSchemas().catch(() => ({})),
            getRegistrationTypeAttributes().catch(() => ({})),
            getUserPreferences().catch(() => null)
        ]).then(([schemas, registrationAttributes, prefs]) => {
            this._schemaCache = schemas || {};
            this._registrationAttributes = registrationAttributes || {};
            this._userContext = {
                Relationship_to_Firm__c: prefs?.relationshipToFirm ?? null
            };
        });
    }
    // Adapt the server-extracted action sources to the (entity, formData) shape sumMissingInputs
    // expects. Only groupId and type are needed to resolve each entity's schema and related-party
    // rules — the same fields the wizard shell passes.
    _missingInputItems(actionSources) {
        return (actionSources || []).map((source) => ({
            entity: { groupId: source.groupId, type: source.entityType },
            formData: source.formData
        }));
    }
}