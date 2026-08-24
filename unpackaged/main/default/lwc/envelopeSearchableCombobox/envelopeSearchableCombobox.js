import { LightningElement, api } from 'lwc';

/**
 * Author: Mile Cacanovic
 *
 * envelopeSearchableCombobox — single-select dropdown with type-to-filter, for picklists with many
 * options (lightning-combobox has no search). Filters a static `[{label, value}]` array client-side;
 * dispatches `change` with `{ value }`. Generic/reusable; first used by the dynamic-form field
 * renderer, intended to replace plain comboboxes across the flow later.
 *
 * How options get in matters more than how many there are. In Lightning Experience every array that
 * crosses an `@api` boundary is wrapped by Lightning Locker and by LWC's read-only membrane, and the
 * two wrap each other at every hop, so reading the array back is roughly O(n²) one hop from where it
 * was built and O(n³) two hops away (measured 2026-08-19 in launchpad: 300 options two hops away took
 * 88 seconds to walk; the 3,962-household New Envelope picker never returned). Three rules follow and
 * are implemented here:
 *
 *  - `options` is copied into plain objects exactly once, in the setter, and every later read —
 *    filtering, row decoration, resolving the selected label — is against that plain copy. Nothing
 *    else in this file touches the array the parent handed over.
 *  - Lists larger than about 150 rows should arrive as `optionsJson`, a JSON string of the same
 *    array: a string crosses any number of boundaries at O(1) and is parsed once here.
 *  - Only `maxRenderedOptions` rows reach the DOM (the rest are reached by typing, with a footer
 *    saying how many are hidden), and the derived row list is cached in a field rather than computed
 *    in a getter, so a render costs the rendered rows, not the option count.
 *
 * The debounced filter also dispatches `search` with `{ term }`, so a parent that resolves options
 * server-side can replace `options` as the user types; parents that do not listen lose nothing.
 */

// Rows rendered at once. 150 clears every current caller's list (the largest is ~95 strategies) while
// bounding the household picker's render to a few hundred nodes instead of twelve thousand.
const DEFAULT_MAX_RENDERED = 150;
// Idle window before a typed term rebuilds the list: long enough to swallow a burst of keystrokes,
// short enough that the list still feels live.
const FILTER_IDLE_MS = 250;
const DEFAULT_EMPTY_MESSAGE = 'No matches';

// One plain `{ label, value }` per option, read from the source exactly once. Labels and values are
// coerced to strings so nothing downstream ever reaches back into the source object.
function toPlainOptions(source) {
    const plain = [];
    if (!source) {
        return plain;
    }
    const length = source.length;
    for (let i = 0; i < length; i += 1) {
        const option = source[i];
        if (!option) {
            continue;
        }
        // Each property is read exactly once: under Locker every read costs a trip through the
        // proxy layers, so `label ?? ''` style double reads are not free here.
        const label = option.label;
        const value = option.value;
        plain.push({
            label: label === null || label === undefined ? '' : String(label),
            value: value === null || value === undefined ? '' : String(value)
        });
    }
    return plain;
}

export default class EnvelopeSearchableCombobox extends LightningElement {
    @api label = '';
    @api placeholder = 'Select an option';
    @api required = false;
    @api disabled = false;
    @api name;
    // Shown in the menu when nothing matches the typed term (or the list is empty). A parent that
    // searches server-side can use it to say "Type at least 2 characters".
    @api emptyMessage = DEFAULT_EMPTY_MESSAGE;
    // 'standard' | 'label-hidden'
    _variant = 'standard';

    @api
    get variant() {
        return this._variant;
    }
    set variant(value) {
        this._variant = value || 'standard';
    }

    // When true, the open menu is rendered as a viewport-fixed overlay positioned from the
    // control's rect, so a scrolling ancestor (e.g. a modal body) cannot clip it.
    @api floatMenu = false;

    searchTerm = '';
    isOpen = false;
    activeIndex = -1;
    _value = '';
    _menuStyle = '';
    // The plain copy of the options (see the header); the parent's array is never kept.
    _options = [];
    // Identity of the last array / string the parent handed over, so a repeat pass is free.
    _optionsSource = null;
    _optionsJson = null;
    _maxRendered = DEFAULT_MAX_RENDERED;
    // The matched options, already capped to what will render, and how many matched in total — the
    // count is what the truncation footer reports, so it is taken before the cap is applied.
    _matched = [];
    _matchCount = 0;
    // The rendered rows: `_matched` plus each row's display state (selected, active).
    _visibleOptions = [];
    // Label of the selected value, resolved against the full plain list whenever the value or the
    // options change — not per render.
    _selectedLabel = '';
    // The value _selectedLabel was resolved for (see _paint).
    _selectedLabelValue = '';
    _filterTimer = null;
    // Stable reference so add/removeEventListener pair up.
    _repositionMenu = () => this._positionMenu();

    @api
    get options() {
        return this._optionsSource;
    }
    // An accessor rather than a field so the plain copy is taken exactly once per real prop change.
    // Parents commonly hand back a freshly mapped array on every one of their own renders; the
    // identity guard makes the repeat pass free. Keep this list small (≲150): the single copy pass is
    // the one place this component reads through the proxy layers, and that pass is O(n²) under
    // Locker. Bigger lists belong in `optionsJson`.
    set options(next) {
        if (next === this._optionsSource) {
            return;
        }
        this._optionsSource = next;
        this._optionsJson = null;
        this._options = toPlainOptions(next);
        this._recompute();
    }

    // The same list as a JSON string — `JSON.stringify([{ label, value }, ...])`. Strings are not
    // proxied, so this is the way to hand over a large list (the household picker's ~4,000 rows)
    // without paying the per-hop wrapping cost. The last of `options` / `optionsJson` to be set wins.
    @api
    get optionsJson() {
        return this._optionsJson;
    }
    set optionsJson(next) {
        if (next === this._optionsJson) {
            return;
        }
        this._optionsJson = next;
        this._optionsSource = null;
        let parsed = [];
        if (next) {
            try {
                parsed = JSON.parse(next);
            } catch (error) {
                console.error('envelopeSearchableCombobox: optionsJson is not valid JSON', error);
                parsed = [];
            }
        }
        this._options = toPlainOptions(Array.isArray(parsed) ? parsed : []);
        this._recompute();
    }

    @api
    get maxRenderedOptions() {
        return this._maxRendered;
    }
    set maxRenderedOptions(next) {
        const cap = Math.floor(Number(next));
        this._maxRendered = cap > 0 ? cap : DEFAULT_MAX_RENDERED;
        this._recompute();
    }

    @api
    get value() {
        return this._value;
    }
    set value(next) {
        this._value = next === null || next === undefined ? '' : String(next);
        this._paint();
    }

    get showLabel() {
        return this.variant !== 'label-hidden' && !!this.label;
    }

    get inputAriaLabel() {
        if (this.variant === 'label-hidden' && this.label) {
            return this.label;
        }
        return null;
    }

    get menuAriaLabel() {
        return this.inputAriaLabel || this.label || 'Options';
    }

    // Resolved against the full option list, not the rendered rows — the selected value is very
    // often outside the cap.
    get selectedLabel() {
        return this._selectedLabel;
    }

    // Closed: show the selected label. Open: show the search term so the user can filter.
    get displayValue() {
        return this.isOpen ? this.searchTerm : this._selectedLabel;
    }

    get visibleOptions() {
        return this._visibleOptions;
    }

    get hasOptions() {
        return this._visibleOptions.length > 0;
    }

    get isTruncated() {
        return this._matchCount > this._visibleOptions.length;
    }

    get truncationLabel() {
        return `Showing first ${this._visibleOptions.length.toLocaleString()} of ${this._matchCount.toLocaleString()} — keep typing to narrow`;
    }

    get emptyLabel() {
        return this.emptyMessage || DEFAULT_EMPTY_MESSAGE;
    }

    get activeDescendant() {
        return this.activeIndex >= 0 ? `escb-opt-${this.activeIndex}` : null;
    }

    get ariaExpanded() {
        return this.isOpen ? 'true' : 'false';
    }

    get controlClass() {
        let classes = 'escb__control';
        if (this.isOpen) {
            classes += ' escb__control_open';
        }
        if (this.disabled) {
            classes += ' escb__control_disabled';
        }
        return classes;
    }

    get menuClass() {
        return this.floatMenu ? 'escb__menu escb__menu_fixed' : 'escb__menu';
    }

    get menuStyle() {
        return this._menuStyle;
    }

    disconnectedCallback() {
        // The component can unmount with the menu open (e.g. its dialog closes), or mid-debounce.
        this._cancelFilter();
        this._removeFloatListeners();
    }

    open() {
        if (this.disabled || this.isOpen) {
            return;
        }
        if (this.floatMenu) {
            // Position before opening: the control is already rendered, so the menu
            // paints at the right spot on its first render.
            this._positionMenu();
            window.addEventListener('scroll', this._repositionMenu, true);
            window.addEventListener('resize', this._repositionMenu);
        }
        this.isOpen = true;
        this.searchTerm = '';
        this.activeIndex = -1;
        this._cancelFilter();
        this._recompute();
    }

    close() {
        this.isOpen = false;
        this.searchTerm = '';
        this.activeIndex = -1;
        this._cancelFilter();
        this._recompute();
        if (this.floatMenu) {
            this._removeFloatListeners();
            this._menuStyle = '';
        }
    }

    handleFocus() {
        this.open();
    }

    // Close when focus leaves the component (to outside content, another field, or a non-focusable
    // area — relatedTarget is null then). Presses inside the menu keep focus via handleMenuMouseDown,
    // so this doesn't fire on selection. Component-local, so the dialog's stopPropagation doesn't
    // affect it.
    handleFocusOut(event) {
        if (event.relatedTarget && this.template.contains(event.relatedTarget)) {
            return;
        }
        this.close();
    }

    // Keep focus in the input on any press inside the menu — an option, the padding, or the scrollbar
    // gutter. Without this the input blurs and focusout closes the list mid-interaction (e.g. while
    // dragging the scrollbar). Native scrollbar dragging is unaffected by preventDefault.
    handleMenuMouseDown(event) {
        event.preventDefault();
    }

    handleInput(event) {
        // Route reopening through open() so the float menu is (re)positioned.
        if (!this.isOpen) {
            this.open();
        }
        // The term is taken immediately, because displayValue is bound to the input: deferring it
        // would let any unrelated re-render inside the idle window paint the stale term back over
        // what was typed. Only the list rebuild waits.
        this.searchTerm = event.target.value;
        this.activeIndex = -1;
        this._scheduleFilter();
    }

    handleKeydown(event) {
        switch (event.key) {
            case 'ArrowDown':
                event.preventDefault();
                if (!this.isOpen) {
                    this.open();
                    return;
                }
                this._setActiveIndex(
                    Math.min(this.activeIndex + 1, this._visibleOptions.length - 1)
                );
                break;
            case 'ArrowUp':
                event.preventDefault();
                this._setActiveIndex(Math.max(this.activeIndex - 1, 0));
                break;
            case 'Enter': {
                event.preventDefault();
                const option = this._visibleOptions[this.activeIndex];
                if (option) {
                    this.selectValue(option.value);
                }
                break;
            }
            case 'Escape':
                event.preventDefault();
                this.close();
                break;
            default:
                break;
        }
    }

    handleOptionClick(event) {
        const selected = event.currentTarget?.dataset?.value;
        if (selected !== undefined) {
            this.selectValue(selected);
        }
    }

    handleToggle(event) {
        event.preventDefault();
        if (this.disabled) {
            return;
        }
        if (this.isOpen) {
            this.close();
        } else {
            this.open();
            this.focusInput();
        }
    }

    selectValue(value) {
        this._value = value;
        this.close();
        this.dispatchEvent(new CustomEvent('change', { detail: { value } }));
    }

    focusInput() {
        const input = this.template.querySelector('.escb__input');
        if (input) {
            input.focus();
        }
    }

    @api
    checkValidity() {
        return !this.required || !!this._value;
    }

    @api
    reportValidity() {
        const valid = this.checkValidity();
        const control = this.template.querySelector('.escb__control');
        if (control) {
            control.classList.toggle('escb__control_error', !valid);
        }
        return valid;
    }

    // One pass over the plain option list: count all the matches, but materialise only the ones that
    // will be rendered. What is left scaling with the list is a string scan per option; nothing
    // downstream of the cap does.
    _recompute() {
        const term = this.searchTerm.trim().toLowerCase();
        const all = this._options;
        const cap = this._maxRendered;
        const matched = [];
        let count = 0;
        for (let i = 0; i < all.length; i += 1) {
            const option = all[i];
            if (term && !option.label.toLowerCase().includes(term)) {
                continue;
            }
            count += 1;
            if (matched.length < cap) {
                matched.push(option);
            }
        }
        this._matched = matched;
        this._matchCount = count;
        this._paint();
    }

    // Row decoration only, so the changes that merely move a highlight — arrow keys, a new selection
    // — cost the rendered row count rather than the whole option list. The selected label is resolved
    // here too (value and options are the only things that change it, and both route through here).
    _paint() {
        const active = this.activeIndex;
        const selected = this._value;
        this._visibleOptions = this._matched.map((option, index) => ({
            value: option.value,
            label: option.label,
            optionId: `escb-opt-${index}`,
            isSelected: option.value === selected,
            optionClass:
                index === active ? 'escb__option escb__option_active' : 'escb__option'
        }));
        // A selection keeps its label even after the option list moves on without it — a parent
        // that pages options in from a server search replaces the list on every term, and the row
        // the user picked two searches ago is still the value.
        const label = this._resolveLabel(selected);
        if (label !== null) {
            this._selectedLabel = label;
            this._selectedLabelValue = selected;
        } else if (selected !== this._selectedLabelValue) {
            this._selectedLabel = '';
            this._selectedLabelValue = selected;
        }
    }

    // The label for a value, '' for no value, null when the value is not in the current list.
    _resolveLabel(value) {
        if (!value) {
            return '';
        }
        const all = this._options;
        for (let i = 0; i < all.length; i += 1) {
            if (all[i].value === value) {
                return all[i].label;
            }
        }
        return null;
    }

    _setActiveIndex(next) {
        this.activeIndex = next;
        this._paint();
    }

    _scheduleFilter() {
        this._cancelFilter();
        this._filterTimer = setTimeout(() => {
            this._filterTimer = null;
            this._recompute();
            this.dispatchEvent(
                new CustomEvent('search', { detail: { term: this.searchTerm.trim() } })
            );
        }, FILTER_IDLE_MS);
    }

    _cancelFilter() {
        if (this._filterTimer) {
            clearTimeout(this._filterTimer);
            this._filterTimer = null;
        }
    }

    // Anchor the fixed menu to the control: same left/width, 4px below, capped to the space left
    // above the viewport bottom so the list scrolls internally instead of running off-screen.
    // Re-run on scroll/resize so the menu follows the control (a reposition to the same
    // coordinates, e.g. from the menu's own internal scroll, is a no-op).
    _positionMenu() {
        const control = this.template.querySelector('.escb__control');
        if (!control) {
            return;
        }
        const rect = control.getBoundingClientRect();
        const maxHeight = Math.max(100, Math.min(240, window.innerHeight - rect.bottom - 12));
        this._menuStyle = `left: ${rect.left}px; top: ${rect.bottom + 4}px; width: ${rect.width}px; max-height: ${maxHeight}px;`;
    }

    _removeFloatListeners() {
        window.removeEventListener('scroll', this._repositionMenu, true);
        window.removeEventListener('resize', this._repositionMenu);
    }
}