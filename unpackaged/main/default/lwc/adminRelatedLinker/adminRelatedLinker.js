import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { resourceDetailUrl, copyText } from 'c/rcLinkUtil';
import searchArticlesForPicker from '@salesforce/apex/ArticleAdminController.searchArticlesForPicker';
import searchResourcesForPicker from '@salesforce/apex/ArticleAdminController.searchResourcesForPicker';
import searchArticlesForLink from '@salesforce/apex/ResourceAdminController.searchArticlesForLink';

/**
 * adminRelatedLinker — search-and-attach list builder for the Admin Console.
 * Kills the hand-typed-Id failure mode: admins pick from live search results
 * and the server resolves stable identifiers.
 *
 * @api searchType 'resources' | 'articles' (value = UrlName, for suggested rails)
 *                 | 'articleLinks' (value = stable KA Id, for junction rows)
 * @api items      [{ value, label, sublabel, slug? }] currently attached, in order
 * @api label      heading shown above the list
 * @api placeholder search input placeholder
 * @api copyLinkBase when set (resource linkers), attached items with a slug get
 *                 a "Copy link" button producing {base}?rcview=detail&rcslug=…
 *                 for pasting into the article body's rich-text link tool
 *
 * Emits `itemschange` { items } (full item objects, in order) on every change.
 */
const DEBOUNCE_MS = 250;

export default class AdminRelatedLinker extends LightningElement {
    @api searchType = 'resources';
    @api label = 'Related content';
    @api placeholder = 'Search…';
    @api copyLinkBase;

    term = '';
    results = [];
    searching = false;

    _items = [];
    _timer;

    @api
    get items() {
        return this._items;
    }
    set items(value) {
        this._items = (value || []).map((i) => ({ ...i }));
    }

    get viewItems() {
        const last = this._items.length - 1;
        return this._items.map((item, index) => ({
            ...item,
            index,
            isFirst: index === 0,
            isLast: index === last,
            copyUrl: resourceDetailUrl(this.copyLinkBase, item.slug)
        }));
    }

    get hasItems() {
        return this._items.length > 0;
    }

    get hasResults() {
        return this.results.length > 0;
    }

    // ---- Search -----------------------------------------------------------------

    handleTermChange(event) {
        this.term = event.target.value;
        window.clearTimeout(this._timer);
        const value = this.term;
        this._timer = window.setTimeout(() => this.runSearch(value), DEBOUNCE_MS);
    }

    async runSearch(value) {
        if (!value || value.trim().length < 2) {
            this.results = [];
            return;
        }
        this.searching = true;
        try {
            const picker =
                this.searchType === 'articles'
                    ? searchArticlesForPicker
                    : this.searchType === 'articleLinks'
                      ? searchArticlesForLink
                      : searchResourcesForPicker;
            const found = await picker({ term: value });
            const attached = new Set(this._items.map((i) => i.value));
            this.results = (found || []).filter((r) => !attached.has(r.value));
        } catch (e) {
            this.results = [];
        } finally {
            this.searching = false;
        }
    }

    handlePick(event) {
        const value = event.currentTarget.dataset.value;
        const picked = this.results.find((r) => r.value === value);
        if (!picked) {
            return;
        }
        this._items = [...this._items, { ...picked }];
        this.term = '';
        this.results = [];
        this.emitChange();
    }

    // ---- List management ----------------------------------------------------------

    handleRemove(event) {
        const index = Number(event.currentTarget.dataset.index);
        this._items = this._items.filter((item, i) => i !== index);
        this.emitChange();
    }

    handleMoveUp(event) {
        this.move(Number(event.currentTarget.dataset.index), -1);
    }

    handleMoveDown(event) {
        this.move(Number(event.currentTarget.dataset.index), 1);
    }

    move(index, delta) {
        const target = index + delta;
        if (target < 0 || target >= this._items.length) {
            return;
        }
        const next = [...this._items];
        const [moved] = next.splice(index, 1);
        next.splice(target, 0, moved);
        this._items = next;
        this.emitChange();
    }

    async handleCopyLink(event) {
        const url = event.currentTarget.dataset.url;
        if (!url) {
            return;
        }
        try {
            await copyText(url);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Link copied',
                    message: 'Paste it anywhere — including a word in the article body via the link tool.',
                    variant: 'success'
                })
            );
        } catch (e) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Could not copy',
                    message: url,
                    variant: 'warning'
                })
            );
        }
    }

    emitChange() {
        this.dispatchEvent(
            new CustomEvent('itemschange', {
                detail: { items: this._items.map((i) => ({ ...i })) }
            })
        );
    }
}