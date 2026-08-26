import { LightningElement, wire } from "lwc";
import NEXS_ICONS from "@salesforce/resourceUrl/arcicon";
import getActiveAnnouncements from "@salesforce/apex/ArcAnnouncementController.getActiveAnnouncements";

const MEGAPHONE_ICON = "megaphone.svg";
const EXTERNAL_LINK_ICON = "arrow-square-out.svg";
const OVERFLOW_ICON = "dots-three-vertical.svg";
const CARET_LEFT_ICON = "caret-left.svg";
const CARET_RIGHT_ICON = "caret-right.svg";

/**
 * Home dashboard announcement banner (Figma node 760:131500): one
 * Announcement__c at a time, with prev/next pagination across every
 * active record. Shows a "No new announcements" empty state when there
 * are none, and greys out the prev/next arrows at either end of the list
 * (both greyed when there's only one announcement).
 */
export default class ArcAnnouncements extends LightningElement {
  announcements = [];
  activeIndex = 0;
  isLoading = true;

  get megaphoneIconStyle() {
    return `--icon-url: url('${NEXS_ICONS}/${MEGAPHONE_ICON}');`;
  }

  get externalLinkIconStyle() {
    return `--icon-url: url('${NEXS_ICONS}/${EXTERNAL_LINK_ICON}');`;
  }

  get overflowIconStyle() {
    return `--icon-url: url('${NEXS_ICONS}/${OVERFLOW_ICON}');`;
  }

  get caretLeftIconStyle() {
    return `--icon-url: url('${NEXS_ICONS}/${CARET_LEFT_ICON}');`;
  }

  get caretRightIconStyle() {
    return `--icon-url: url('${NEXS_ICONS}/${CARET_RIGHT_ICON}');`;
  }

  @wire(getActiveAnnouncements)
  wiredAnnouncements({ data, error }) {
    this.isLoading = false;
    if (data) {
      this.announcements = data;
      this.activeIndex = 0;
      return;
    }
    if (error) {
      this.announcements = [];
      console.error("[arcAnnouncements] Failed to load announcements", error);
    }
  }

  get hasAnnouncements() {
    return this.announcements.length > 0;
  }

  get showEmptyState() {
    return !this.isLoading && !this.hasAnnouncements;
  }

  get showPagination() {
    return this.hasAnnouncements;
  }

  get current() {
    return this.announcements[this.activeIndex];
  }

  get paginationLabel() {
    return `${this.activeIndex + 1}/${this.announcements.length}`;
  }

  get hasLink() {
    return Boolean(this.current?.linkUrl);
  }

  get isPreviousDisabled() {
    return this.activeIndex === 0;
  }

  get isNextDisabled() {
    return this.activeIndex >= this.announcements.length - 1;
  }

  handlePrevious() {
    if (this.isPreviousDisabled) {
      return;
    }
    this.activeIndex -= 1;
  }

  handleNext() {
    if (this.isNextDisabled) {
      return;
    }
    this.activeIndex += 1;
  }

  handleVisitPage() {
    if (!this.hasLink) {
      return;
    }
    window.open(this.current.linkUrl, "_blank", "noopener,noreferrer");
  }
}