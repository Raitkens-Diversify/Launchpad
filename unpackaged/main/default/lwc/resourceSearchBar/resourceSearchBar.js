import { LightningElement, api, track } from 'lwc';
import typeahead from '@salesforce/apex/ResourceCenterService.typeahead';
import logSearch from '@salesforce/apex/NexSArticleEngagementController.logSearch';
import { highlightSegments } from 'c/nexsHighlight';
import { getSessionKey } from 'c/nexsSession';

const DEBOUNCE_MS = 275;
const MIN_SIGNIFICANT_CHARS = 2;
const LISTBOX_ID = 'rc-typeahead-listbox';
// Idle pause after a zero-suggestion typeahead before it's logged as a gap —
// long enough that mid-word keystrokes don't log partial terms.
const ZERO_LOG_IDLE_MS = 1200;

/**
 * resourceSearchBar
 *
 * Resource-aware search box — a clone of nexsSearchBar's two-tier UX and ARIA
 * combobox, repointed from Knowledge to ResourceCenterService.typeahead so it
 * looks pixel-identical to the Help Center search while suggesting resources.
 *
 * Surface-agnostic: emits events, navigates nothing.
 *   select { slug }   — a resource suggestion was chosen
 *   search { value }  — see all results (Enter / "See all" / clear)
 */
export default class ResourceSearchBar extends LightningElement {
    @api placeholder = 'Search resources…';

    @track suggestions = [];
    term = '';
    open = false;
    activeIndex = -1; // -1 = no suggestion active (Enter runs full search)

    _timer;
    _seq = 0; // request sequence: only the latest response may render
    _rendered = 0; // highest sequence rendered so far (stale-response guard)
    _blurTimer;
    _zeroTimer;
    _zeroLogged = new Set(); // terms already logged as gaps this session

    listboxId = LISTBOX_ID;

    // ---- Derived view --------------------------------------------------------

    get hasSuggestions() {
        return this.suggestions.length > 0;
    }

    get showMenu() {
        return this.open;
    }

    get suggestionsView() {
        return this.suggestions.map((s, i) => ({
            id: s.id,
            slug: s.slug,
            optionId: `rc-opt-${i}`,
            titleSegments: highlightSegments(s.name, this.term),
            cssClass: i === this.activeIndex ? 'rc-search__item rc-search__item--active' : 'rc-search__item',
            ariaSelected: i === this.activeIndex ? 'true' : 'false'
        }));
    }

    get ariaExpanded() {
        return this.showMenu ? 'true' : 'false';
    }

    get activeDescendant() {
        return this.showMenu && this.activeIndex >= 0 ? `rc-opt-${this.activeIndex}` : null;
    }

    get showClear() {
        return Boolean(this.term);
    }

    // ---- Input ---------------------------------------------------------------

    handleInput(event) {
        this.term = event.target.value || '';
        window.clearTimeout(this._timer);
        window.clearTimeout(this._zeroTimer); // still typing — not a settled gap

        if (this.significantLength(this.term) < MIN_SIGNIFICANT_CHARS) {
            this.closeMenu();
            return;
        }
        this._timer = window.setTimeout(() => this.fetchSuggestions(), DEBOUNCE_MS);
    }

    async fetchSuggestions() {
        const seq = ++this._seq;
        try {
            const results = await typeahead({ term: this.term });
            if (seq <= this._rendered) {
                return;
            }
            this._rendered = seq;
            this.suggestions = results || [];
            this.activeIndex = -1;
            this.open = true;
            this.scheduleZeroSuggestionLog();
        } catch (error) {
            if (seq > this._rendered) {
                this._rendered = seq;
                this.suggestions = [];
                this.open = false;
            }
            // eslint-disable-next-line no-console
            console.error('resourceSearchBar typeahead error', error);
        }
    }

    // Count of significant (alphanumeric) characters in the raw term.
    significantLength(term) {
        return (term || '').replace(/[^a-z0-9]/gi, '').length;
    }

    // ---- Keyboard (ARIA combobox) --------------------------------------------

    handleKeydown(event) {
        switch (event.key) {
            case 'ArrowDown':
                if (this.showMenu) {
                    event.preventDefault();
                    this.activeIndex = Math.min(this.activeIndex + 1, this.suggestions.length - 1);
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
                    this.select(this.suggestions[this.activeIndex]);
                } else if ((this.term || '').trim()) {
                    this.seeAllResults();
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
        const match = this.suggestions.find((s) => s.id === id);
        if (match) {
            this.select(match);
        }
    }

    // Keep focus on the input when clicking an option (so blur-close doesn't race).
    handleOptionMousedown(event) {
        event.preventDefault();
    }

    select(suggestion) {
        this.logTypeaheadConversion();
        this.dispatchEvent(
            new CustomEvent('select', {
                detail: { slug: suggestion.slug || null },
                bubbles: true,
                composed: true
            })
        );
        this.closeMenu();
    }

    handleSeeAll() {
        this.seeAllResults();
    }

    seeAllResults() {
        // The full search (resourceSearchResults) logs this term itself — the
        // pending gap log would dupe it.
        window.clearTimeout(this._zeroTimer);
        this.dispatchEvent(
            new CustomEvent('search', { detail: { value: this.term }, bubbles: true, composed: true })
        );
        this.closeMenu();
    }

    handleClear() {
        this.term = '';
        this.closeMenu();
        this.dispatchEvent(
            new CustomEvent('search', { detail: { value: '' }, bubbles: true, composed: true })
        );
        const input = this.template.querySelector('.rc-search__input');
        if (input) {
            input.focus();
        }
    }

    handleBlur() {
        this._blurTimer = window.setTimeout(() => {
            this.open = false;
        }, 150);
    }

    handleFocus() {
        window.clearTimeout(this._blurTimer);
        if (this.hasSuggestions && this.significantLength(this.term) >= MIN_SIGNIFICANT_CHARS) {
            this.open = true;
        }
    }

    closeMenu() {
        window.clearTimeout(this._timer);
        this.open = false;
        this.activeIndex = -1;
    }

    // ---- Search analytics (fire-and-forget, mirrors nexsSearchBar) -----------

    // Record the typeahead conversion (a suggestion was chosen). Resource
    // suggestions aren't Knowledge articles, so there is no logClick follow-up —
    // the row itself (with its result count) is the signal.
    logTypeaheadConversion() {
        window.clearTimeout(this._zeroTimer);
        // JSON-string transport (org gotcha: custom-type params arrive null).
        logSearch({
            entryJson: JSON.stringify({
                term: this.term,
                resultCount: this.suggestions.length,
                topResultArticleId: null,
                searchType: 'Typeahead',
                sessionKey: getSessionKey()
            })
        }).catch(() => {});
    }

    // A settled typeahead with no matches is a content gap. Log it only after
    // an idle pause (so mid-word keystrokes don't log partial terms) and once
    // per term per session; abandoning the box (blur/Escape/clear) lets the
    // pending log fire — the abandonment IS the gap signal.
    scheduleZeroSuggestionLog() {
        window.clearTimeout(this._zeroTimer);
        if (this.suggestions.length > 0) {
            return;
        }
        const term = this.term;
        this._zeroTimer = window.setTimeout(() => this.logZeroSuggestion(term), ZERO_LOG_IDLE_MS);
    }

    logZeroSuggestion(term) {
        const key = (term || '').trim().toLowerCase();
        if (!key || this.significantLength(term) < MIN_SIGNIFICANT_CHARS
            || this._zeroLogged.has(key)) {
            return;
        }
        this._zeroLogged.add(key);
        // JSON-string transport (org gotcha: custom-type params arrive null).
        logSearch({
            entryJson: JSON.stringify({
                term,
                resultCount: 0,
                topResultArticleId: null,
                searchType: 'Typeahead',
                sessionKey: getSessionKey()
            })
        }).catch(() => {});
    }
}