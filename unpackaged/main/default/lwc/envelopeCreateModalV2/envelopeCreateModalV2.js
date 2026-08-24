import { LightningElement, api, track, wire } from 'lwc';
import LightningToast from 'lightning/toast';
// eslint-disable-next-line no-unused-vars -- cosmosdev-side import (Govind, 2026-08-21), kept through the perf merge
import { CurrentPageReference } from 'lightning/navigation';
import createWizEnvelopeV2 from '@salesforce/apex/EnvelopeLandingApex.createWizEnvelopeV2';
import searchHouseholds from '@salesforce/apex/EnvelopeLandingApex.searchHouseholds';

const TOGGLE_BASE_CLASS = 'new-envelope-form__toggle-button';

// Mirrors HOUSEHOLD_SEARCH_MIN_CHARS in EnvelopeLandingApex: the server returns nothing for a
// shorter term, so the picker says why instead of "No matches".
const HOUSEHOLD_SEARCH_MIN_CHARS = 2;
const HOUSEHOLD_SEARCH_HINT = `Type at least ${HOUSEHOLD_SEARCH_MIN_CHARS} characters to search`;
const HOUSEHOLD_NO_MATCHES = 'No matches';

const EMPTY_FORM = {
    title: '',
    householdMode: 'new',
    householdName: '',
    householdId: '',
    advisorTeam: ''
};

export default class EnvelopeCreateModalV2 extends LightningElement {
    // The advisor-team list is owned by the list page and passed in; the household list is not
    // passed in at all — the Existing Household picker searches server-side as the user types
    // (EnvelopeLandingApex.searchHouseholds), so a many-team advisor's thousands of households
    // never reach the client.
    //
    // Under Lightning Locker an array forwarded one hop further than where it was built costs
    // O(n³) to read (see envelopeSearchableCombobox's header for the measurement), so the team
    // list is copied into plain objects exactly once here before lightning-combobox sees it, and
    // the search results are plain objects built here before the picker sees them.
    _advisorTeamOptions = [];
    _advisorTeamOptionsSource = null;

    // The current page of household matches, and what the picker says when it is empty.
    householdOptions = [];
    householdEmptyMessage = HOUSEHOLD_SEARCH_HINT;
    // Sequence number of the latest search, so a slow earlier response cannot overwrite a newer one.
    _householdSearchSeq = 0;

    // `[{ label, value }]`, one per advisor team the user belongs to.
    @api
    get advisorTeamOptions() {
        return this._advisorTeamOptionsSource;
    }
    set advisorTeamOptions(value) {
        if (value === this._advisorTeamOptionsSource) {
            return;
        }
        this._advisorTeamOptionsSource = value;
        const plain = [];
        const length = value ? value.length : 0;
        for (let i = 0; i < length; i += 1) {
            const option = value[i];
            if (option) {
                // One read per property: each is a trip through the proxy layers.
                const label = option.label;
                const id = option.value;
                plain.push({
                    label: label === null || label === undefined ? '' : String(label),
                    value: id === null || id === undefined ? '' : String(id)
                });
            }
        }
        this._advisorTeamOptions = plain;
        // The list normally sets the teams before the dialog opens, but if they land on an open,
        // untouched form the single-team preselection resetForm makes still has to happen.
        if (plain.length === 1 && this.newEnvelope && !this.newEnvelope.advisorTeam) {
            this.newEnvelope = { ...this.newEnvelope, advisorTeam: plain[0].value };
        }
    }

    // The plain copy lightning-combobox is bound to.
    get advisorTeamOptionsPlain() {
        return this._advisorTeamOptions;
    }

    @track newEnvelope = { ...EMPTY_FORM };

    // True while the create is running — drives the spinner over the Create button and
    // disables the footer so the dialog stays put until the action resolves.
    @track isSaving = false;

    _isOpen = false;

    @api
    get isOpen() {
        return this._isOpen;
    }
    set isOpen(value) {
        this._isOpen = value;
        // Start each open with a clean form.
        if (value) {
            this.resetForm();
        }
    }

    get isNewHousehold() {
        return this.newEnvelope.householdMode === 'new';
    }

    get isExistingHousehold() {
        return !this.isNewHousehold;
    }

    get showAdvisorTeamField() {
        // Only show the dropdown when there's a real choice — a single team is
        // preselected and hidden (see resetForm).
        return this._advisorTeamOptions.length > 1;
    }

    get newHouseholdClass() {
        return this.isNewHousehold ? `${TOGGLE_BASE_CLASS} is-active` : TOGGLE_BASE_CLASS;
    }

    get existingHouseholdClass() {
        return this.isExistingHousehold ? `${TOGGLE_BASE_CLASS} is-active` : TOGGLE_BASE_CLASS;
    }

    get isCreateEnvelopeDisabled() {
        if (this.isSaving) {
            return true;
        }
        const hasTitle = !!(this.newEnvelope.title || '').trim();
        // A new household needs both a name and an advisor team — without the team
        // the created household fails the team filter in getWizEnvelopes and the new
        // envelope wouldn't appear in the list.
        const hasHousehold = this.isNewHousehold
            ? !!(this.newEnvelope.householdName || '').trim() && !!this.newEnvelope.advisorTeam
            : !!this.newEnvelope.householdId;
        return !(hasTitle && hasHousehold);
    }

    handleHouseholdModeChange(event) {
        const mode = event.currentTarget.dataset.value;
        this.newEnvelope = {
            ...this.newEnvelope,
            householdMode: mode,
            householdName: '',
            householdId: ''
        };
        // A fresh picker each time the mode flips to Existing: no stale page from the last search.
        this.resetHouseholdSearch();
    }

    // The picker's debounced `search`: fetch the first page of matching households for the term.
    // Responses are sequenced, so a slow response to an earlier term is dropped when a later one has
    // already been issued.
    async handleHouseholdSearch(event) {
        const term = (event.detail?.term || '').trim();
        const seq = ++this._householdSearchSeq;
        if (term.length < HOUSEHOLD_SEARCH_MIN_CHARS) {
            this.householdOptions = [];
            this.householdEmptyMessage = HOUSEHOLD_SEARCH_HINT;
            return;
        }
        try {
            const results = await searchHouseholds({ term });
            if (seq !== this._householdSearchSeq) {
                return;
            }
            // Plain copies, read once: the Apex result is itself proxied on its way in.
            this.householdOptions = (results || []).map((option) => ({
                label: option.label,
                value: option.value
            }));
            this.householdEmptyMessage = HOUSEHOLD_NO_MATCHES;
        } catch (error) {
            if (seq !== this._householdSearchSeq) {
                return;
            }
            console.error('Household search failed', error);
            this.householdOptions = [];
            this.householdEmptyMessage = 'Search failed — try again';
        }
    }

    resetHouseholdSearch() {
        this._householdSearchSeq += 1;
        this.householdOptions = [];
        this.householdEmptyMessage = HOUSEHOLD_SEARCH_HINT;
    }

    handleFieldChange(event) {
        const field = event.target.dataset.field;
        if (!field) return;
        const value = event.detail?.value ?? event.target.value;
        this.newEnvelope = { ...this.newEnvelope, [field]: value };
    }

    handleClose(event) {
        // The inner ds-modal-v2 close event is composed; stop it so the parent
        // gets a single `close` from this component.
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    // Persist the create here so this dialog is self-contained. Keep the dialog open while
    // saving; on success dispatch `created` with the new envelope so the host can navigate
    // to its detail screen, on error surface a toast and stay open to retry.
    async handleCreate() {
        const { title, householdMode, householdName, householdId, advisorTeam } = this.newEnvelope;
        this.isSaving = true;
        try {
            const result = await createWizEnvelopeV2({
                title,
                householdMode,
                householdId: householdId || null,
                householdName,
                advisorTeamId: advisorTeam || null
            });
            this.dispatchEvent(
                new CustomEvent('created', {
                    detail: {
                        envelopeId: result?.id || null,
                        title,
                        // The server resolves the household for both modes — the newly created
                        // one, or the selected existing one. The shell needs the id to
                        // prepopulate the outline with that household's entities.
                        householdName: result?.householdName || '',
                        householdId: result?.householdId || null
                    }
                })
            );
        } catch (error) {
            console.error('Failed to create envelope', error);
            const message = error?.body?.message || error?.message || 'Unable to create envelope.';
            this.showToast('Create failed', message, 'error');
        } finally {
            this.isSaving = false;
        }
    }

    showToast(title, message, variant) {
        LightningToast.show({ label: title, message, variant }, this);
    }

    resetForm() {
        const options = this._advisorTeamOptions;
        this.isSaving = false;
        this.resetHouseholdSearch();
        this.newEnvelope = {
            ...EMPTY_FORM,
            // One team => no choice to make: hide the dropdown but still send the
            // team to the backend (it's required for a new household).
            advisorTeam: options.length === 1 ? options[0].value : ''
        };
    }
}