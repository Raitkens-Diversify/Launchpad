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
// section cards and the own/inherited article split.
import { indexTree, findNode, ancestorsOf } from 'c/treeUtil';

const TOPIC_CRUMB = 'topic:';
const PREVIEW_MAX = 3;

/** An ArticleSummary as a c-ds-item-list row. */
function rowOf(a) {
    return { id: a.id, title: a.title, routeKey: a.urlName, featured: Boolean(a.featured) };
}

/**
 * nexsArticleBrowser
 *
 * Hulu-style help browser: persistent left Data Category nav (c-ds-tree), a
 * prominent search bar, and a main panel that shows the topic's branch as
 * section cards (c-ds-section-cards: one per direct child, any depth) over
 * the topic's own articles — or, when it has none of its own, the articles
 * inherited from its children grouped under linked child headings
 * (c-ds-item-list). Search results keep their single collapsible section.
 * Selecting an article shows nexsArticleViewer inline. A "Need more help?"
 * contact band sits at the bottom.
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
    @track articles = [];
    @track sections = [];
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
        if (landing) {
            this.selectCategory(landing.name, landing.label);
        }
        if (this.initialArticleId) {
            this.openArticle(this.initialArticleId);
        } else if (this.initialArticleUrlName) {
            getArticleByUrlName({ urlName: this.initialArticleUrlName })
                .then((detail) => {
                    if (detail && detail.id) {
                        this.openArticle(detail.id);
                    }
                })
                .catch(() => {
                    // Unknown/unpublished UrlName: stay on the browse landing.
                });
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

    /** Articles the topic list holds under one direct child: the list comes
        back BELOW the topic with `section` = that child's label (a grandchild
        filing groups under the child it hangs from). */
    articlesUnder(child) {
        return (this.articles || []).filter((a) => a.section != null && a.section === child.label);
    }

    /** Section cards: the topic's direct children (tree nodes — the card
        prints countLine() from them) plus a preview of the first titles
        under each. The Help_Topics tree is unpruned, so an empty subtopic
        still cards, reading "0 articles", as it does in the sidebar. */
    get sectionCardItems() {
        const node = this.selectedNode;
        return ((node && node.children) || []).map((child) => ({
            ...child,
            key: child.id,
            preview: this.articlesUnder(child).slice(0, PREVIEW_MAX).map((a) => ({ id: a.id, title: a.title }))
        }));
    }

    get showSectionCards() {
        return this.showTitle && this.sectionCardItems.length > 0;
    }

    /** Articles filed on the topic itself (no subtopic section). */
    get ownArticles() {
        return (this.articles || []).filter((a) => a.section == null).map(rowOf);
    }

    get ownHeading() {
        return `Articles in ${this.selectedCategoryLabel}`;
    }

    /** Inherited articles grouped by the direct child each hangs from —
        offered only when the topic has nothing of its own, so a branch page
        never dead-ends on "No articles here yet" while content sits below. */
    get inheritedGroups() {
        if (this.ownArticles.length) {
            return [];
        }
        const node = this.selectedNode;
        return ((node && node.children) || [])
            .map((child) => ({ key: child.id, label: child.label, items: this.articlesUnder(child).map(rowOf) }))
            .filter((g) => g.items.length > 0);
    }

    get showList() {
        return this.showTitle && !this.loadingArticles
            && (this.ownArticles.length > 0 || this.inheritedGroups.length > 0);
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
    // the list is BELOW-scoped, so empty means the whole subtree is empty.
    get showEmpty() {
        return !this.loadingArticles && this.mode === 'category' && (this.articles || []).length === 0;
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

    handleNavSelect(event) {
        const key = event.detail.key;
        const match = (this.categories || []).find((c) => c.name === key);
        this.selectCategory(key, match ? match.label : key);
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
        // Routed hosts mirror the topic into ?topic= so Back/Forward walk the
        // tree too (mirror of articleopen). Non-routed hosts don't listen.
        this.dispatchEvent(new CustomEvent('topicchange', {
            detail: { name, label: this.selectedCategoryLabel }
        }));
        this.loadArticles();
    }

    async loadArticles() {
        this.loadingArticles = true;
        try {
            this.articles = await getArticlesByCategory({ category: this.selectedCategory });
            this.buildSections();
        } catch (e) {
            this.articles = [];
            this.sections = [];
            // eslint-disable-next-line no-console
            console.error('nexsArticleBrowser article load error', e);
        } finally {
            this.loadingArticles = false;
        }
    }

    // ---- Search --------------------------------------------------------------
    // The search bar lives in the host's header (nexsLanding) since the browser
    // no longer renders one; these @api methods let the host drive it.

    /** Open an article directly (e.g. a header-search suggestion). */
    @api
    openArticleById(articleId) {
        this.openArticle(articleId);
    }

    /** Open an article by UrlName after mount (routed host drives this on
        popstate; unknown/unpublished names stay on the current view). */
    @api
    openArticleByUrlName(urlName) {
        if (!urlName) {
            return;
        }
        getArticleByUrlName({ urlName })
            .then((detail) => {
                if (detail && detail.id) {
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
        this.loadingArticles = true;
        try {
            const result = await searchRanked({
                term: this.searchTerm,
                category: this.searchScope || null, // BELOW: the whole subtree
                disableFuzzy: this._disableFuzzy
            });
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
            this.articles = [];
            this.sections = [];
            this.fuzzy = false;
            this.corrected = '';
            // eslint-disable-next-line no-console
            console.error('nexsArticleBrowser search error', e);
        } finally {
            this.loadingArticles = false;
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
        // renders c-ds-section-cards + c-ds-item-list straight from `articles`.
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