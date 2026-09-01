import { LightningElement, api } from 'lwc';

// Per-variant configuration for the inline add-item card. Type options are mock data
// until the real member/ISA type sources are wired up.
const CONFIG = {
    member: {
        icon: 'utility:adduser',
        iconClass: 'add-form__icon add-form__icon_member',
        title: 'Add Client',
        nicknameLabel: 'Client Nickname',
        nicknamePlaceholder: 'Enter Client Nickname',
        typeLabel: 'Client Type',
        typePlaceholder: 'Select Client Type',
        submitLabel: 'Add Client',
        typeOptions: [
            { label: 'Individual', value: 'client' },
            { label: 'Business', value: 'business' },
            { label: 'Trust', value: 'trust' },
            { label: 'Retirement Plan', value: 'retirementPlan' }
        ]
    },
    isa: {
        icon: 'utility:new',
        iconClass: 'add-form__icon add-form__icon_isa',
        title: 'Add Investment or Service',
        nicknameLabel: 'Investment or Service Nickname',
        nicknamePlaceholder: 'Enter Investment or Service Nickname',
        typeLabel: 'Investment or Service Type',
        typePlaceholder: 'Select Investment or Service Type',
        submitLabel: 'Add Investment or Service',
        typeOptions: [
            { label: 'Accounts', value: 'accounts' },
            { label: 'DPIs - Sponsor Reported', value: 'dpi' },
            { label: 'Service Agreements', value: 'serviceAgreements' },
        ]
    }
};

/**
 * Author: Mile Cacanovic
 *
 * envelopeAddItemForm — inline "Add member" / "Add ISA" card. The two variants share
 * one template and differ only by the per-variant config above. Presentational for
 * now: emits `cancel` and `additem`; the host owns what happens next.
 */
export default class EnvelopeAddItemForm extends LightningElement {
    @api variant = 'member';
    @api saving = false;
    @api isSalesforceUser = false;
    @api eligibleMembers = [];

    nickname = '';
    typeValue = '';
    selectedExistingId = '';
    _formMode = null;

    get config() {
        return CONFIG[this.variant] || CONFIG.member;
    }

    get hasEligibleMembers() {
        return this.eligibleMembers?.length > 0;
    }

    get showModeButtons() {
        return this.isSalesforceUser && this.variant === 'member' && this.hasEligibleMembers && !this._formMode;
    }

    get showSelectExisting() {
        return this.isSalesforceUser && this.variant === 'member' && this._formMode === 'selectExisting';
    }

    get showCreateNew() {
        return (this.variant !== 'member' || !this.isSalesforceUser || !this.hasEligibleMembers) || this._formMode === 'createNew';
    }

    get disableSubmit() {
        return this.saving || !(this.nickname?.trim() && this.typeValue);
    }

    get disableSelectSubmit() {
        return this.saving || !this.selectedExistingId;
    }

    get eligibleMemberOptions() {
        return this.eligibleMembers || [];
    }

    handleSelectExistingMode() {
        this._formMode = 'selectExisting';
    }

    handleCreateNewMode() {
        this._formMode = 'createNew';
    }

    handleBackToModes() {
        this._formMode = null;
        this.selectedExistingId = '';
        this.nickname = '';
        this.typeValue = '';
    }

    handleExistingMemberChange(event) {
        this.selectedExistingId = event.detail.value;
    }

    handleExistingSubmit() {
        this.dispatchEvent(
            new CustomEvent('addexisting', {
                detail: { entityId: this.selectedExistingId }
            })
        );
    }

    handleNicknameChange(event) {
        this.nickname = event.detail.value;
    }

    handleTypeChange(event) {
        this.typeValue = event.detail.value;
    }

    get cancelOrBackLabel() {
        return this._formMode === 'createNew' && this.hasEligibleMembers ? 'Back' : 'Cancel';
    }

    handleCancelOrBack() {
        if (this._formMode === 'createNew' && this.hasEligibleMembers) {
            this.handleBackToModes();
        } else {
            this.handleCancel();
        }
    }

    handleCancel() {
        this._formMode = null;
        this.dispatchEvent(new CustomEvent('cancel'));
    }

    handleSubmit() {
        const selected = this.config.typeOptions.find((option) => option.value === this.typeValue);
        this.dispatchEvent(
            new CustomEvent('additem', {
                detail: {
                    variant: this.variant,
                    nickname: this.nickname,
                    type: this.typeValue,
                    typeLabel: selected ? 'Client' : ''
                }
            })
        );
    }
}