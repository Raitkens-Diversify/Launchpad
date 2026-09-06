import { LightningElement, api } from 'lwc';

/**
 * dsSubnav — the "In this topic" row: one navigation pill per child of the
 * node a reader is looking at, so a topic's subtopics are reachable from the
 * content column and not only from the sidebar tree. Pure presentation: the
 * host hands over the children it already holds (c/treeUtil) and routes.
 *
 * Plain buttons, not c-ds-filter-chips' aria-pressed toggles — these leave
 * the page rather than filter it.
 *
 * @api label  lead-in text, doubling as the nav's accessible name
 * @api items  [{ key, label, count? }] — count 0/omitted renders no badge
 *             (the c-ds-tree rule)
 * Emits `navselect { key }` — the same contract as c-ds-tree, so a host
 * points both at one handler.
 */
export default class DsSubnav extends LightningElement {
    @api label = 'In this topic';
    @api items = [];

    get hasItems() {
        return (this.items || []).length > 0;
    }

    get decorated() {
        return (this.items || []).map((item) => ({
            key: item.key,
            label: item.label,
            count: item.count > 0 ? String(item.count) : null
        }));
    }

    handleSelect(event) {
        this.dispatchEvent(new CustomEvent('navselect', {
            detail: { key: event.currentTarget.dataset.key }
        }));
    }
}