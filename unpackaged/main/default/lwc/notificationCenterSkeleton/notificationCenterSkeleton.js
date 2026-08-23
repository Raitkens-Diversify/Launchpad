/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-06
 *
 * Content-area loading skeleton for Notification Center views.
 */
import { LightningElement, api } from "lwc";

const DEFAULT_ROW_COUNT = 6;

const buildPlaceholderItems = (count, prefix) => {
  const size = Number(count) > 0 ? Number(count) : 1;

  return Array.from({ length: size }, (_, index) => ({
    id: `${prefix}-${index}`
  }));
};

export default class NotificationCenterSkeleton extends LightningElement {
  @api rowCount = DEFAULT_ROW_COUNT;
  @api label = "Loading content";

  get contentRows() {
    return buildPlaceholderItems(this.rowCount, "row");
  }

  get toolbarItems() {
    return buildPlaceholderItems(3, "pill");
  }
}