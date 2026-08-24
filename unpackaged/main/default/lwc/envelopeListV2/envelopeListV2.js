import { LightningElement, track } from 'lwc';
import LightningToast from 'lightning/toast';
import getEnvelopeListData from '@salesforce/apex/EnvelopeLandingApex.getEnvelopeListData';
import EMPTY_ENVELOPE from '@salesforce/resourceUrl/EmptyEnvelopeV2';
import ENVELOPE_NO_RESULTS from '@salesforce/resourceUrl/EnvelopeNoResults';
import {
    formatEnvelopeContentsLabel,
    missingInputsCountLabel
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

    // The envelope rows as the server resolves them (EnvelopeLandingApex.EnvelopeRow: envelope plus
    // the household and advisor team its junction row points at). The page no longer receives the
    // user's household list at all — the Existing Household picker searches server-side.
    @track envelopes = [];

    // Table rows, built from the queried envelopes in loadData(). A rename/delete
    // updates this working copy in place (those handlers are still stubs).
    @track rows = [];

    // True while the envelope data is being fetched. Initialized true so the first
    // render shows the spinner instead of briefly flashing the empty state before
    // the Apex call resolves.
    @track isLoading = true;

    // Per-envelope metrics (entity counts and the stored missing-inputs total), keyed by envelope
    // id. Feeds the Action Items / Missing Items columns without shipping each envelope's full
    // saved-state blob.
    _metricsById = {};

    // Dropdown payloads for the New Envelope dialog and the toolbar, built once per load and held in
    // plain, non-tracked fields so each keeps its identity across renders. They used to be getters:
    // every list render (every search keystroke, every modal open/close) rebuilt them and handed the
    // children a fresh array, which under Lightning Locker re-ran an O(n²)–O(n³) copy in each child
    // — see envelopeSearchableCombobox's header for the measurement behind this.
    advisorTeamOptions = [];
    teamOptions = [];

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
        return getEnvelopeListData()
            .then((result) => {
                // Copied from the raw result before anything is assigned to a tracked field, so
                // the dialog gets plain objects with a stable identity.
                this.advisorTeamOptions = (result.advisorTeamOptions || []).map((option) => ({
                    label: option.label,
                    value: option.value
                }));
                this.envelopes = result.envelopes || [];
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

    // Map the server's envelope rows onto the table's column keys. The household and advisor team
    // arrive already resolved per row (getEnvelopeListData joins them through the junction row).
    // Action Items summarizes the envelope's contents ("N members • M ISAs"), counted server-side
    // from its records so the figure matches the wizard's Household Outline; it falls back to blank
    // only when that count could not be derived. Missing Items is the same "inputs missing" count
    // the wizard's Review Missing Items header shows — including its trailing '+' when an unfilled
    // Key Point gates further fields — read from the total the wizard stores on the envelope, and
    // rendered as 0 when no save has computed one yet rather than as a placeholder.
    buildRows() {
        this.rows = (this.envelopes || []).map((env) => {
            const metrics = this._metricsById[env.id];
            const hasCounts = Boolean(metrics?.hasCounts);
            // Never a placeholder: an envelope that owes nothing owes zero, and one whose total has
            // not been computed yet reads the same way rather than as an unexplained dash.
            const missingCount = metrics?.missingItemsCount ?? 0;
            return {
                id: env.id,
                name: env.name || '',
                household: env.householdName || '',
                // Household Account id resolved server-side via the envelope's content link;
                // carried on the row so opening the envelope can pass it to the shell's data load.
                householdId: env.householdId || null,
                advisorTeam: env.advisorTeamName || '',
                created: env.createdDate
                    ? `${this.formatDateTime(env.createdDate)} - ${env.createdByName || ''}`
                    : '',
                // Raw datetime kept so the Created column sorts chronologically
                // rather than by its formatted display string.
                createdRaw: env.createdDate || null,
                actionItems: hasCounts
                    ? formatEnvelopeContentsLabel({
                          members: metrics.members,
                          isas: metrics.isas
                      })
                    : '',
                missingItems: missingInputsCountLabel(
                    missingCount,
                    Boolean(metrics?.missingItemsHasPlus)
                ),
                // Raw count kept so the column sorts numerically rather than by its
                // display string (where "10" would order before "2").
                missingItemsCount: missingCount,
                lastActivity: env.lastModifiedDate
                    ? `${this.formatDateTime(env.lastModifiedDate)} - ${env.lastModifiedByName || ''}`
                    : '',
                // Raw datetime feeding both the toolbar date filter and the
                // chronological sort of the Last Activity column.
                lastActivityRaw: env.lastModifiedDate || null
            };
        });

        // Toolbar team filter: the distinct teams present in the rows, rebuilt only here so the
        // lightning-combobox keeps the same array between renders.
        const teams = [...new Set(this.rows.map((row) => row.advisorTeam))].filter(Boolean).sort();
        this.teamOptions = [
            { label: 'Team: All', value: TEAM_ALL },
            ...teams.map((team) => ({ label: team, value: team }))
        ];
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
}