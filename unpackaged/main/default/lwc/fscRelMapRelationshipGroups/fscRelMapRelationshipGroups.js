/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-25
 */
import { LightningElement, api } from "lwc";

export default class FscRelMapRelationshipGroups extends LightningElement {
  @api groups = [];
  @api activePreviewSourceId = "";

  get groupViewModels() {
    return (this.groups || []).map((group) => {
      const contactCount = (group.children || []).length;

      return {
        ...group,
        contactCount,
        countLabel: `${contactCount} related contact${contactCount === 1 ? "" : "s"}`
      };
    });
  }

  handleCardAction(event) {
    event.stopPropagation();
    this.dispatchEvent(
      new CustomEvent("cardaction", {
        detail: event.detail,
        bubbles: true,
        composed: true
      })
    );
  }

  @api
  collectAnchorRects() {
    const anchorRects = {};

    this.template.querySelectorAll("[data-anchor-id]").forEach((element) => {
      const nodeId = element.dataset.anchorId;
      if (!nodeId) {
        return;
      }

      anchorRects[nodeId] = element.getBoundingClientRect();
    });

    return anchorRects;
  }
}