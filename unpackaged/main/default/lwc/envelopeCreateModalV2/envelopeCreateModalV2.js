import { LightningElement, api, track } from 'lwc';
import LightningToast from 'lightning/toast';
import createWizEnvelopeV2 from '@salesforce/apex/EnvelopeLandingApex.createWizEnvelopeV2';

const TOGGLE_BASE_CLASS = 'new-envelope-form__toggle-button';

const EMPTY_FORM = {
    title: '',
    householdMode: 'new',
    householdName: '',
    householdId: '',
    advisorTeam: ''
};

export default class EnvelopeCreateModalV2 extends LightningElement {
    // Dropdown data is owned by the list page and passed in.
    @api householdOptions = [];
    @api advisorTeamOptions = [];

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
        return (this.advisorTeamOptions || []).length > 1;
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
        const options = this.advisorTeamOptions || [];
        this.isSaving = false;
        this.newEnvelope = {
            ...EMPTY_FORM,
            // One team => no choice to make: hide the dropdown but still send the
            // team to the backend (it's required for a new household).
            advisorTeam: options.length === 1 ? options[0].value : ''
        };
    }
}