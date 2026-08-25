import { LightningElement, wire } from "lwc";
import NEXS_ICONS from "@salesforce/resourceUrl/arcicon";
import getActiveAnnouncements from "@salesforce/apex/ArcAnnouncementController.getActiveAnnouncements";

const MEGAPHONE_ICON = "megaphone.svg";
const EXTERNAL_LINK_ICON = "arrow-square-out.svg";
const OVERFLOW_ICON = "dots-three-vertical.svg";
const CARET_LEFT_ICON = "caret-left.svg";
const CARET_RIGHT_ICON = "caret-right.svg";

// Shown until Announcement__c has real active records — keeps the banner
// visible (per Figma) instead of the section silently disappearing.
const PLACEHOLDER_ANNOUNCEMENTS = [
  {
    id: "placeholder",
    title: "Announcement message title goes here",
    body: "Additional information about announcement goes here",
    linkUrl: null
  }
];

/**
 * Home dashboard announcement banner (Figma node 760:131500): one
 * Announcement__c at a time, with prev/next pagination across every
 * active record.
 */
export default class ArcAnnouncements extends LightningElement {
  announcements = [];
  activeIndex = 0;

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
    if (data) {
      this.announcements = data.length > 0 ? data : PLACEHOLDER_ANNOUNCEMENTS;
      this.activeIndex = 0;
      return;
    }
    if (error) {
      this.announcements = PLACEHOLDER_ANNOUNCEMENTS;
      console.error("[arcAnnouncements] Failed to load announcements", error);
    }
  }

  get hasAnnouncements() {
    return this.announcements.length > 0;
  }

  get showPagination() {
    // Always visible per Figma, even with a single (or placeholder)
    // announcement — it reads as "1/1" rather than disappearing.
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

  handlePrevious() {
    if (this.activeIndex === 0) {
      return;
    }
    this.activeIndex -= 1;
  }

  handleNext() {
    if (this.activeIndex >= this.announcements.length - 1) {
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