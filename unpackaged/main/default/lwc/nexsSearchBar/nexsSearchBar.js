import { LightningElement, api, track } from 'lwc';
import typeahead from '@salesforce/apex/NexSKnowledgeController.typeahead';
import logSearch from '@salesforce/apex/NexSArticleEngagementController.logSearch';
import logClick from '@salesforce/apex/NexSArticleEngagementController.logClick';
import { highlightSegments } from 'c/nexsHighlight';
import { getSessionKey } from 'c/nexsSession';

const DEBOUNCE_MS = 275;
const MIN_SIGNIFICANT_CHARS = 2;
const LISTBOX_ID = 'nexs-typeahead-listbox';
// Idle pause after a zero-suggestion typeahead before it's logged as a gap —
// long enough that mid-word keystrokes don't log partial terms.
const ZERO_LOG_IDLE_MS = 1200;

/**
 * nexsSearchBar
 *
 * Knowledge-aware search box (two-tier UX). As-you-type it hits the lightweight
 * `typeahead` Apex tier (one SOQL, no scoring engine); the full engine runs only
 * on Enter / "See all results". Owns its own input so it can implement the ARIA
 * combobox pattern (role=combobox, aria-expanded, aria-activedescendant) and full
 * keyboard navigation — the shared c-ds-search-bar can't expose those.
 *
 * Surface-agnostic: emits events, navigates nothing.
 *   select { articleId, urlName } — a suggestion was chosen
 *   search { value }              — see all results (Enter / "See all" / clear)
 */
export default class NexsSearchBar extends LightningElement {
    @api placeholder = 'Search help articles…';

    @track suggestions = [];
    term = '';
    open = false;
    activeIndex = -1; // -1 = no suggestion active (Enter runs full search)

    _timer;
    _seq = 0;          // request sequence: only the latest response may render
    _rendered = 0;     // highest sequence rendered so far (stale-response guard)
    _blurTimer;
    _zeroTimer;
    _zeroLogged = new Set(); // terms already logged as gaps this session

    listboxId = LISTBOX_ID;

    // ---- Derived view --------------------------------------------------------

    get hasSuggestions() {
        return this.suggestions.length > 0;
    }

    get showMenu() {
        // `open` is only set true after a fetch completes for a >=2-significant-
        // char query (and cleared on short/clear/Escape/blur), so an empty result
        // still shows the dropdown — with the empty hint and the always-present
        // "See all results" row — rather than vanishing.
        return this.open;
    }

    get suggestionsView() {
        return this.suggestions.map((s, i) => ({
            id: s.id,
            urlName: s.urlName,
            optionId: `nexs-opt-${i}`,
            titleSegments: highlightSegments(s.title, this.term),
            cssClass: i === this.activeIndex ? 'nexs-search__item nexs-search__item--active' : 'nexs-search__item',
            ariaSelected: i === this.activeIndex ? 'true' : 'false'
        }));
    }

    get ariaExpanded() {
        return this.showMenu ? 'true' : 'false';
    }

    get activeDescendant() {
        return this.showMenu && this.activeIndex >= 0 ? `nexs-opt-${this.activeIndex}` : null;
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
            const results = await typeahead({ term: this.term, category: null });
            // Stale-response guard: never let an earlier request overwrite a later
            // one. Only render if this response is newer than the last rendered.
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
            console.error('nexsSearchBar typeahead error', error);
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
        const rank = this.suggestions.findIndex((s) => s.id === suggestion.id) + 1;
        this.logTypeaheadClick(suggestion.id, rank);
        this.dispatchEvent(
            new CustomEvent('select', {
                detail: { articleId: suggestion.id, urlName: suggestion.urlName || null },
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
        // The full search logs this term itself — the pending gap log would dupe it.
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
        const input = this.template.querySelector('.nexs-search__input');
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
        if (this.hasSuggestions && this.significantLength(this.term) >= MIN_SIGNIFICANT_CHARS) {
            this.open = true;
        }
    }

    closeMenu() {
        window.clearTimeout(this._timer);
        this.open = false;
        this.activeIndex = -1;
    }

    // Fire-and-forget: record the typeahead conversion (a Typeahead search plus
    // the click that followed), with the selected rank. Never blocks selection.
    logTypeaheadClick(articleId, rank) {
        const entry = {
            term: this.term,
            resultCount: this.suggestions.length,
            topResultArticleId: this.suggestions.length ? this.suggestions[0].id : null,
            searchType: 'Typeahead',
            sessionKey: getSessionKey(),
            app: 'Help Center'
        };
        // JSON-string transport (org gotcha: custom-type params arrive null).
        logSearch({ entryJson: JSON.stringify(entry) })
            .then((logId) => {
                if (logId) {
                    return logClick({ searchLogId: logId, clickedArticleId: articleId, rank });
                }
                return null;
            })
            .catch(() => {});
    }

    // A settled typeahead with no matches is a knowledge gap. Log it only after
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
                sessionKey: getSessionKey(),
                app: 'Help Center'
            })
        }).catch(() => {});
    }
}