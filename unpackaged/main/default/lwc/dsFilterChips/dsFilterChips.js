import { LightningElement, api } from 'lwc';

/**
 * dsFilterChips — a row of toggle-button filter chips with optional live
 * counts (the mockup's "All 6 | In Progress 2 | …" row). Pure presentation:
 * callers compute the counts and own the filtering; this only renders and
 * reports selection. Toggle-button group semantics (`aria-pressed` per chip
 * inside a labelled group) — the notificationCenterLog pattern, restyled
 * with system tokens.
 *
 * @api chips: [{ value, label, count? }] — count omitted → no count pill
 * @api selected: value of the active chip
 * @api groupLabel: accessible name for the group (default 'Filters')
 * Emits `select` { value } on click (also when re-clicking the active chip).
 */
export default class DsFilterChips extends LightningElement {
    @api chips = [];
    @api selected;
    @api groupLabel = 'Filters';

    get decorated() {
        return (this.chips || []).map((chip) => {
            const active = chip.value === this.selected;
            return {
                ...chip,
                hasCount: chip.count !== undefined && chip.count !== null,
                pressed: active ? 'true' : 'false',
                cssClass: 'ds-chips__chip' + (active ? ' ds-chips__chip--active' : '')
            };
        });
    }

    handleSelect(event) {
        this.dispatchEvent(new CustomEvent('select', {
            detail: { value: event.currentTarget.dataset.value }
        }));
    }
}