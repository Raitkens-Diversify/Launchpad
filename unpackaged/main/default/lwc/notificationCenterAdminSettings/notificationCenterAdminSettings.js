/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-08
 *
 * Admin-only settings hub with one section per org-wide configuration area.
 */
import { LightningElement } from "lwc";
import { ICON } from "c/notificationCenterUtils";

const ADMIN_SECTIONS = Object.freeze([
  {
    id: "system-default-rules",
    type: "system-default-rules",
    title: "System Default Rules",
    description:
      "Org-wide default notification rules applied to all users when they have no active custom rule for the same object type.",
    newRuleLabel: "New Rule"
  }
]);

export default class NotificationCenterAdminSettings extends LightningElement {
  icons = ICON;
  isEmbeddedRulesReady = false;

  sections = ADMIN_SECTIONS.map((section) => ({
    ...section,
    isSystemDefaultRules: section.type === "system-default-rules"
  }));

  get showSectionChrome() {
    return this.isEmbeddedRulesReady;
  }

  handleEmbeddedRulesReady = () => {
    this.isEmbeddedRulesReady = true;
  };

  handleNewSystemDefault = () => {
    this.template
      .querySelector("c-notification-center-rules")
      ?.openCreateModal();
  };
}