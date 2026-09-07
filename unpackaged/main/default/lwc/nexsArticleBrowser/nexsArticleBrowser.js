import { LightningElement, api, wire, track } from 'lwc';
import getCategoryTree from '@salesforce/apex/NexSKnowledgeController.getCategoryTree';
import getArticlesByCategory from '@salesforce/apex/NexSKnowledgeController.getArticlesByCategory';
import searchRanked from '@salesforce/apex/NexSKnowledgeController.searchRanked';
import getFallbackArticles from '@salesforce/apex/NexSKnowledgeController.getFallbackArticles';
import getArticle from '@salesforce/apex/NexSKnowledgeController.getArticle';
import getSupportSettings from '@salesforce/apex/NexSKnowledgeController.getSupportSettings';
import getArticleByUrlName from '@salesforce/apex/NexSKnowledgeController.getArticleByUrlName';
// Shared Help_Topics icon paths (rendered with stroke=currentColor).
import { topicIconPath } from 'c/nexsTopicIcons';
// Escaped match-highlight segments (no innerHTML — injection-safe).
import { highlightSegments } from 'c/nexsHighlight';
// One shared analytics path (dedup + App__c tagging live there).
import { createSearchLogger, logResultClick, APP_HELP_CENTER } from 'c/searchLogUtil';
// The Help_Topics tree (any depth): nav rows, ancestor crumbs, scope labels,
// the subtopic pill rows and the per-article path tags.
import {
    indexTree, findNode, ancestorsOf, rootOf, filterRows, inSubtree, pathTag, pluralize
} from 'c/treeUtil';

const TOPIC_CRUMB = 'topic:';
/** The Type facet's "everything" value (chip values are record-type labels). */
const TYPE_ALL = 'all';

/** An ArticleSummary as a c-ds-item-list row. */
function rowOf(a) {
    return { id: a.id, title: a.title, routeKey: a.urlName, featured: Boolean(a.featured) };
}

/**
 * nexsArticleBrowser
 *
 * Hulu-style help browser: persistent left Data Category nav (c-ds-tree), a
 * prominent search bar, and a main panel that shows the TOP-LEVEL topic of
 * the selected node — its title, cascading subtopic pill rows
 * (c-subtopic-filter-rows: the topic's children, then the selected child's
 * children, and so on), a count line with a compact Type facet, and every
 * article in the selected node's subtree as one flat list (c-ds-item-list)
 * with a path tag per row saying where it lives relative to the selection.
 * Filtering, not drilling (2026-09-07; the section-card grid is gone): the
 * selected topic is the one source of truth — a pill, a path tag, a sidebar
 * row and a breadcrumb all land in selectCategory, and a routed host mirrors
 * it into ?topic= so Back/Forward restore the pill state. The browse list is
 * fetched ONCE per top-level topic (getArticlesByCategory on the root, BELOW
 * scoped, every row naming its categories) and narrowed client-side with
 * c/treeUtil; moving between subtopics of one topic never refetches. Search
 * results keep their single collapsible section. Selecting an article shows
 * nexsArticleViewer inline. A "Need more help?" contact band sits at the
 * bottom.
 *
 * Dual-context note: the viewer renders inline (a state swap) rather than
 * navigating, so this one component is drop-in for both the Experience Cloud
 * LWR site and a core Lightning App page without surface detection.
 *
 * Initial state: the host (nexsLanding's home view) can hand off a category,
 * article, or search term to land on. Applied once, when the category wire
 * first resolves. The "Help Center" breadcrumb dispatches a `home` event for
 * hosts that have a home view; standalone it just falls back to the list.
 */
export default class NexsArticleBrowser extends LightningElement {
    /** Data Category API name to open instead of the first category. */
    @api initialCategory;
    /** Article to open immediately (e.g. a "Popular Articles" click). */
    @api initialArticleId;
    /** Article UrlName to open immediately — the ?article= deep-link path
     *  (resolved via getArticleByUrlName; unknown names land on browse). */
    @api initialArticleUrlName;
    /** Search term to run immediately (e.g. the home hero's search). */
    @api initialSearchTerm;
    /**
     * Opt-in for routed hosts (the LWR site): when true, clicking an article row
     * dispatches `articleselect {articleId, urlName}` instead of opening the
     * viewer inline, so the host can navigate to /article/<UrlName>. Defaults
     * false, so the core app tab keeps opening articles inline unchanged.
     */
    @api navigateOnArticleSelect = false;
    /** Zero-results "contact support" CTA target + label. Defaults to the
     *  Resource_Center_Setting__mdt support mailbox; hidden with no target. */
    @api contactSupportUrl;
    @api contactSupportLabel = 'Contact support';

    supportSettings;

    @wire(getSupportSettings)
    wiredSupportSettings({ data }) {
        if (data) {
            this.supportSettings = data;
        }
    }

    get zeroCtaUrl() {
        if (this.contactSupportUrl) {
            return this.contactSupportUrl;
        }
        const email = this.supportSettings && this.supportSettings.supportEmail;
        return email ? 'mailto:' + email : null;
    }
    _initialApplied = false;

    // Fuzzy-correction transparency for the current search.
    fuzzy = false;
    corrected = '';
    _disableFuzzy = false; // set by the "search for {original} instead" link
    @track fallbackArticles = [];

    /** Every topic at any depth as {name, label}, in tree order (roots first
        under each branch) — what selection, landing and lookups key off. */
    @track categories = [];
    /** Top-level nodes of the Help_Topics tree for c-ds-tree (icons added). */
    navRoots = [];
    _tree = indexTree([]);
    navOpen = false; // phone-width topic drawer
    _focusTree = false;
    /** Category API name a search is scoped to (BELOW = its subtree); null = all. */
    searchScope = null;
    /** Search results (searchRanked). Browse rows live in browseArticles. */
    @track articles = [];
    @track sections = [];
    /** The browse list: every article under the top-level topic of the
        selected node (`_browseRoot`), narrowed by the getters below. */
    browseArticles = [];
    _browseRoot = null;
    _browseLoading = false;
    _browseSeq = 0;
    typeFilter = TYPE_ALL;
    selectedCategory;
    selectedCategoryLabel = '';
    selectedArticleId;
    articleTitle = ''; // breadcrumb leaf; fed by the viewer's articleload event
    suggestedArticles = []; // "Suggested Articles" rail; also from articleload
    articleHasEmbed = false; // embed articles hide the rail + go full width
    articleHasResources = false; // "Downloads & Resources" rail card; from resourcesload
    searchTerm = '';
    mode = 'category'; // 'category' | 'search'
    loadingArticles = false;
    _pendingScrollTop = false; // scroll back to the top when an article opens
    _prefetched = new Set(); // article ids whose bodies we've warmed on hover
    _lastSearchLogId = null; // Article_Search__c Id of the current search, for click correlation
    _searchLogger = createSearchLogger(APP_HELP_CENTER);

    @wire(getCategoryTree)
    wiredCategories({ data, error }) {
        if (data) {
            const roots = data.roots || [];
            this._tree = indexTree(roots);
            this.navRoots = roots.map((r) => ({ ...r, iconPath: topicIconPath(r.id) }));
            this.categories = this._tree.ordered.map((n) => ({ name: n.id, label: n.label }));
            if (!this._initialApplied) {
                this._initialApplied = true;
                this.applyInitialState(this.categories);
            }
        } else if (error) {
            // eslint-disable-next-line no-console
            console.error('nexsArticleBrowser category load error', error);
        }
    }

    // Land on the host-requested search/category/article, or default to the
    // first category (the original behavior).
    applyInitialState(categories) {
        if (this.initialSearchTerm) {
            this.searchTerm = this.initialSearchTerm;
            this.mode = 'search';
            this.runSearch();
            return;
        }
        const initial = this.initialCategory
            ? categories.find((c) => c.name === this.initialCategory)
            : null;
        const landing = initial || categories[0];
        // A routed host can drive us to an article (openArticleById /
        // openArticleByUrlName) before the taxonomy lands. Select the landing
        // topic so the list behind is populated, but never clear the article
        // it asked for — selectCategory blanks selectedArticleId.
        const hostDriven = this._openSeq > 0;
        const hostArticleId = this.selectedArticleId;
        if (landing) {
            this.selectCategory(landing.name, landing.label);
        }
        if (hostDriven) {
            if (hostArticleId) {
                this.selectedArticleId = hostArticleId;
            }
            return; // the host owns the article slot
        }
        if (this.initialArticleId) {
            this.openArticleById(this.initialArticleId);
        } else if (this.initialArticleUrlName) {
            // Through the guarded @api so overlapping lookups can't fight.
            this.openArticleByUrlName(this.initialArticleUrlName);
        }
    }

    /** The c-ds-tree active row: the selected topic while browsing it. */
    get navActiveKey() {
        return this.mode === 'category' ? this.selectedCategory : null;
    }

    get navClass() {
        return this.navOpen ? 'nexs__nav nexs__nav--open' : 'nexs__nav';
    }

    get navToggleLabel() {
        return this.navOpen ? 'Hide topics' : 'Browse topics';
    }

    get navToggleExpanded() {
        return this.navOpen ? 'true' : 'false';
    }

    /** The browse view's title: the topic being read (search has its own banner). */
    get showTitle() {
        return this.mode === 'category' && !this.showViewer && Boolean(this.selectedCategory);
    }

    /** The selected topic's node in the Help_Topics index (null until both
        the tree and a selection exist). */
    get selectedNode() {
        return findNode(this._tree, this.selectedCategory);
    }

    /** The top-level topic the browse page is titled after. */
    get rootNode() {
        const node = this.selectedNode;
        return node ? rootOf(this._tree, node.id) : null;
    }

    /** A pill (or deep link) has narrowed the page below its topic. */
    get isNarrowed() {
        const node = this.selectedNode;
        const root = this.rootNode;
        return Boolean(node && root && node.id !== root.id);
    }

    /** The browse view's h1: the top-level topic (the selected topic until
        the tree lands). */
    get browseTitle() {
        const root = this.rootNode;
        return root ? root.label : this.selectedCategoryLabel;
    }

    /** c-subtopic-filter-rows input: the selected path's rows, from the tree. */
    get filterRowsData() {
        const node = this.selectedNode;
        return node ? filterRows(this._tree, node.id) : [];
    }

    get showFilterRows() {
        return this.showTitle && this.filterRowsData.length > 0;
    }

    /** The browse list narrowed to the selected node's subtree. A row from
        an older server without `categories` is kept rather than dropped. */
    get subtreeArticles() {
        const node = this.selectedNode;
        const rows = this.browseArticles || [];
        if (!node) {
            return rows;
        }
        return rows.filter((a) => !a.categories || inSubtree(this._tree, a.categories, node.id));
    }

    typeOf(a) {
        return a.recordTypeLabel || a.recordType || 'Article';
    }

    /** …then by type, each row carrying its path tag relative to the selection. */
    get browseRows() {
        const node = this.selectedNode;
        return this.subtreeArticles
            .filter((a) => this.typeFilter === TYPE_ALL || this.typeOf(a) === this.typeFilter)
            .map((a) => {
                const tag = node ? pathTag(this._tree, a.categories || [], node.id) : null;
                return tag ? { ...rowOf(a), pathLabel: tag.label, pathKey: tag.key } : rowOf(a);
            });
    }

    /** The Type facet: one chip per record type present in the selected
        subtree (live counts), All first; hidden when there is only one. */
    get typeChips() {
        const counts = new Map();
        this.subtreeArticles.forEach((a) => {
            const type = this.typeOf(a);
            counts.set(type, (counts.get(type) || 0) + 1);
        });
        if (counts.size < 2) {
            return [];
        }
        const types = [...counts.keys()].sort((a, b) => a.localeCompare(b));
        return [
            { value: TYPE_ALL, label: 'All', count: this.subtreeArticles.length },
            ...types.map((type) => ({ value: type, label: type, count: counts.get(type) }))
        ];
    }

    get showTypeChips() {
        return this.typeChips.length > 0;
    }

    /** "12 articles" / "4 articles in Shortcuts" / "2 How-to articles in Shortcuts". */
    get countLine() {
        const noun = this.typeFilter === TYPE_ALL ? 'article' : `${this.typeFilter} article`;
        const text = pluralize(this.browseRows.length, noun);
        return this.isNarrowed ? `${text} in ${this.selectedCategoryLabel}` : text;
    }

    /** Count line + Type facet: whenever the selected subtree has anything. */
    get showToolbar() {
        return this.showTitle && !this.loadingArticles && this.subtreeArticles.length > 0;
    }

    get showList() {
        return this.showToolbar && this.browseRows.length > 0;
    }

    /** The subtree has articles, just none of the chosen type. */
    get showTypeEmpty() {
        return this.showToolbar && this.browseRows.length === 0;
    }

    get typeEmptyText() {
        const where = this.isNarrowed ? ` in ${this.selectedCategoryLabel}` : '';
        return `No ${this.typeFilter} articles${where}.`;
    }

    /** Crumb trail for the shared c-ds-breadcrumbs — Help Center › ancestors…
        › topic, then three states: list view (current heading), viewer while
        the title loads (clickable heading, no leaf), viewer with title. */
    get crumbItems() {
        const crumbs = [{ label: 'Help Center', key: 'home' }];
        if (this.mode === 'category' && this.selectedCategory) {
            ancestorsOf(this._tree, this.selectedCategory).forEach((a) => {
                crumbs.push({ label: a.label, key: TOPIC_CRUMB + a.id });
            });
        }
        if (!this.showViewer) {
            crumbs.push({ label: this.panelHeading });
        } else {
            crumbs.push({ label: this.panelHeading, key: 'back' });
            if (this.articleTitle) {
                crumbs.push({ label: this.articleTitle });
            }
        }
        return crumbs;
    }

    get showViewer() {
        return !!this.selectedArticleId;
    }

    // Article view gets a wider container + breadcrumb inset (Hulu-like); the
    // list/category view keeps the breadcrumb aligned to the section cards.
    get nexsClass() {
        return this.showViewer ? 'nexs nexs--article' : 'nexs';
    }

    get hasSections() {
        return !this.loadingArticles && this.sections.length > 0;
    }

    // Category browse with nothing filed on the topic OR anywhere under it —
    // the list is BELOW-scoped, so empty means the whole subtree is empty
    // (a Type facet with no matches is showTypeEmpty, not this).
    get showEmpty() {
        return !this.loadingArticles && this.mode === 'category' && this.subtreeArticles.length === 0;
    }

    // Search that returned nothing — never blank; show fallback articles + CTA.
    get showZeroResults() {
        return !this.loadingArticles && this.mode === 'search' && this.sections.length === 0;
    }

    // "Showing results for {corrected}" banner — only on fuzzy-sourced results.
    get showFuzzyBanner() {
        return this.mode === 'search' && this.fuzzy && !!this.corrected;
    }

    get hasFallback() {
        return this.fallbackArticles.length > 0;
    }

    get fallbackView() {
        return this.fallbackArticles.map((a) => ({
            id: a.id,
            urlName: a.urlName,
            title: a.title
        }));
    }

    get panelHeading() {
        return this.mode === 'search'
            ? `Results for “${this.searchTerm}”`
            : this.selectedCategoryLabel;
    }

    get hasSuggested() {
        // Embed articles (Scribe etc.) go full width, so suggestions are suppressed.
        return this.suggestedArticles.length > 0 && !this.articleHasEmbed;
    }

    get showRail() {
        // Resources still get the rail on embed articles — dropping them there
        // would silently hide attached files.
        return this.hasSuggested || this.articleHasResources;
    }

    get articleLayoutClass() {
        return this.showRail
            ? 'nexs__article-layout'
            : 'nexs__article-layout nexs__article-layout--single';
    }

    // Decorate sections with chevron icon + open class for the template.
    get sectionView() {
        const highlightTerm = this.mode === 'search' ? this.searchTerm : '';
        const inSearch = this.mode === 'search';
        return this.sections.map((s) => ({
            ...s,
            iconName: s.open ? 'utility:chevrondown' : 'utility:chevronright',
            ariaExpanded: s.open ? 'true' : 'false',
            bodyClass: s.open ? 'nexs__section-body' : 'nexs__section-body nexs__section-body--collapsed',
            // Enrich each row: highlighted title segments, plus a summary snippet
            // in search results only. Highlighting is off (single plain segment)
            // when browsing a category.
            articles: s.articles.map((a) => ({
                id: a.id,
                urlName: a.urlName,
                featured: a.featured,
                titleSegments: highlightSegments(a.title, highlightTerm),
                summary: a.summary,
                showSummary: inSearch && !!a.summary
            }))
        }));
    }

    // ---- Category nav --------------------------------------------------------

    /** Sidebar rows, pills and path tags all hand back a topic API name. */
    handleNavSelect(event) {
        const key = event.detail.key;
        const match = (this.categories || []).find((c) => c.name === key);
        this.selectCategory(key, match ? match.label : key);
    }

    /** c-item-path-tag's composed pathselect (from inside a list row). */
    handlePathSelect(event) {
        event.stopPropagation();
        this.handleNavSelect(event);
    }

    handleTypeSelect(event) {
        this.typeFilter = event.detail.value || TYPE_ALL;
    }

    handleTypeClear() {
        this.typeFilter = TYPE_ALL;
    }

    /** Phone-width drawer: open moves focus into the tree, close returns it. */
    handleNavToggle() {
        this.navOpen = !this.navOpen;
        this._focusTree = this.navOpen;
    }

    handleNavKeydown(event) {
        if (event.key === 'Escape' && this.navOpen) {
            this.navOpen = false;
            const toggle = this.template.querySelector('.nexs__nav-toggle');
            if (toggle) {
                toggle.focus();
            }
        }
    }

    // ---- Search scope ("Search within {topic}") ---------------------------------

    get scopeLabel() {
        const node = findNode(this._tree, this.searchScope);
        return node ? node.label : this.searchScope;
    }

    /** Offer / show the scope only on a results list that has a topic to scope to. */
    get showScopeBar() {
        return this.mode === 'search' && !this.showViewer
            && Boolean(this.searchScope || this.selectedCategory);
    }

    get scopeOfferLabel() {
        return `Search within ${this.selectedCategoryLabel}`;
    }

    handleScopeOn() {
        this.searchScope = this.selectedCategory;
        this.runSearch();
    }

    handleScopeOff() {
        this.searchScope = null;
        this.runSearch();
    }

    selectCategory(name, label) {
        this.selectedCategory = name;
        this.selectedCategoryLabel = label || name;
        this.mode = 'category';
        this.navOpen = false;
        this.searchScope = null;
        this.selectedArticleId = null;
        this.articleTitle = '';
        this._lastSearchLogId = null; // leaving search mode — don't attribute clicks to a stale search
        this.leaveSearch();
        // Routed hosts mirror the topic into ?topic= so Back/Forward walk the
        // tree too (mirror of articleopen). Non-routed hosts don't listen.
        this.dispatchEvent(new CustomEvent('topicchange', {
            detail: { name, label: this.selectedCategoryLabel }
        }));
        this.loadArticles();
    }

    /** Drop search state (and outrun a search still in flight) so the browse
        view never shows a results section that lands late. */
    leaveSearch() {
        this._articlesSeq += 1;
        this.articles = [];
        this.sections = [];
        this.fallbackArticles = [];
    }

    /**
     * Stale-response guard for every path that writes `articles` — a search
     * or a scope change. A reader who searches again before the first list
     * lands would otherwise get whichever request happened to resolve last,
     * which is not necessarily the one on screen.
     */
    _articlesSeq = 0;

    /** The topic whose subtree the browse list holds: the selected topic's
        top-level ancestor once the tree is known, the topic itself before. */
    browseRootFor(name) {
        const root = rootOf(this._tree, name);
        return root ? root.id : name;
    }

    /**
     * Fetch the browse list for the selected topic's top-level topic — once.
     * Selecting another node under the same root just re-narrows what is
     * already here (the getters key off selectedCategory), so pills, path
     * tags and the sidebar never wait on the server.
     */
    async loadArticles() {
        const root = this.browseRootFor(this.selectedCategory);
        if (root === this._browseRoot) {
            this.loadingArticles = this._browseLoading;
            return;
        }
        const seq = ++this._browseSeq;
        this._browseRoot = root;
        this.browseArticles = [];
        this._browseLoading = true;
        this.loadingArticles = true;
        try {
            const rows = await getArticlesByCategory({ category: root });
            if (seq !== this._browseSeq) {
                return;
            }
            this.browseArticles = rows || [];
        } catch (e) {
            if (seq !== this._browseSeq) {
                return;
            }
            this.browseArticles = [];
            this._browseRoot = null; // let the next selection retry
            // eslint-disable-next-line no-console
            console.error('nexsArticleBrowser article load error', e);
        } finally {
            if (seq === this._browseSeq) {
                this._browseLoading = false;
                if (this.mode === 'category') {
                    this.loadingArticles = false;
                }
            }
        }
    }

    // ---- Search --------------------------------------------------------------
    // The search bar lives in the host's header (nexsLanding) since the browser
    // no longer renders one; these @api methods let the host drive it.

    /** Open an article directly (e.g. a header-search suggestion). */
    @api
    openArticleById(articleId) {
        this._openSeq += 1; // outruns any UrlName lookup still in flight
        this.openArticle(articleId);
    }

    /** Stale-response guard for the UrlName → Id lookups below. */
    _openSeq = 0;

    /** Open an article by UrlName after mount (routed host drives this on
        popstate; unknown/unpublished names stay on the current view). */
    @api
    openArticleByUrlName(urlName) {
        if (!urlName) {
            return;
        }
        // A routed host can ask for a second article before the first name
        // resolves; only the newest lookup may open anything.
        const seq = ++this._openSeq;
        getArticleByUrlName({ urlName })
            .then((detail) => {
                if (seq === this._openSeq && detail && detail.id) {
                    this.openArticle(detail.id);
                }
            })
            .catch(() => {
                // Unknown/unpublished UrlName: stay put.
            });
    }

    /** An authored in-body link to another article (nexsArticleViewer
        `articlelink`): open it inline, exactly like a Suggested Articles pick,
        so the routed host mirrors it into ?name= via articleopen. */
    handleArticleLink(event) {
        event.stopPropagation();
        this.openArticleByUrlName(event.detail && event.detail.urlName);
    }

    /** Run a full search (blank term returns to the category list). */
    @api
    searchFor(term) {
        this.runTermSearch(term || '');
    }

    /**
     * Open a category by API name after mount (routed host drives this on URL
     * param changes; the label is resolved from the loaded taxonomy).
     */
    @api
    openCategory(name) {
        if (!name) {
            return;
        }
        const match = (this.categories || []).find((c) => c.name === name);
        this.selectCategory(name, match ? match.label : name);
    }

    runTermSearch(term) {
        if (!term.trim()) {
            this.mode = 'category';
            this._lastSearchLogId = null;
            this.leaveSearch();
            this.loadArticles();
            return;
        }
        this.searchTerm = term;
        this.mode = 'search';
        this.selectedArticleId = null;
        this.articleTitle = '';
        this._disableFuzzy = false; // a fresh query re-enables typo correction
        this.runSearch();
    }

    async runSearch() {
        const seq = ++this._articlesSeq;
        this.loadingArticles = true;
        try {
            const result = await searchRanked({
                term: this.searchTerm,
                category: this.searchScope || null, // BELOW: the whole subtree
                disableFuzzy: this._disableFuzzy
            });
            if (seq !== this._articlesSeq) {
                return; // a newer search or category load already rendered
            }
            this.articles = (result && result.articles) || [];
            // Fuzzy banner only when the engine actually corrected and the user
            // hasn't opted out via "search instead".
            this.fuzzy = !this._disableFuzzy && !!(result && result.fuzzy);
            this.corrected = (result && result.corrected) || '';
            this.buildSections();

            // Fire-and-forget search analytics: submitted searches only; capture
            // the returned log Id so a following result click correlates to it.
            this._lastSearchLogId = null;
            this._searchLogger.logFull({
                term: this.searchTerm,
                resultCount: this.articles.length,
                topResultArticleId: this.articles.length ? this.articles[0].id : null,
                // Fuzzy = the typo pass produced these results; Fallback = zero
                // results, the fallback rail is what the user actually saw.
                searchType: this.fuzzy ? 'Fuzzy'
                    : (this.articles.length === 0 ? 'Fallback' : 'Full')
            }).then((logId) => {
                this._lastSearchLogId = logId;
            });

            // Never a blank results page — load fallback articles for zero results.
            if (this.articles.length === 0) {
                this.loadFallback();
            } else {
                this.fallbackArticles = [];
            }
        } catch (e) {
            if (seq !== this._articlesSeq) {
                return;
            }
            this.articles = [];
            this.sections = [];
            this.fuzzy = false;
            this.corrected = '';
            // eslint-disable-next-line no-console
            console.error('nexsArticleBrowser search error', e);
        } finally {
            if (seq === this._articlesSeq) {
                this.loadingArticles = false;
            }
        }
    }

    async loadFallback() {
        try {
            this.fallbackArticles = (await getFallbackArticles({ category: null })) || [];
        } catch (e) {
            this.fallbackArticles = [];
        }
    }

    // "Search for {original} instead" — re-run the same term with the typo pass
    // off, so the user sees literal matches for exactly what they typed.
    handleSearchOriginal() {
        this._disableFuzzy = true;
        this.runSearch();
    }

    // ---- Sections ------------------------------------------------------------

    buildSections() {
        const rows = this.articles || [];
        // Search results stay as one open "Results" section; category browse
        // renders the pill rows + c-ds-item-list from browseArticles instead.
        this.sections = rows.length && this.mode === 'search'
            ? [{ key: 'results', title: this.panelHeading, open: true, articles: rows }]
            : [];
    }

    handleSectionToggle(event) {
        const key = event.currentTarget.dataset.key;
        this.sections = this.sections.map((s) =>
            s.key === key ? { ...s, open: !s.open } : s
        );
    }

    // ---- Article view --------------------------------------------------------

    handleArticleClick(event) {
        event.preventDefault(); // rows are anchors; don't jump the page
        const { id, urlname } = event.currentTarget.dataset;
        this.openArticleRow(id, urlname);
    }

    /** c-ds-item-list rows (category browse). */
    handleListSelect(event) {
        this.openArticleRow(event.detail.id, event.detail.routeKey);
    }

    handleListHover(event) {
        this.prefetch(event.detail.id);
    }

    openArticleRow(id, urlName) {
        this.logResultClick(id);
        if (this.navigateOnArticleSelect) {
            this.dispatchEvent(
                new CustomEvent('articleselect', { detail: { articleId: id, urlName } })
            );
            return;
        }
        this.openArticle(id);
    }

    // Correlate a result click back to the search that produced it (search mode
    // only). Fire-and-forget; rank is the clicked article's 1-based position in
    // the result list. No-op when the click didn't follow a search.
    logResultClick(articleId) {
        if (this.mode !== 'search' || !this._lastSearchLogId || !articleId) {
            return;
        }
        const idx = (this.articles || []).findIndex((a) => a.id === articleId);
        logResultClick(this._lastSearchLogId, articleId, idx >= 0 ? idx + 1 : null);
    }

    // Warm the article body cache on hover/focus so the click feels instant.
    // getArticle is cacheable, so the viewer's later call is served from cache.
    handlePrefetch(event) {
        this.prefetch(event.currentTarget.dataset.id);
    }

    prefetch(id) {
        if (!id || this._prefetched.has(id)) {
            return;
        }
        this._prefetched.add(id);
        getArticle({ articleId: id }).catch(() => this._prefetched.delete(id));
    }

    openArticle(articleId) {
        this.selectedArticleId = articleId;
        // Crumb and rail stay blank until the viewer reports in.
        this.articleTitle = '';
        this.suggestedArticles = [];
        this.articleHasEmbed = false;
        this.articleHasResources = false;
        // Opening an article is a state swap, not a page nav, so the browser
        // keeps the old scroll position (e.g. after a suggested-article click
        // from the bottom). Flag a scroll-to-top for the next render.
        this._pendingScrollTop = true;
    }

    renderedCallback() {
        if (this._focusTree) {
            this._focusTree = false;
            const tree = this.template.querySelector('c-ds-tree');
            if (tree && typeof tree.focusActive === 'function') {
                tree.focusActive();
            }
        }
        if (!this._pendingScrollTop) {
            return;
        }
        this._pendingScrollTop = false;
        // scrollIntoView traverses the flat tree, so it scrolls whichever
        // ancestor scrolls (the window on the LWR site, the tab container in the
        // core app). scroll-margin-top on .nexs clears the sticky header.
        this.template.querySelector('.nexs')?.scrollIntoView({ block: 'start' });
    }

    handleArticleLoad(event) {
        this.articleTitle = event.detail.title;
        this.suggestedArticles = event.detail.suggestions || [];
        this.articleHasEmbed = !!event.detail.hasEmbed;
        // Notify routed hosts on EVERY viewer navigation (search click, rail
        // suggestion, deep link) so they can sync the URL. Non-routed hosts
        // simply don't listen.
        this.dispatchEvent(new CustomEvent('articleopen', {
            detail: { articleId: this.selectedArticleId, urlName: event.detail.urlName || null }
        }));
    }

    handleResourcesLoad(event) {
        this.articleHasResources = event.detail.count > 0;
    }

    handleBack(event) {
        if (event) {
            event.preventDefault(); // crumbs are anchors; don't jump the page
        }
        const wasViewing = Boolean(this.selectedArticleId);
        this.selectedArticleId = null;
        this.articleTitle = '';
        this.suggestedArticles = [];
        this.articleHasEmbed = false;
        this.articleHasResources = false;
        if (wasViewing) {
            // Mirror of articleopen — routed hosts clear the ?name= param.
            this.dispatchEvent(new CustomEvent('articleclose'));
        }
    }

    // "Help Center" crumb: let a hosting home view take over; the internal
    // back-to-list is the fallback when nothing is listening (standalone use).
    // The topic crumb ('back') returns from the article to its topic list; an
    // ancestor crumb ('topic:<name>') opens that topic's own list.
    handleCrumbSelect(event) {
        const key = event.detail.key || '';
        if (key === 'home') {
            this.dispatchEvent(new CustomEvent('home'));
            this.handleBack();
        } else if (key === 'back') {
            this.handleBack();
        } else if (key.startsWith(TOPIC_CRUMB)) {
            this.handleBack();
            this.openCategory(key.slice(TOPIC_CRUMB.length));
        }
    }
}