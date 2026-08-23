import { LightningElement, api } from 'lwc';

/**
 * dsPager — "Showing X to Y of Z" plus a Previous / numbered / Next pager.
 * The repo's first pager: state lives in the host (it passes page/pageSize/
 * total and re-slices on `pagechange`); this renders and clamps. The caption
 * always shows; the buttons appear only when there is more than one page.
 * The caption is aria-live so page changes announce to assistive tech.
 *
 * @api page: current 1-based page
 * @api pageSize: rows per page
 * @api total: total row count (after the host's filtering)
 * @api itemLabel: noun for the caption (default 'items')
 * Emits `pagechange` { page }.
 */
export default class DsPager extends LightningElement {
    @api page = 1;
    @api pageSize = 10;
    @api total = 0;
    @api itemLabel = 'items';

    get pageNum() {
        return Math.max(1, Number(this.page) || 1);
    }

    get sizeNum() {
        return Math.max(1, Number(this.pageSize) || 1);
    }

    get totalNum() {
        return Math.max(0, Number(this.total) || 0);
    }

    get pageCount() {
        return Math.max(1, Math.ceil(this.totalNum / this.sizeNum));
    }

    get rangeStart() {
        return this.totalNum === 0 ? 0 : (this.pageNum - 1) * this.sizeNum + 1;
    }

    get rangeEnd() {
        return Math.min(this.pageNum * this.sizeNum, this.totalNum);
    }

    get caption() {
        return `Showing ${this.rangeStart} to ${this.rangeEnd} of ${this.totalNum} ${this.itemLabel}`;
    }

    get showButtons() {
        return this.pageCount > 1;
    }

    get prevDisabled() {
        return this.pageNum <= 1;
    }

    get nextDisabled() {
        return this.pageNum >= this.pageCount;
    }

    /** All pages up to 7; beyond that, first + last + a window around the
     *  current page with ellipsis gaps. */
    get pageItems() {
        const count = this.pageCount;
        const current = this.pageNum;
        let pages;
        if (count <= 7) {
            pages = [];
            for (let i = 1; i <= count; i++) {
                pages.push(i);
            }
        } else {
            let start = Math.max(2, current - 2);
            let end = Math.min(count - 1, current + 2);
            if (current <= 3) {
                start = 2;
                end = 5;
            }
            if (current >= count - 2) {
                start = count - 4;
                end = count - 1;
            }
            pages = [1];
            if (start > 2) {
                pages.push('gap-lead');
            }
            for (let i = start; i <= end; i++) {
                pages.push(i);
            }
            if (end < count - 1) {
                pages.push('gap-trail');
            }
            pages.push(count);
        }
        return pages.map((p) => {
            if (typeof p === 'string') {
                return { key: p, isGap: true };
            }
            const active = p === current;
            return {
                key: `p${p}`,
                isGap: false,
                page: p,
                label: String(p),
                current: active ? 'page' : null,
                cssClass: 'ds-pager__btn ds-pager__btn--page' + (active ? ' ds-pager__btn--current' : '')
            };
        });
    }

    handlePrevious() {
        this.emit(this.pageNum - 1);
    }

    handleNext() {
        this.emit(this.pageNum + 1);
    }

    handlePage(event) {
        this.emit(Number(event.currentTarget.dataset.page));
    }

    emit(target) {
        const page = Math.min(Math.max(1, target), this.pageCount);
        if (page !== this.pageNum) {
            this.dispatchEvent(new CustomEvent('pagechange', { detail: { page } }));
        }
    }
}