import { LightningElement, api, track } from 'lwc';
import { highlightSegments } from 'c/nexsHighlight';
import { significantLength, MIN_SIGNIFICANT_CHARS } from 'c/searchConstants';

const DEBOUNCE_MS = 275;
const LISTBOX_ID = 'ds-search-listbox';

/**
 * dsSearchBar — the shared typeahead search box (ARIA combobox machine).
 *
 * Extracted from the identical machinery that had been forked across
 * nexsSearchBar / resourceSearchBar: 275 ms debounce, min-2-significant-chars
 * gate, full keyboard navigation (role=combobox, aria-expanded,
 * aria-activedescendant), 150 ms blur delay so option mousedown wins, IME
 * guard, and match highlighting.
 *
 * Controlled + Apex-free: the HOST owns data fetching and analytics.
 *   in:  @api placeholder, headerLabel, emptyHint, loading
 *        @api suggestions — [{ id, title, subtitle?, kind?, routeKey }]
 *          Assigning it after a querychange settles the dropdown open (an
 *          empty list still shows the menu, with the empty hint and the
 *          always-present "See all results" row).
 *   out: querychange { value }      — debounced, significant terms only; fetch now
 *        select { suggestion, rank } — a suggestion was chosen (rank is 1-based)
 *        submit { value }            — run the full search (Enter / "See all");
 *                                      value '' on clear
 *
 * Async hosts MUST guard stale responses — use createSuggestionFetcher below
 * so an early slow response can never overwrite a later one.
 */
export default class DsSearchBar extends LightningElement {
    @api placeholder = 'Search…';
    @api headerLabel = 'Top suggestions:';
    @api emptyHint = 'No matches — press Enter to search everything.';
    @api loading = false;

    @track _suggestions = [];
    term = '';
    open = false;
    activeIndex = -1; // -1 = no suggestion active (Enter runs full search)

    _timer;
    _blurTimer;
    _awaitingResults = false; // a querychange went out; next suggestions write settles it

    listboxId = LISTBOX_ID;

    @api
    get suggestions() {
        return this._suggestions;
    }
    set suggestions(value) {
        this._suggestions = Array.isArray(value) ? value : [];
        this.activeIndex = -1;
        if (this._awaitingResults) {
            this._awaitingResults = false;
            this.open = true;
        }
    }

    // ---- Derived view --------------------------------------------------------

    get hasSuggestions() {
        return this._suggestions.length > 0;
    }

    get showMenu() {
        // `open` is only set after a fetch settles for a >=2-significant-char
        // query (and cleared on short/clear/Escape/blur), so an empty result
        // still shows the dropdown rather than vanishing.
        return this.open;
    }

    get suggestionsView() {
        return this._suggestions.map((s, i) => ({
            id: s.id,
            optionId: `ds-opt-${i}`,
            titleSegments: highlightSegments(s.title, this.term),
            subtitle: s.subtitle || null,
            cssClass: i === this.activeIndex ? 'ds-search__item ds-search__item--active' : 'ds-search__item',
            ariaSelected: i === this.activeIndex ? 'true' : 'false'
        }));
    }

    get ariaExpanded() {
        return this.showMenu ? 'true' : 'false';
    }

    get ariaBusy() {
        return this.loading ? 'true' : 'false';
    }

    get activeDescendant() {
        return this.showMenu && this.activeIndex >= 0 ? `ds-opt-${this.activeIndex}` : null;
    }

    get showClear() {
        return Boolean(this.term);
    }

    // ---- Input ---------------------------------------------------------------

    handleInput(event) {
        this.term = event.target.value || '';
        window.clearTimeout(this._timer);

        if (significantLength(this.term) < MIN_SIGNIFICANT_CHARS) {
            this._awaitingResults = false;
            this.closeMenu();
            return;
        }
        this._timer = window.setTimeout(() => {
            this._awaitingResults = true;
            this.dispatchEvent(new CustomEvent('querychange', { detail: { value: this.term } }));
        }, DEBOUNCE_MS);
    }

    // ---- Keyboard (ARIA combobox) --------------------------------------------

    handleKeydown(event) {
        switch (event.key) {
            case 'ArrowDown':
                if (this.showMenu) {
                    event.preventDefault();
                    this.activeIndex = Math.min(this.activeIndex + 1, this._suggestions.length - 1);
                }
                break;
            case 'ArrowUp':
                if (this.showMenu) {
                    event.preventDefault();
                    this.activeIndex = Math.max(this.activeIndex - 1, -1);
                }
                break;
            case 'Enter':
                if (event.isComposing) {
                    return;
                }
                event.preventDefault();
                if (this.showMenu && this.activeIndex >= 0) {
                    this.select(this._suggestions[this.activeIndex]);
                } else if ((this.term || '').trim()) {
                    this.submitSearch();
                }
                break;
            case 'Escape':
                this.closeMenu();
                break;
            default:
        }
    }

    // ---- Selection -----------------------------------------------------------

    handleOptionClick(event) {
        const id = event.currentTarget.dataset.id;
        const match = this._suggestions.find((s) => String(s.id) === id);
        if (match) {
            this.select(match);
        }
    }

    // Keep focus on the input when clicking an option (so blur-close doesn't race).
    handleOptionMousedown(event) {
        event.preventDefault();
    }

    select(suggestion) {
        const rank = this._suggestions.findIndex((s) => s.id === suggestion.id) + 1;
        this.dispatchEvent(new CustomEvent('select', { detail: { suggestion, rank } }));
        this.closeMenu();
    }

    handleSeeAll() {
        this.submitSearch();
    }

    submitSearch() {
        this.dispatchEvent(new CustomEvent('submit', { detail: { value: this.term } }));
        this.closeMenu();
    }

    handleClear() {
        this.term = '';
        this._awaitingResults = false;
        this.closeMenu();
        this.dispatchEvent(new CustomEvent('submit', { detail: { value: '' } }));
        const input = this.template.querySelector('.ds-search__input');
        if (input) {
            input.focus();
        }
    }

    handleBlur() {
        // Delay so an option click registers before the menu closes.
        this._blurTimer = window.setTimeout(() => {
            this.open = false;
        }, 150);
    }

    handleFocus() {
        window.clearTimeout(this._blurTimer);
        if (this.hasSuggestions && significantLength(this.term) >= MIN_SIGNIFICANT_CHARS) {
            this.open = true;
        }
    }

    closeMenu() {
        window.clearTimeout(this._timer);
        this.open = false;
        this.activeIndex = -1;
    }
}

/**
 * Stale-response guard for hosts feeding the bar from async sources: an
 * earlier slow response can never overwrite a later one. Resolves to the
 * fetch result, or null when the response is stale (host: skip the write).
 * Errors still reject, but only after marking the sequence rendered so a
 * failed newer request doesn't let an older success sneak in afterwards.
 */
export function createSuggestionFetcher(fetchFn) {
    let seq = 0;
    let rendered = 0;
    return async (term) => {
        const mine = ++seq;
        try {
            const result = await fetchFn(term);
            if (mine <= rendered) {
                return null;
            }
            rendered = mine;
            return result;
        } catch (error) {
            if (mine > rendered) {
                rendered = mine;
            }
            throw error;
        }
    };
}