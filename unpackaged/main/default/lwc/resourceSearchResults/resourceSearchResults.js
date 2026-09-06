import { LightningElement, api, wire } from 'lwc';
import search from '@salesforce/apex/UnifiedSearchService.search';
import searchResources from '@salesforce/apex/ResourceCenterService.searchResources';
import getCategoryTree from '@salesforce/apex/ResourceCenterService.getCategoryTree';
import { createSearchLogger, APP_RESOURCE_CENTER } from 'c/searchLogUtil';
import { linkContext, goToArticle } from 'c/contextNav';
import { toContentItem } from 'c/rcConstants';
import { iconPath } from 'c/rcIcons';
import { indexTree, findNode } from 'c/treeUtil';

/**
 * resourceSearchResults — the shared cross-app results view: grouped Articles /
 * Resources sections (ranked within each by UnifiedSearchService), rendered as
 * c-ds-content-card tiles, with a category facet (shared c-ds-tree) in the
 * left rail. Picking any node — at any depth — scopes the RESOURCE hits to
 * that category's subtree ("Also show in" placements included) through
 * ResourceCenterService.searchResources; articles live in a different
 * taxonomy, so a scoped view lists resources only and says so. The scope is
 * the host's state (`scope` = category slug) so it round-trips through the
 * URL; the facet asks for changes with `searchscope { slug|null }`.
 *
 * Resources open in-site (emits `resourceselect { slug }`) unless their action
 * leaves the site (External Link, an upcoming webinar's "Sign up") —
 * rcConstants.toContentItem decides, same as every other card grid. Articles
 * carry an href deep link into the Help Center. Either side can be degraded
 * (no access / backend fault) — the other still renders, with a quiet notice
 * instead of a hard error.
 */
export default class ResourceSearchResults extends LightningElement {
    /** Optional override; defaults to the site root resolved server-side. */
    @api helpCenterBaseUrl;

    _term;
    _scope;

    @api
    get term() {
        return this._term;
    }
    set term(value) {
        this._term = value;
        this.load();
    }

    /** Category slug the resource hits are scoped to; null/undefined = all. */
    @api
    get scope() {
        return this._scope;
    }
    set scope(value) {
        this._scope = value || null;
        this.load();
    }

    /** {surface, helpBase, resourceBase} from c/contextNav; null until resolved. */
    linkCtx = null;

    facetRoots = [];
    _facetTree = indexTree([]);

    @wire(getCategoryTree)
    wiredTree({ data }) {
        if (data) {
            this.facetRoots = (data.roots || []).map((r) => ({ ...r, iconPath: iconPath(r.iconName) }));
            this._facetTree = indexTree(this.facetRoots);
        }
    }

    connectedCallback() {
        linkContext().then((ctx) => {
            this.linkCtx = ctx;
        });
        this._connected = true;
        this.load();
    }

    articleHits = [];
    resourceHits = [];
    meta = {};
    loading = true;
    _connected = false;
    _seq = 0;
    // Fire-and-forget analytics: one row per submitted term (searchLogUtil
    // dedupes consecutive repeats, so a scope change on the same term does
    // not log twice). search is cacheable Apex, so it can't log server-side.
    _searchLogger = createSearchLogger(APP_RESOURCE_CENTER);

    disconnectedCallback() {
        this._connected = false;
        this._searchLogger.dispose();
    }

    /** Unscoped: the unified search. Scoped: resources only, in the subtree. */
    load() {
        if (!this._connected) {
            return;
        }
        const term = (this._term || '').trim();
        const seq = ++this._seq;
        if (!term) {
            this.apply({ articles: [], resources: [], meta: {} });
            return;
        }
        this.loading = true;
        const request = this._scope
            ? searchResources({ term, categorySlug: this._scope })
                .then((rows) => ({ articles: [], resources: rows || [], meta: {} }))
            : search({ term });
        request
            .then((data) => {
                if (seq === this._seq) {
                    this.apply(data || {});
                }
            })
            .catch(() => {
                if (seq === this._seq) {
                    this.apply({ articles: [], resources: [], meta: { articlesDegraded: true, resourcesDegraded: true } });
                }
            });
    }

    apply(data) {
        this.articleHits = data.articles || [];
        this.resourceHits = data.resources || [];
        this.meta = data.meta || {};
        this.loading = false;
        const term = (this._term || '').trim();
        if (!term) {
            return;
        }
        this._searchLogger.logFull({
            term,
            resultCount: this.articleHits.length + this.resourceHits.length,
            topResultArticleId: this.articleHits.length ? this.articleHits[0].id : null,
            searchType: this.meta.fuzzy ? 'Fuzzy' : 'Full'
        });
    }

    // ---- View model ----------------------------------------------------------

    get resourceItems() {
        return this.resourceHits.map(toContentItem);
    }

    /** Articles carry NO href on purpose — dsContentCard reserves that for
        links that truly leave the site. See handleContentSelect. */
    get articleItems() {
        return this.articleHits.map((a) => ({
            kind: 'article',
            id: a.id,
            title: a.title,
            subtitle: a.summary,
            routeKey: a.urlName
        }));
    }

    get hasResources() {
        return this.resourceHits.length > 0;
    }
    get hasArticles() {
        return this.articleHits.length > 0;
    }
    get isEmpty() {
        return !this.loading && !this.hasResources && !this.hasArticles;
    }
    get articlesDegraded() {
        return this.meta.articlesDegraded === true;
    }
    get resourcesDegraded() {
        return this.meta.resourcesDegraded === true;
    }
    get showFuzzy() {
        return this.meta.fuzzy === true && Boolean(this.meta.corrected);
    }

    get scopeNode() {
        if (!this._scope) {
            return null;
        }
        return this._facetTree.ordered.find((n) => n.slug === this._scope) || null;
    }
    get scopeLabel() {
        const node = this.scopeNode;
        return node ? node.label : this._scope;
    }
    get isScoped() {
        return Boolean(this._scope);
    }
    get scopeKey() {
        const node = this.scopeNode;
        return node ? node.id : null;
    }
    get hasFacets() {
        return this.facetRoots.length > 0;
    }
    get allClass() {
        return this._scope ? 'rsr__all' : 'rsr__all rsr__all--active';
    }
    get allPressed() {
        return this._scope ? 'false' : 'true';
    }
    get emptyMessage() {
        return this._scope
            ? `No resources in ${this.scopeLabel} matched your search.`
            : 'No resources or articles matched your search.';
    }

    // ---- Handlers ------------------------------------------------------------

    handleContentSelect(event) {
        event.stopPropagation();
        if (event.detail.kind === 'article') {
            // No mixin here, so contextNav takes its event rung and the
            // host routes. Previously this branch returned early and the
            // click was simply dropped.
            goToArticle(this, this.linkCtx, { urlName: event.detail.routeKey });
            return;
        }
        this.dispatchEvent(new CustomEvent('resourceselect', {
            detail: { slug: event.detail.routeKey }, bubbles: true, composed: true
        }));
    }

    handleFacetSelect(event) {
        const node = findNode(this._facetTree, event.detail.key);
        this.emitScope(node ? node.slug : null);
    }

    handleScopeClear() {
        this.emitScope(null);
    }

    /** The host owns the scope (it lives in the URL); we only ask. */
    emitScope(slug) {
        this.dispatchEvent(new CustomEvent('searchscope', {
            detail: { slug }, bubbles: true, composed: true
        }));
    }
}