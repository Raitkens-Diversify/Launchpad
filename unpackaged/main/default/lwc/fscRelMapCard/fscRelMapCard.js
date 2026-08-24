/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-11
 */
import { LightningElement, api } from "lwc";
import { MAP_NODE_TYPE } from "c/fscRelMapUtils";
import {
  buildRecordPageUrl,
  shouldAllowNativeRecordNavigation
} from "c/fscRelUtils";

const MEMBER_RELATION_ACTION_PREFIX = 'manageaar:';
const CLASSIFICATION_ACTION_PREFIX = 'manageclassification:';

const buildRelationshipLinkViewModel = (link, index) => {
  const relatedToInverseRole = String(link.relatedToInverseRole || "").trim();
  const relationshipRole = String(link.relationshipRole || "").trim();
  const relatedToName = String(link.relatedToName || "related person account").trim();
  const relatedToAccountId = String(link.relatedToAccountId || "").trim();
  const rowParts = [];

  if (relatedToInverseRole) {
    rowParts.push(relatedToInverseRole);
  }

  rowParts.push(relatedToName);

  if (relationshipRole) {
    rowParts.push(relationshipRole);
  }

  return {
    ...link,
    key: link.id || `relationship-link-${index}`,
    relatedToAccountId,
    relatedToName,
    relatedToInverseRole,
    relationshipRole,
    showRelatedToInverseRole: Boolean(relatedToInverseRole),
    showRelationshipRole: Boolean(relationshipRole),
    rowAriaLabel: rowParts.join(", "),
    recordUrl: buildRecordPageUrl(link.relatedToAccountId, "Account")
  };
};

const buildRelationshipPartyKey = (link) =>
  String(link.relatedToAccountId || "").trim() ||
  String(link.relatedToName || "").trim().toLowerCase() ||
  link.key;

const groupRelationshipLinks = (links = []) => {
  const partyOrder = [];
  const partiesByKey = new Map();

  links.forEach((link, index) => {
    const normalizedLink = buildRelationshipLinkViewModel(link, index);
    const partyKey = buildRelationshipPartyKey(normalizedLink);

    if (!partiesByKey.has(partyKey)) {
      partiesByKey.set(partyKey, {
        key: `relationship-party-${partyKey}`,
        relatedToAccountId: normalizedLink.relatedToAccountId,
        relatedToName: normalizedLink.relatedToName,
        recordUrl: normalizedLink.recordUrl,
        pairings: []
      });
      partyOrder.push(partyKey);
    }

    const party = partiesByKey.get(partyKey);
    const pairingIndex = party.pairings.length;

    party.pairings.push({
      ...normalizedLink,
      key: `${party.key}-pairing-${pairingIndex}`,
      showPartyName: pairingIndex === 0,
      rowClass: "map-card__relationship-row"
    });
  });

  return partyOrder.map((partyKey) => {
    const party = partiesByKey.get(partyKey);
    const hasMultiplePairings = party.pairings.length > 1;

    if (hasMultiplePairings) {
      party.pairings = party.pairings.map((pairing) => ({
        ...pairing,
        showPartyName: false,
        rowClass:
          "map-card__relationship-row map-card__relationship-row_pairing"
      }));
    }

    return {
      ...party,
      hasMultiplePairings,
      partyClass: hasMultiplePairings
        ? "map-card__relationship-party map-card__relationship-party_multi"
        : "map-card__relationship-party"
    };
  });
};

export default class FscRelMapCard extends LightningElement {
  @api node;
  @api activePreviewSourceId = "";

  isMenuOpen = false;
  areRelationshipDetailsExpanded = true;
  _relationshipDetailsNodeId = "";
  tooltipText = "";
  tooltipTop = 0;
  tooltipLeft = 0;
  tooltipAlignRight = false;

  get showTooltip() {
    return Boolean(this.tooltipText);
  }

  get tooltipStyle() {
    if (!this.showTooltip) {
      return "";
    }

    const transform = this.tooltipAlignRight
      ? "translate(-100%, calc(-100% - 0.25rem))"
      : "translateY(calc(-100% - 0.25rem))";

    return `top:${this.tooltipTop}px;left:${this.tooltipLeft}px;transform:${transform};`;
  }

  get cardClass() {
    const classes = ["map-card", "slds-box", "slds-box_x-small"];

    if (this.node?.hasExpandableContent) {
      classes.push("map-card_expandable");
    }

    if (this.isMenuOpen) {
      classes.push("map-card_menu-open");
    }

    if (this.isGroupCard) {
      classes.push("map-card_group");
    }

    if (this.showFooterBadge) {
      classes.push("map-card_has-badge");
    }

    return classes.join(" ");
  }

  get cardAriaLabel() {
    const label = this.node?.label || "Node";
    const primary = this.showPrimaryPill ? ", Primary" : "";
    const relationshipLinks = this.showRelationshipLinks
      ? this.relationshipLinkGroups
          .flatMap((party) =>
            party.pairings.map((pairing, pairingIndex) => {
              const parts = [];

              if (pairing.relatedToInverseRole) {
                parts.push(pairing.relatedToInverseRole);
              }

              if (
                pairing.showPartyName ||
                (party.hasMultiplePairings && pairingIndex === 0)
              ) {
                parts.push(party.relatedToName);
              }

              if (pairing.relationshipRole) {
                parts.push(pairing.relationshipRole);
              }

              return parts.join(", ");
            })
          )
          .join("; ")
      : "";
    const relatedTo = this.showRelatedToSubline
      ? `, ${this.showRelatedToInverseRole ? `${this.node.relatedToInverseRole}, ` : ""}${this.node.relatedToName}${this.showRelatedToMemberRole ? `, ${this.node.relationshipRole}` : ""}`
      : "";
    const links = relationshipLinks ? `, ${relationshipLinks}` : "";
    const roleFooterLabels = this.roleFooterPills
      .map((pill) => pill.label)
      .join(", ");
    const sub =
      roleFooterLabels && !this.showRelationshipLinks && !this.showRelatedToSubline
        ? `, ${roleFooterLabels}`
        : this.showPlainSub
          ? `, ${this.node.sub}`
          : "";
    return `${label}${primary}${relatedTo}${links}${sub}`;
  }

  get cardAriaExpanded() {
    if (!this.node?.hasExpandableContent) {
      return undefined;
    }

    const isExpanded =
      this.node?.isRequestedOpen === true || this.node?.isOpen === true;

    return isExpanded ? "true" : "false";
  }

  get badgeToggleLabel() {
    const label = this.node?.label || "node";
    const isExpanded =
      this.node?.isRequestedOpen === true || this.node?.isOpen === true;
    const action = isExpanded ? "Collapse" : "Expand";
    return `${action} ${label}`;
  }

  get showRecordLink() {
    if (this.node?.nodeType === MAP_NODE_TYPE.GROUP) {
      return false;
    }

    if (this.node?.nodeType === MAP_NODE_TYPE.RELATED_CONTACT) {
      return Boolean(this.node?.accountId || this.node?.contactId);
    }

    return Boolean(this.node?.accountId);
  }

  get previewRecordId() {
    if (this.node?.nodeType === MAP_NODE_TYPE.RELATED_CONTACT) {
      return this.node?.accountId || this.node?.contactId || "";
    }

    return this.node?.accountId || "";
  }

  get previewObjectApiName() {
    if (this.node?.nodeType === MAP_NODE_TYPE.RELATED_CONTACT) {
      return this.node?.accountId ? "Account" : "Contact";
    }

    return "Account";
  }

  get recordLinkUrl() {
    return buildRecordPageUrl(this.previewRecordId, this.previewObjectApiName);
  }

  get relatedToRecordLinkUrl() {
    return buildRecordPageUrl(this.node?.relatedToAccountId, "Account");
  }

  get previewSourceId() {
    return this.node?.id || "";
  }

  get isPreviewActive() {
    return (
      Boolean(this.previewSourceId) &&
      this.activePreviewSourceId === this.previewSourceId
    );
  }

  get previewButtonVariant() {
    return this.isPreviewActive ? "brand" : "border-filled";
  }

  get previewButtonLabel() {
    return `Preview ${this.node?.label || "record"}`;
  }

  get showBadge() {
    return Boolean(this.node?.showBadge);
  }

  get isGroupCard() {
    return this.node?.nodeType === MAP_NODE_TYPE.GROUP;
  }

  get showFooterBadge() {
    return this.showBadge;
  }

  get showFooterStart() {
    return (
      this.showPrimaryPill ||
      this.showRecordTypeFooterPill ||
      this.showRoleFooterPills
    );
  }

  get footerClass() {
    const classes = ["map-card__footer"];

    if (!this.showFooterStart && this.showFooterBadge) {
      classes.push("map-card__footer_badge-only");
    }

    return classes.join(" ");
  }

  get showPrimaryPill() {
    return (
      this.node?.nodeType === MAP_NODE_TYPE.MEMBER &&
      Boolean(this.node?.isPrimaryMember)
    );
  }

  get showRelatedToSubline() {
    return (
      Boolean(this.node?.showRelatedToSubline) &&
      Boolean(String(this.node?.relatedToName || "").trim()) &&
      Boolean(String(this.node?.relatedToAccountId || "").trim()) &&
      (Boolean(String(this.node?.relatedToInverseRole || "").trim()) ||
        Boolean(String(this.node?.relationshipRole || "").trim()))
    );
  }

  get showRelatedToInverseRole() {
    return Boolean(String(this.node?.relatedToInverseRole || "").trim());
  }

  get showRelatedToMemberRole() {
    return Boolean(String(this.node?.relationshipRole || "").trim());
  }

  get showRelationshipLinks() {
    return this.relationshipLinks.length > 0;
  }

  get hasRelationshipDetails() {
    return this.showRelationshipLinks || this.showRelatedToSubline;
  }

  get relationshipPartyCount() {
    if (this.showRelationshipLinks) {
      return this.relationshipLinkGroups.length;
    }

    if (this.showRelatedToSubline) {
      return 1;
    }

    return 0;
  }

  get relationshipDetailsSummaryLabel() {
    const count = this.relationshipPartyCount;

    if (count === 1) {
      return "1 party";
    }

    return `${count} parties`;
  }

  get relationshipDetailsChevronIcon() {
    return this.areRelationshipDetailsExpanded
      ? "utility:chevrondown"
      : "utility:chevronright";
  }

  get relationshipDetailsToggleLabel() {
    if (this.areRelationshipDetailsExpanded) {
      return `Hide ${this.relationshipDetailsSummaryLabel}`;
    }

    return this.relationshipDetailsSummaryLabel;
  }

  get relationshipDetailsAriaExpanded() {
    return this.areRelationshipDetailsExpanded ? "true" : "false";
  }

  get showRelationshipDetailsContent() {
    return this.hasRelationshipDetails && this.areRelationshipDetailsExpanded;
  }

  get relationshipLinks() {
    return (this.node?.relationshipLinks || []).map((link, index) =>
      buildRelationshipLinkViewModel(link, index)
    );
  }

  get relationshipLinkGroups() {
    return groupRelationshipLinks(this.node?.relationshipLinks || []);
  }

  get showPlainSub() {
    return Boolean(String(this.node?.sub || "").trim());
  }

  get showRecordTypeFooterPill() {
    return (
      this.showPlainSub &&
      (this.node?.nodeType === MAP_NODE_TYPE.ROOT ||
        this.node?.nodeType === MAP_NODE_TYPE.ACCOUNT)
    );
  }

  get showRoleFooterPills() {
    return this.roleFooterPills.length > 0;
  }

  get roleFooterPills() {
    const roleLabels = Array.isArray(this.node?.roleLabels)
      ? this.node.roleLabels
      : [];

    if (roleLabels.length > 0) {
      return roleLabels.map((label, index) => ({
        key: `${label}-${index}`,
        label
      }));
    }

    if (
      this.showPlainSub &&
      this.node?.nodeType === MAP_NODE_TYPE.RELATED_CONTACT
    ) {
      return [
        {
          key: this.node.sub,
          label: this.node.sub
        }
      ];
    }

    return [];
  }

  get showActionsMenu() {
    return (
      Boolean(this.node?.showManageMemberRelationships) ||
      Boolean(this.node?.showManageRelatedContacts) ||
      (this.node?.memberRelationshipActions || []).length > 0 ||
      (Boolean(this.node?.showFamilyGroupContactAction) &&
        (this.node?.familyGroupContactActions || []).length > 0) ||
      (Boolean(this.node?.showNetworkGroupContactAction) &&
        (this.node?.networkGroupContactActions || []).length > 0) ||
      (Boolean(this.node?.showClassificationGroupAction) &&
        (this.node?.classificationGroupContactActions || []).length > 0)
    );
  }

  get showFooter() {
    return (
      this.showFooterBadge ||
      this.showPrimaryPill ||
      this.showRecordTypeFooterPill ||
      this.showRoleFooterPills
    );
  }

  get menuActions() {
    if (
      this.node?.nodeType === MAP_NODE_TYPE.GROUP &&
      this.node?.isLazyFamilyGroup &&
      this.node?.showFamilyGroupContactAction
    ) {
      return (this.node?.familyGroupContactActions || []).map((action) => ({
        name: action.name,
        label: action.label
      }));
    }

    if (
      this.node?.nodeType === MAP_NODE_TYPE.GROUP &&
      this.node?.isLazyNetworkGroup &&
      this.node?.showNetworkGroupContactAction
    ) {
      return (this.node?.networkGroupContactActions || []).map((action) => ({
        name: action.name,
        label: action.label
      }));
    }

    if (this.node?.showClassificationGroupAction) {
      return (this.node?.classificationGroupContactActions || []).map(
        (action) => ({
          name: action.name,
          label: action.label
        })
      );
    }

    if (
      (this.node?.nodeType === MAP_NODE_TYPE.MEMBER ||
        this.node?.nodeType === MAP_NODE_TYPE.ACCOUNT) &&
      (this.node?.showManageMemberRelationships || this.node?.showManageRelatedContacts)
    ) {
      return (this.node?.memberRelationshipActions || []).map((action) => ({
        name: action.name,
        label: action.label
      }));
    }

    return [];
  }

  get actionsMenuLabel() {
    return `Open actions for ${this.node?.label || "node"}`;
  }

  handleMenuOpen(event) {
    event.stopPropagation();
    this.setMenuElevated(true);
  }

  handleMenuClose(event) {
    event.stopPropagation();
    this.setMenuElevated(false);
  }

    @api
  getWireAnchorRect() {
    const card = this.template.querySelector(".map-card");

    if (!card) {
      return this.template.host.getBoundingClientRect();
    }

    return card.getBoundingClientRect();
  }

  setMenuElevated(isElevated) {
    this.isMenuOpen = isElevated;

    const host = this.template.host;
    host.classList.toggle("map-card-host_menu-open", isElevated);

    const cardWrap = host.parentElement;

    if (cardWrap?.classList?.contains("map-node-row__card")) {
      cardWrap.classList.toggle("map-node-row__card_menu-open", isElevated);
    }
  }

  handleMenuSelect(event) {
    event.stopPropagation();
    const value = event.detail?.value;

    if (!value) {
      return;
    }

    this.dispatchCardAction(value);
  }

  handleActionClickStop(event) {
    event.stopPropagation();
  }

  handleTooltipShow(event) {
    event.stopPropagation();

    const target = event.currentTarget;
    const text = (target.dataset?.tooltip || target.textContent || "").trim();

    if (!text) {
      return;
    }

    const rect = target.getBoundingClientRect();
    const alignRight = Boolean(target.closest(".map-card__relationship-end"));

    this.tooltipText = text;
    this.tooltipTop = rect.top;
    this.tooltipLeft = alignRight ? rect.right : rect.left;
    this.tooltipAlignRight = alignRight;
  }

  handleTooltipHide(event) {
    event.stopPropagation();
    this.clearTooltip();
  }

  handleTooltipTargetClick(event) {
    event.stopPropagation();
  }

  handleRelationshipDetailsToggle(event) {
    event.preventDefault();
    event.stopPropagation();
    this.areRelationshipDetailsExpanded = !this.areRelationshipDetailsExpanded;
    this.clearTooltip();
    this.dispatchEvent(
      new CustomEvent("cardaction", {
        detail: {
          action: "layoutchange",
          nodeId: this.node?.id
        },
        bubbles: true,
        composed: true
      })
    );
  }

  clearTooltip() {
    this.tooltipText = "";
    this.tooltipTop = 0;
    this.tooltipLeft = 0;
    this.tooltipAlignRight = false;
  }

  shouldSkipCardToggle(event) {
    return event.composedPath().some((node) => {
      const tag = (node?.localName || "").toLowerCase();
      const className = node?.className || "";

      return (
        tag === "lightning-button-menu" ||
        tag === "lightning-button-icon" ||
        tag === "lightning-menu-item" ||
        tag === "a" ||
        tag === "button" ||
        (typeof className === "string" &&
          (className.includes("map-card__pill") ||
            className.includes("map-card__relationship-toggle")))
      );
    });
  }

  handleToggleClick(event) {
    if (!this.node?.hasExpandableContent) {
      return;
    }

    if (this.shouldSkipCardToggle(event)) {
      return;
    }

    event.preventDefault();
    event.stopPropagation();
    this.dispatchCardAction("toggle");
  }

  handleBadgeToggle(event) {
    if (!this.node?.hasExpandableContent) {
      return;
    }

    event.preventDefault();
    event.stopPropagation();
    this.dispatchCardAction("toggle");
  }

  handleRecordClick(event) {
    if (shouldAllowNativeRecordNavigation(event)) {
      return;
    }

    event.preventDefault();
    event.stopPropagation();
    this.dispatchCardAction("record");
  }

  handleRelatedToRecordClick(event) {
    if (shouldAllowNativeRecordNavigation(event)) {
      return;
    }

    event.preventDefault();
    event.stopPropagation();

    this.dispatchEvent(
      new CustomEvent("cardaction", {
        detail: {
          action: "record",
          nodeId: this.node?.id,
          accountId: this.node?.relatedToAccountId || "",
          contactId: "",
          objectApiName: "Account",
          relationId: this.node?.relationId,
          memberName: this.node?.relatedToName || ""
        },
        bubbles: true,
        composed: true
      })
    );
  }

  handleRelationshipLinkClick(event) {
    if (shouldAllowNativeRecordNavigation(event)) {
      return;
    }

    event.preventDefault();
    event.stopPropagation();

    const target = event.currentTarget;

    this.dispatchEvent(
      new CustomEvent("cardaction", {
        detail: {
          action: "record",
          nodeId: this.node?.id,
          accountId: target.dataset.relatedToAccountId || "",
          contactId: "",
          objectApiName: "Account",
          relationId: target.dataset.relationId || "",
          memberName: target.dataset.relatedToName || ""
        },
        bubbles: true,
        composed: true
      })
    );
  }

  handlePreviewClick(event) {
    event.preventDefault();
    event.stopPropagation();

    const anchorRect = event.currentTarget.getBoundingClientRect();

    this.dispatchEvent(
      new CustomEvent("cardaction", {
        detail: {
          action: "preview",
          nodeId: this.node?.id,
          sourceId: this.previewSourceId,
          accountId:
            this.previewObjectApiName === "Account"
              ? this.previewRecordId
              : "",
          contactId:
            this.previewObjectApiName === "Contact"
              ? this.previewRecordId
              : "",
          objectApiName: this.previewObjectApiName,
          memberName: this.node?.label,
          anchorRect: {
            top: anchorRect.top,
            left: anchorRect.left,
            right: anchorRect.right,
            bottom: anchorRect.bottom
          }
        },
        bubbles: true,
        composed: true
      })
    );
  }

  disconnectedCallback() {
    this.clearTooltip();
    this.setMenuElevated(false);
    this.template.host?.classList.remove("map-card-host_group");
  }

  renderedCallback() {
    this.template.host?.classList.toggle("map-card-host_group", this.isGroupCard);

    const nodeId = this.node?.id || "";

    if (nodeId !== this._relationshipDetailsNodeId) {
      this._relationshipDetailsNodeId = nodeId;
      this.areRelationshipDetailsExpanded = true;
    }
  }

  dispatchCardAction(action) {
    const detail = {
      action,
      nodeId: this.node?.id,
      accountId: this.node?.accountId,
      contactId: this.node?.contactId,
      objectApiName: this.previewObjectApiName,
      relationId: this.node?.relationId,
      memberName: this.node?.label,
      selectMemberFromClients:
        Boolean(this.node?.isLazyFamilyGroup) ||
        Boolean(this.node?.isLazyNetworkGroup)
    };

    if (String(action || '').startsWith(MEMBER_RELATION_ACTION_PREFIX)) {
      const recordTypeDeveloperName = String(action).slice(
        MEMBER_RELATION_ACTION_PREFIX.length
      );
      const matchedAction =
        (this.node?.memberRelationshipActions || []).find(
          (menuAction) => menuAction.recordTypeDeveloperName === recordTypeDeveloperName
        ) ||
        (this.node?.familyGroupContactActions || []).find(
          (menuAction) => menuAction.recordTypeDeveloperName === recordTypeDeveloperName
        ) ||
        (this.node?.networkGroupContactActions || []).find(
          (menuAction) => menuAction.recordTypeDeveloperName === recordTypeDeveloperName
        );

      detail.recordTypeDeveloperName = recordTypeDeveloperName;
      detail.recordTypeLabel = matchedAction?.recordTypeLabel || '';
      detail.reciprocalRoleRecordTypeDeveloperName =
        matchedAction?.reciprocalRoleRecordTypeDeveloperName || recordTypeDeveloperName;
    }

    if (String(action || '').startsWith(CLASSIFICATION_ACTION_PREFIX)) {
      detail.classificationValue = String(action).slice(
        CLASSIFICATION_ACTION_PREFIX.length
      );
      const matchedAction = (this.node?.classificationGroupContactActions || []).find(
        (menuAction) => menuAction.classificationValue === detail.classificationValue
      );
      detail.classificationLabel =
        matchedAction?.classificationValue || detail.classificationValue;
    }

    this.dispatchEvent(
      new CustomEvent("cardaction", {
        detail,
        bubbles: true,
        composed: true
      })
    );
  }
}