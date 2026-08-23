import { LightningElement, api } from 'lwc';

/**
 * dsTabs — a level-1 tab strip with real tablist semantics: `role="tablist"`,
 * `role="tab"` + `aria-selected` per tab, roving tabindex, and arrow-key
 * navigation (Left/Right wrap, Home/End jump) with automatic activation —
 * panel swaps are free client-side re-renders, so focusing selects.
 *
 * Pure presentation: callers own the panels and the selected value. Level-2
 * status FILTERING stays c-ds-filter-chips (aria-pressed toggle group); this
 * component is for switching content panels.
 *
 * No aria-controls: the panels live across the shadow boundary in the host,
 * where cross-root ID references don't resolve. Hosts should wrap each panel
 * in role="tabpanel" with an aria-label instead.
 *
 * @api tabs: [{ value, label, count? }] — count omitted → no count pill
 * @api selected: value of the active tab
 * @api label: accessible name for the tablist (default 'Tabs')
 * Emits `tabchange` { value } on activation (not when re-clicking the active tab).
 */
export default class DsTabs extends LightningElement {
    @api tabs = [];
    @api selected;
    @api label = 'Tabs';

    get decorated() {
        return (this.tabs || []).map((tab) => {
            const active = tab.value === this.selected;
            return {
                ...tab,
                hasCount: tab.count !== undefined && tab.count !== null,
                ariaSelected: active ? 'true' : 'false',
                tabIndex: active ? '0' : '-1',
                cssClass: 'ds-tabs__tab' + (active ? ' ds-tabs__tab--active' : '')
            };
        });
    }

    handleClick(event) {
        this.activate(event.currentTarget.dataset.value);
    }

    handleKeydown(event) {
        const values = (this.tabs || []).map((t) => t.value);
        if (!values.length) {
            return;
        }
        const current = values.indexOf(event.currentTarget.dataset.value);
        let next = -1;
        if (event.key === 'ArrowRight') {
            next = (current + 1) % values.length;
        } else if (event.key === 'ArrowLeft') {
            next = (current - 1 + values.length) % values.length;
        } else if (event.key === 'Home') {
            next = 0;
        } else if (event.key === 'End') {
            next = values.length - 1;
        }
        if (next === -1) {
            return;
        }
        event.preventDefault();
        this.activate(values[next]);
        // Roving tabindex: the newly active tab is the only 0 — move focus to it.
        const target = this.template.querySelector(`[data-value="${values[next]}"]`);
        if (target) {
            target.focus();
        }
    }

    activate(value) {
        if (value === this.selected) {
            return;
        }
        this.dispatchEvent(new CustomEvent('tabchange', { detail: { value } }));
    }
}