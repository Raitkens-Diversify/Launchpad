import { LightningElement, api } from 'lwc';

/**
 * uatCycleSwitcher — the header cycle-context menu for the UAT tester app:
 * a lightning-button-menu over the tester's cycles (getMyCycles) plus an
 * "All cycles" item. Renders nothing when the tester has fewer than two
 * cycles — with one cycle there is nothing to switch. Emits `cyclechange`
 * { cycleId, cycleName } (null id = All cycles). Embedded by uatTesterApp
 * only; the shell owns the selection and its persistence.
 */
const LABEL_MAX = 32;

export default class UatCycleSwitcher extends LightningElement {
    /** CycleOptionDTO[] from UatRunController.getMyCycles. @type {Array} */
    @api cycles = [];
    /** Selected cycle id; null/undefined = All cycles. @type {string} */
    @api selectedCycleId = null;

    get visible() {
        return (this.cycles || []).length >= 2;
    }

    get selectedCycle() {
        return (this.cycles || []).find((c) => c.cycleId === this.selectedCycleId) || null;
    }

    /* JS truncation, not CSS — the menu's internal button sits across the
       base component's shadow boundary, so an ellipsis style can't reach
       it. The full name rides on the title attribute (hover + assistive
       tech), and the menu items show it untruncated. */
    get buttonLabel() {
        const name = this.selectedCycle ? this.selectedCycle.cycleName : 'All cycles';
        return name.length > LABEL_MAX ? name.slice(0, LABEL_MAX - 1) + '…' : name;
    }

    get buttonTitle() {
        return this.selectedCycle ? this.selectedCycle.cycleName : 'All cycles';
    }

    get allChecked() {
        return !this.selectedCycle;
    }

    get options() {
        return (this.cycles || []).map((c) => ({
            cycleId: c.cycleId,
            checked: c.cycleId === this.selectedCycleId,
            label: c.daysToTarget == null ? c.cycleName
                : c.daysToTarget < 0 ? `${c.cycleName} — ${-c.daysToTarget}d overdue`
                : c.daysToTarget === 0 ? `${c.cycleName} — due today`
                : `${c.cycleName} — ${c.daysToTarget}d left`
        }));
    }

    handleSelect(event) {
        const match = (this.cycles || []).find((c) => c.cycleId === event.detail.value);
        this.dispatchEvent(new CustomEvent('cyclechange', {
            detail: {
                cycleId: match ? match.cycleId : null,
                cycleName: match ? match.cycleName : null
            }
        }));
    }
}