import { LightningElement, api } from 'lwc';

/**
 * Author: Mile Cacanovic
 *
 * envelopeSearchableCombobox — single-select dropdown with type-to-filter, for picklists with many
 * options (lightning-combobox has no search). Filters a static `[{label, value}]` array client-side;
 * dispatches `change` with `{ value }`. Generic/reusable; first used by the dynamic-form field
 * renderer, intended to replace plain comboboxes across the flow later.
 */
export default class EnvelopeSearchableCombobox extends LightningElement {
    @api label = '';
    @api placeholder = 'Select an option';
    @api options = [];
    @api required = false;
    @api disabled = false;
    @api name;
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
    // Stable reference so add/removeEventListener pair up.
    _repositionMenu = () => this._positionMenu();

    @api
    get value() {
        return this._value;
    }
    set value(next) {
        this._value = next === null || next === undefined ? '' : String(next);
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

    get selectedLabel() {
        const match = (this.options || []).find((option) => option.value === this._value);
        return match ? match.label : '';
    }

    // Closed: show the selected label. Open: show the search term so the user can filter.
    get displayValue() {
        return this.isOpen ? this.searchTerm : this.selectedLabel;
    }

    get filteredOptions() {
        const term = this.searchTerm.trim().toLowerCase();
        return (this.options || [])
            .filter(
                (option) =>
                    !term || String(option.label || '').toLowerCase().includes(term)
            )
            .map((option, index) => ({
                value: option.value,
                label: option.label,
                optionId: `escb-opt-${index}`,
                isSelected: option.value === this._value,
                optionClass:
                    index === this.activeIndex
                        ? 'escb__option escb__option_active'
                        : 'escb__option'
            }));
    }

    get hasOptions() {
        return this.filteredOptions.length > 0;
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
        // The component can unmount with the menu open (e.g. its dialog closes).
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
    }

    close() {
        this.isOpen = false;
        this.searchTerm = '';
        this.activeIndex = -1;
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
        this.searchTerm = event.target.value;
        this.activeIndex = -1;
    }

    handleKeydown(event) {
        switch (event.key) {
            case 'ArrowDown':
                event.preventDefault();
                if (!this.isOpen) {
                    this.open();
                    return;
                }
                this.activeIndex = Math.min(
                    this.activeIndex + 1,
                    this.filteredOptions.length - 1
                );
                break;
            case 'ArrowUp':
                event.preventDefault();
                this.activeIndex = Math.max(this.activeIndex - 1, 0);
                break;
            case 'Enter': {
                event.preventDefault();
                const option = this.filteredOptions[this.activeIndex];
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