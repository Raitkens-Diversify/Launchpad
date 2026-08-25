import { LightningElement, api } from "lwc";
import NEXS_ICONS from "@salesforce/resourceUrl/arcicon";
import getInbox from "@salesforce/apex/NotificationCenterController.getInbox";
import markAllAsRead from "@salesforce/apex/NotificationCenterController.markAllAsRead";

const TABS = [
  { value: "ALL", label: "All" },
  { value: "UNREAD", label: "Unread" },
  { value: "Case", label: "Cases" },
  { value: "Task", label: "Tasks" }
];

const PAGE_SIZE_OPTIONS = [10, 25, 50];
const DEFAULT_PAGE_SIZE = 10;
const PAGE_WINDOW = 7;
/**
 * getInbox is keyset (lastSeenId) paginated, not offset paginated, so there's
 * no server-side "jump to page 7" or a total-for-this-filter count. This page
 * fetches one large batch per active tab and paginates it client-side (like
 * the Figma "1 2 3 … 9 10" footer), which matches the Items-per-page count
 * exactly as long as a filter stays under this cap.
 */
const FETCH_CAP = 300;

const CARET_LEFT_ICON = "caret-left.svg";
const CARET_RIGHT_ICON = "caret-right.svg";

/**
 * Full Notifications page (Figma 781:25920): page header with unread/total
 * stats and an All/Unread/Cases/Tasks tab strip, a card listing notification
 * rows, and an Items-per-page + numbered pager footer.
 */
export default class ArcNotifications extends LightningElement {
  @api pageTitle = "Notifications";

  activeTab = "ALL";
  items = [];
  isLoading = true;
  errorMessage = "";
  unreadCount = 0;
  totalCount = 0;
  page = 1;
  pageSize = DEFAULT_PAGE_SIZE;

  connectedCallback() {
    this.loadNotifications();
  }

  get tabs() {
    return TABS;
  }

  get caretLeftStyle() {
    return `--icon-url: url('${NEXS_ICONS}/${CARET_LEFT_ICON}');`;
  }

  get caretRightStyle() {
    return `--icon-url: url('${NEXS_ICONS}/${CARET_RIGHT_ICON}');`;
  }

  get statsLabel() {
    return `${this.unreadCount} unread · ${this.totalCount} total`;
  }

  get totalFilteredCount() {
    return this.items.length;
  }

  get hasItems() {
    return this.totalFilteredCount > 0;
  }

  get pageCount() {
    return Math.max(1, Math.ceil(this.totalFilteredCount / this.pageSize));
  }

  get pagedItems() {
    const start = (this.page - 1) * this.pageSize;
    return this.items.slice(start, start + this.pageSize);
  }

  get rangeStart() {
    return this.totalFilteredCount === 0
      ? 0
      : (this.page - 1) * this.pageSize + 1;
  }

  get rangeEnd() {
    return Math.min(this.page * this.pageSize, this.totalFilteredCount);
  }

  get summaryLabel() {
    return `Showing ${this.rangeStart}-${this.rangeEnd} of ${this.totalFilteredCount}`;
  }

  get prevDisabled() {
    return this.page <= 1;
  }

  get nextDisabled() {
    return this.page >= this.pageCount;
  }

  get pageSizeOptions() {
    return PAGE_SIZE_OPTIONS.map((size) => ({
      value: String(size),
      label: String(size),
      isSelected: size === this.pageSize
    }));
  }

  get pageItemsView() {
    const total = this.pageCount;
    const current = this.page;
    const pages = [];

    if (total <= PAGE_WINDOW) {
      for (let index = 1; index <= total; index += 1) {
        pages.push(index);
      }
    } else {
      pages.push(1);
      const start = Math.max(2, current - 1);
      const end = Math.min(total - 1, current + 1);
      if (start > 2) {
        pages.push("gap-lead");
      }
      for (let index = start; index <= end; index += 1) {
        pages.push(index);
      }
      if (end < total - 1) {
        pages.push("gap-trail");
      }
      pages.push(total);
    }

    return pages.map((page) => {
      if (page === "gap-lead" || page === "gap-trail") {
        return { key: page, isGap: true };
      }
      const isActive = page === current;
      return {
        key: `page-${page}`,
        isGap: false,
        page,
        label: String(page),
        cssClass: isActive
          ? "arc-notifications__page-btn arc-notifications__page-btn--active"
          : "arc-notifications__page-btn",
        ariaCurrent: isActive ? "page" : undefined
      };
    });
  }

  async loadNotifications() {
    this.isLoading = true;
    this.errorMessage = "";
    try {
      const result = await getInbox({
        filterName: this.activeTab,
        searchTerm: null,
        pageSize: FETCH_CAP,
        lastSeenId: null,
        sortDirection: "desc"
      });
      this.items = (result && result.items) || [];
      this.unreadCount =
        (result && result.stats && result.stats.unreadCount) || 0;
      this.totalCount =
        (result && result.stats && result.stats.totalCount) || 0;
      this.page = 1;
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("[arcNotifications] Failed to load notifications", error);
      this.errorMessage = "Unable to load notifications.";
      this.items = [];
    } finally {
      this.isLoading = false;
    }
  }

  handleTabChange(event) {
    this.activeTab = event.detail.value;
    this.loadNotifications();
  }

  async handleMarkAllRead() {
    try {
      await markAllAsRead();
      await this.loadNotifications();
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("[arcNotifications] markAllAsRead failed", error);
    }
  }

  handleRowSelect() {
    this.loadNotifications();
  }

  handlePageSizeChange(event) {
    this.pageSize = Number(event.target.value) || DEFAULT_PAGE_SIZE;
    this.page = 1;
  }

  handlePrevious() {
    if (!this.prevDisabled) {
      this.page -= 1;
    }
  }

  handleNext() {
    if (!this.nextDisabled) {
      this.page += 1;
    }
  }

  handlePageClick(event) {
    const page = Number(event.currentTarget.dataset.page);
    if (page) {
      this.page = page;
    }
  }
}