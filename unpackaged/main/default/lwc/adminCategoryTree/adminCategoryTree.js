import { LightningElement, api } from 'lwc';

/**
 * adminCategoryTree — reusable checkbox tree for the Admin Console (article
 * filing, the resource editor's home and "Also show in" pickers). Renders
 * the {name, label, children} picker shape at any depth as one flat list,
 * indented per level; no data-category jargon leaks to the admin.
 * Controlled component: it mirrors @api selected internally and emits
 * `selectionchange` { names } on every toggle.
 *
 * @api nodes    [{ name, label, children: [same shape, any depth] }]
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

    /** Pre-order rows with depth (1 = top level), iterative for any depth. */
    get viewNodes() {
        const rows = [];
        const stack = [];
        const roots = this.nodes || [];
        for (let i = roots.length - 1; i >= 0; i--) {
            stack.push([roots[i], 1]);
        }
        while (stack.length) {
            const [node, depth] = stack.pop();
            rows.push({
                name: node.name,
                label: node.label,
                checked: this._selected.has(node.name),
                cssClass: depth === 1 ? 'act-item' : 'act-item act-item--child',
                labelClass: depth === 1 ? 'act-item__label act-item__label--topic' : 'act-item__label',
                style: `padding-left: ${0.375 + 1.5 * (depth - 1)}rem`,
                level: String(depth)
            });
            const kids = node.children || [];
            for (let i = kids.length - 1; i >= 0; i--) {
                stack.push([kids[i], depth + 1]);
            }
        }
        return rows;
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