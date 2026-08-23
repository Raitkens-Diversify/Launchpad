import { LightningElement, api, wire } from 'lwc';
import searchAll from '@salesforce/apex/ResourceCenterService.searchAll';
import getHelpCenterLinkBase from '@salesforce/apex/ResourceCenterService.getHelpCenterLinkBase';
import logSearch from '@salesforce/apex/NexSArticleEngagementController.logSearch';
import { getSessionKey } from 'c/nexsSession';

/**
 * resourceSearchResults — combined article + resource results, sectioned by
 * type. Resources open in-site (emits `resourceselect { slug }`); articles
 * deep-link to the Help Center when helpCenterBaseUrl is set.
 */
export default class ResourceSearchResults extends LightningElement {
    @api term;
    /** Optional override; defaults to the site root resolved server-side. */
    @api helpCenterBaseUrl;

    resolvedHelpBase;

    @wire(getHelpCenterLinkBase)
    wiredHelpBase({ data }) {
        if (data) {
            this.resolvedHelpBase = data;
        }
    }

    results;
    loading = true;
    _lastLoggedTerm; // wire can re-emit for the same term — log each search once

    @wire(searchAll, { term: '$term' })
    wiredResults({ data }) {
        this.results = data || [];
        this.loading = false;
        if (data) {
            this.logSubmittedSearch(data);
        }
    }

    // Fire-and-forget search analytics: one row per submitted term (the term
    // only changes on Enter / "See all"), zero-result included. searchAll is
    // cacheable Apex, so it can't log server-side.
    logSubmittedSearch(results) {
        const term = (this.term || '').trim();
        if (!term || term === this._lastLoggedTerm) {
            return;
        }
        this._lastLoggedTerm = term;
        const top = results.length ? results[0] : null;
        // JSON-string transport (org gotcha: custom-type params arrive null).
        logSearch({
            entryJson: JSON.stringify({
                term,
                resultCount: results.length,
                topResultArticleId: top && top.type === 'article' ? top.id : null,
                searchType: 'Full',
                sessionKey: getSessionKey()
            })
        }).catch(() => {});
    }

    get resources() {
        return (this.results || []).filter((r) => r.type === 'resource');
    }
    get articles() {
        const raw = this.helpCenterBaseUrl || this.resolvedHelpBase;
        const base = raw ? raw.replace(/\/$/, '') : null;
        return (this.results || [])
            .filter((r) => r.type === 'article')
            .map((a) => ({
                ...a,
                // Query-param deep link — the site has no /article/ route.
                href: base && a.urlName ? `${base}/?article=${encodeURIComponent(a.urlName)}` : null
            }));
    }
    get hasResources() {
        return this.resources.length > 0;
    }
    get hasArticles() {
        return this.articles.length > 0;
    }
    get isEmpty() {
        return !this.loading && !this.hasResources && !this.hasArticles;
    }

    handleResource(event) {
        const slug = event.currentTarget.dataset.slug;
        this.dispatchEvent(new CustomEvent('resourceselect', {
            detail: { slug }, bubbles: true, composed: true
        }));
    }
}