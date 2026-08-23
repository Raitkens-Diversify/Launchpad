import { LightningElement, api } from 'lwc';

// Member types offered by the "Household Members" add menu. Values are the member
// types the Apex create path accepts, each resolving to an Account record type there.
const MEMBER_TYPES = [
    { label: 'Individual', value: 'client' },
    { label: 'Business', value: 'business' },
    { label: 'Trust', value: 'trust' },
    { label: 'Retirement Plan', value: 'retirementPlan' }
];

// Outline sections shown in the Household Outline rail. Static for now; a later slice
// replaces this with the real household/account model. A group with a `menuItems` array
// renders its add control as a dropdown menu (pick a type, then the inline input opens);
// the rest open the inline input directly. `addPlaceholder` is the inline-input
// placeholder for groups without a type step.
const OUTLINE_GROUPS = [
    { id: 'householdMembers', label: 'Household Members', addLabel: 'Add household member', removeLabel: 'Remove household member', menuItems: MEMBER_TYPES },
    { id: 'accounts', label: 'Accounts', addLabel: 'Add account', removeLabel: 'Remove account', addPlaceholder: 'Enter account nickname' },
    { id: 'dpisSponsor', label: 'DPIs - Sponsor Reported', addLabel: 'Add DPI', removeLabel: 'Remove DPI', addPlaceholder: 'Enter DPI nickname' },
    { id: 'serviceAgreements', label: 'Service Agreements', addLabel: 'Add service agreement', removeLabel: 'Remove service agreement', addPlaceholder: 'Enter service agreement nickname' }
];

// The search field appears once the rail holds more than this many items in total.
const SEARCH_THRESHOLD = 6;

/**
 * Author: Mile Cacanovic
 *
 * householdOutlineV2 — presentational left-rail outline for envelopeShellV2.
 * Renders the "Household Outline" header and the collapsible section headings
 * (Household Members, Accounts, DPIs, Service Agreements), each with an add control.
 * Adding opens an inline nickname input under the group; committing it (Enter)
 * dispatches `addentity` to the parent, which owns persistence.
 *
 * Collapse is controlled by the parent: the toggle dispatches a `toggle` event
 * and the parent reflects the new state back via the `collapsed` property. When
 * collapsed the rail shrinks to a narrow strip showing only the toggle button.
 */
export default class HouseholdOutlineV2 extends LightningElement {
    @api collapsed = false;

    // Existing household entities to prepopulate the rail, keyed by group id
    // (householdMembers | accounts | dpisSponsor | serviceAgreements). Each value is an
    // array of { id, name, meta, amount, iconVariant } rendered as outline items.
    @api householdData = {};

    // The group whose inline add-input is currently open (only one at a time), plus the
    // type chosen from the dropdown (members only) used to label the input.
    addingGroupId = null;
    addingType = '';
    addingTypeLabel = '';
    _focusAddInput = false;
    _committing = false;

    // Per-group accordion state: a group id maps to true once collapsed. Absent = expanded,
    // so every group starts open. Session-only.
    _collapsedGroups = {};

    searchTerm = '';

    get totalItemCount() {
        return OUTLINE_GROUPS.reduce(
            (sum, group) => sum + (this.householdData?.[group.id]?.length ?? 0),
            0
        );
    }

    get showSearch() {
        return this.totalItemCount > SEARCH_THRESHOLD;
    }

    get groups() {
        const term = this.searchTerm.trim().toLowerCase();
        // Only filter while the search field is actually offered.
        const searching = this.showSearch && term.length > 0;

        return OUTLINE_GROUPS.map((group) => {
            const allItems = this.householdData?.[group.id] ?? [];
            const items = searching
                ? allItems.filter((item) =>
                      `${item.name} ${item.meta || ''}`.toLowerCase().includes(term)
                  )
                : allItems;
            const hasItems = items.length > 0;
            // While searching, groups are force-expanded and the caret is hidden so matches
            // are always visible; otherwise the accordion state applies.
            const expanded = searching ? true : !this._collapsedGroups[group.id];
            return {
                ...group,
                items,
                hasItems,
                expanded,
                groupClass: 'outline__group',
                ariaExpanded: expanded ? 'true' : 'false',
                // The accordion toggle only shows when the group has items and we're not searching.
                showCaret: hasItems && !searching,
                // Items collapse only when the group has any; the caret never shows otherwise.
                showItems: hasItems && expanded,
                // While searching, a group with no matches keeps its heading and shows "No results".
                showNoResults: searching && !hasItems,
                caretIcon: expanded ? 'utility:chevrondown' : 'utility:chevronright',
                toggleLabel: expanded ? `Collapse ${group.label}` : `Expand ${group.label}`,
                // During search the count is always shown (including "(0)" for no matches);
                labelWithCount: searching || items.length ? `${group.label} (${items.length})` : group.label,
                isAdding: group.id === this.addingGroupId,
                // Hide the group's "+" add control while its own inline input is open.
                showAddControl: group.id !== this.addingGroupId,
                addPlaceholder: this._placeholderFor(group)
            };
        });
    }

    get navClass() {
        return this.collapsed ? 'outline outline--collapsed' : 'outline';
    }

    get toggleLabel() {
        return this.collapsed ? 'Expand sidebar' : 'Collapse sidebar';
    }

    // Drives the inline editor's in-progress state (disabled input + spinner) while
    // a committed add is being persisted by the host.
    get isCommitting() {
        return this._committing;
    }

    handleToggle() {
        this.dispatchEvent(new CustomEvent('toggle'));
    }

    handleSearchChange(event) {
        this.searchTerm = event.detail.value || '';
    }

    // Collapse/expand a single group's item list (accordion). Reassign the map so the
    // change is reactive.
    handleGroupToggle(event) {
        const groupId = event.currentTarget.dataset.group;
        this._collapsedGroups = {
            ...this._collapsedGroups,
            [groupId]: !this._collapsedGroups[groupId]
        };
    }

    // Household Members: a type was picked from the dropdown — open the inline input
    // labelled for that type.
    handleAddSelect(event) {
        const groupId = event.currentTarget.dataset.group;
        const type = event.detail.value;
        const selected = MEMBER_TYPES.find((item) => item.value === type);
        this._openAdd(groupId, type, selected ? selected.label : '');
    }

    // Other groups: the plain "+" opens the inline input directly (no type step).
    handleAddClick(event) {
        this._openAdd(event.currentTarget.dataset.group, '', '');
    }

    // Enter commits the typed nickname; Escape cancels.
    handleAddKeyup(event) {
        if (event.key === 'Enter') {
            this._commitAdd();
        } else if (event.key === 'Escape') {
            this._closeAdd();
        }
    }

    handleAddCancel() {
        this._closeAdd();
    }

    // Re-dispatch an item's more-actions selection to the host, tagged with its group.
    handleItemMenu(event) {
        this.dispatchEvent(
            new CustomEvent('itemmenu', {
                detail: { ...event.detail, group: event.currentTarget.dataset.group }
            })
        );
    }

    // Re-dispatch an item's "+" to the host, tagged with its group.
    handleItemAdd(event) {
        this.dispatchEvent(
            new CustomEvent('itemadd', {
                detail: { ...event.detail, group: event.currentTarget.dataset.group }
            })
        );
    }

    @api
    clearAdd() {
        this._closeAdd();
    }

    // Focus the inline input the first time it appears.
    renderedCallback() {
        if (this._focusAddInput) {
            const input = this.template.querySelector('.outline__add-input');
            if (input) {
                input.focus();
                this._focusAddInput = false;
            }
        }
    }

    // Inline-input placeholder for the group currently adding: type-specific for members,
    // the group's own placeholder otherwise.
    _placeholderFor(group) {
        if (group.id === this.addingGroupId && group.menuItems) {
            return `Enter ${this.addingTypeLabel.toLowerCase()} member's nickname`;
        }
        return group.addPlaceholder || '';
    }

    _openAdd(groupId, type, typeLabel) {
        // Make sure the group is expanded so the input and existing items are visible.
        if (this._collapsedGroups[groupId]) {
            this._collapsedGroups = { ...this._collapsedGroups, [groupId]: false };
        }
        this.addingGroupId = groupId;
        this.addingType = type;
        this.addingTypeLabel = typeLabel;
        this._focusAddInput = true;
    }

    _commitAdd() {
        const input = this.template.querySelector('.outline__add-input');
        const nickname = (input?.value || '').trim();
        if (!nickname) {
            return;
        }
        this._committing = true;
        this.dispatchEvent(
            new CustomEvent('addentity', {
                detail: {
                    group: this.addingGroupId,
                    type: this.addingType,
                    typeLabel: this.addingTypeLabel,
                    nickname
                }
            })
        );
    }

    _closeAdd() {
        this.addingGroupId = null;
        this.addingType = '';
        this.addingTypeLabel = '';
        this._committing = false;
    }
}