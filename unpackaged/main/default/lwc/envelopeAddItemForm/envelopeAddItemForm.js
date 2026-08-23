import { LightningElement, api } from 'lwc';

// Per-variant configuration for the inline add-item card. Type options are mock data
// until the real member/ISA type sources are wired up.
const CONFIG = {
    member: {
        icon: 'utility:adduser',
        iconClass: 'add-form__icon add-form__icon_member',
        title: 'Add member',
        nicknameLabel: 'Member Nickname',
        nicknamePlaceholder: 'Enter member nickname',
        typeLabel: 'Member Type',
        typePlaceholder: 'Select member type',
        submitLabel: 'Add Member',
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
        title: 'Add ISA',
        nicknameLabel: 'ISA Nickname',
        nicknamePlaceholder: 'Enter ISA nickname',
        typeLabel: 'ISA Type',
        typePlaceholder: 'Select ISA type',
        submitLabel: 'Add ISA',
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
    // Set by the host while it persists the added item; keeps the form in a busy state.
    @api saving = false;

    nickname = '';
    typeValue = '';

    get config() {
        return CONFIG[this.variant] || CONFIG.member;
    }

    get disableSubmit() {
        return this.saving || !(this.nickname?.trim() && this.typeValue);
    }

    handleNicknameChange(event) {
        this.nickname = event.detail.value;
    }

    handleTypeChange(event) {
        this.typeValue = event.detail.value;
    }

    handleCancel() {
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
                    typeLabel: selected ? selected.label : ''
                }
            })
        );
    }
}