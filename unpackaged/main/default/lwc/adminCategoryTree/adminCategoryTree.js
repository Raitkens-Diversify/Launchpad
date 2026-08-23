import { LightningElement, api } from 'lwc';

/**
 * adminCategoryTree — reusable checkbox tree for the Admin Console.
 * Renders two levels (topics → subtopics) from plain data; no data-category
 * jargon leaks to the admin. Controlled component: it mirrors @api selected
 * internally and emits `selectionchange` { names } on every toggle.
 *
 * @api nodes    [{ name, label, children: [{ name, label }] }]
 * @api selected [names] currently assigned
 * @api mode     'multi' (default, checkboxes) | 'single' (one selection max)
 */
export default class AdminCategoryTree extends LightningElement {
    @api nodes = [];
    @api mode = 'multi';

    _selected = new Set();

    @api
    get selected() {
        return [...this._selected];
    }
    set selected(value) {
        this._selected = new Set(value || []);
    }

    get viewNodes() {
        const decorate = (node, isChild) => ({
            name: node.name,
            label: node.label,
            checked: this._selected.has(node.name),
            cssClass: isChild ? 'act-item act-item--child' : 'act-item',
            children: (node.children || []).map((c) => decorate(c, true))
        });
        return (this.nodes || []).map((n) => decorate(n, false));
    }

    get isEmpty() {
        return !this.nodes || this.nodes.length === 0;
    }

    handleToggle(event) {
        const name = event.target.dataset.name;
        const next = new Set(this._selected);
        if (event.target.checked) {
            if (this.mode === 'single') {
                next.clear();
            }
            next.add(name);
        } else {
            next.delete(name);
        }
        this._selected = next;
        this.dispatchEvent(
            new CustomEvent('selectionchange', {
                detail: { names: [...next] }
            })
        );
    }
}