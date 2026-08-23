import { LightningElement, api, wire } from "lwc";
import { loadStyle } from "lightning/platformResourceLoader";
import { NavigationMixin, CurrentPageReference } from "lightning/navigation";
import NEXS_ICONS from "@salesforce/resourceUrl/arcicon";
import diversifyStyles from "@salesforce/resourceUrl/diversifyStyles";
import getHelpCenterLinkBase from "@salesforce/apex/ResourceCenterService.getHelpCenterLinkBase";
import { buildPublishedExperienceSiteUrl } from "c/recordNavigationCommunityUtils";
import {
  readSidebarCollapsed,
  bootstrapSidebarCollapsedState,
  SIDEBAR_COLLAPSE_CHANGE_EVENT,
  SIDEBAR_NAV_PHASE_MS,
} from "c/arcNavSidebarState";
import {
  STATIC_NAV_ITEMS,
  MANUAL_CONTACTS_GROUP_ID,
  MANUAL_WORK_GROUP_ID,
  MANUAL_ISA_GROUP_ID,
  HELP_SITE_PATH,
  NAV_PATH_CHANGE_EVENT,
  resolveCurrentPath,
  resolveCurrentQueryParams,
  serializeSearch,
  recordNavSelection,
  findNavTargetById,
  syncNavTrailFromLocation,
  isNavItemActive,
  syncNavParamsOnTabClick,
  resolveTabLabelFromElement,
  resolveSelectedTabLabelFromDom,
} from "c/arcNavTrailState";

/** Hoang Long Vu To — Aug 12, 2026 */
const CONTACTS_EXPANDED_STORAGE_KEY = "arc-nav-contacts-expanded";
const WORK_EXPANDED_STORAGE_KEY = "arc-nav-work-expanded";
const ISA_EXPANDED_STORAGE_KEY = "arc-nav-isas-expanded";

const COLLAPSIBLE_GROUP_STORAGE_KEYS = Object.freeze({
  [MANUAL_CONTACTS_GROUP_ID]: CONTACTS_EXPANDED_STORAGE_KEY,
  [MANUAL_WORK_GROUP_ID]: WORK_EXPANDED_STORAGE_KEY,
  [MANUAL_ISA_GROUP_ID]: ISA_EXPANDED_STORAGE_KEY,
});

const buildIconUrl = (iconFile) =>
  iconFile ? `${NEXS_ICONS}/${iconFile}` : null;

const buildIconStyle = (iconFile) => {
  const iconUrl = buildIconUrl(iconFile);

  if (!iconUrl) {
    return null;
  }

  return `--icon-url: url('${iconUrl}');`;
};

/**
 * Vertical Arc sidebar navigation for LWR Experience sites.
 * Static menu with arcicon assets; Contacts submenu uses tab deep-links.
 */
export default class ArcNavigation extends NavigationMixin(LightningElement) {
  /** Reserved for future dynamic menu support. */
  @api menuName = "Arc";

  pathname = "";
  search = "";
  locationSignature = "";
  contactsExpanded = true;
  workExpanded = true;
  isaExpanded = true;
  sidebarCollapsed = false;
  motionPhase = "idle";
  isAnimating = false;
  currentPageRef;
  helpSiteUrl = "";
  _locationPollId;
  _animationTimerId;

  @wire(getHelpCenterLinkBase)
  wiredHelpSiteUrl({ data }) {
    this.helpSiteUrl = data ? String(data).replace(/\/$/, "") : "";
  }

  connectedCallback() {
    loadStyle(this, diversifyStyles).catch((error) => {
      console.error("[arcNavigation] Failed to load diversifyStyles", error);
    });
    this.contactsExpanded = readGroupExpanded(MANUAL_CONTACTS_GROUP_ID, true);
    this.workExpanded = readGroupExpanded(MANUAL_WORK_GROUP_ID, true);
    this.isaExpanded = readGroupExpanded(MANUAL_ISA_GROUP_ID, true);
    bootstrapSidebarCollapsedState();
    this.sidebarCollapsed = readSidebarCollapsed();
    this.syncCollapsedHostState();
    this._onSidebarCollapseChange = (event) => {
      const collapsed = Boolean(event.detail?.collapsed);
      this.applySidebarCollapsedState(collapsed);
    };
    window.addEventListener(
      SIDEBAR_COLLAPSE_CHANGE_EVENT,
      this._onSidebarCollapseChange
    );
    this.syncLocation();
    this._onPathChange = () => {
      this.syncLocation(this.currentPageRef);
    };
    window.addEventListener("popstate", this._onPathChange);
    window.addEventListener(NAV_PATH_CHANGE_EVENT, this._onPathChange);
    window.addEventListener("hashchange", this._onPathChange);
    this._locationPollId = window.setInterval(this._onPathChange, 250);
    this._onDocumentClick = (event) => {
      const tab = event.target?.closest?.('[role="tab"]');

      if (!tab) {
        return;
      }

      const tabLabel = resolveTabLabelFromElement(tab);

      [0, 50, 150, 400].forEach((delay) => {
        window.setTimeout(() => {
          syncNavParamsOnTabClick(
            tabLabel || resolveSelectedTabLabelFromDom()
          );
          this.syncLocation(this.currentPageRef);
        }, delay);
      });
    };
    document.addEventListener("click", this._onDocumentClick, true);
  }

  disconnectedCallback() {
    window.removeEventListener("popstate", this._onPathChange);
    window.removeEventListener(NAV_PATH_CHANGE_EVENT, this._onPathChange);
    window.removeEventListener("hashchange", this._onPathChange);
    window.removeEventListener(
      SIDEBAR_COLLAPSE_CHANGE_EVENT,
      this._onSidebarCollapseChange
    );
    window.clearInterval(this._locationPollId);
    this.clearAnimationTimers();
    document.removeEventListener("click", this._onDocumentClick, true);
  }

  applySidebarCollapsedState(collapsed) {
    this.clearAnimationTimers();

    if (this.prefersReducedMotion()) {
      this.motionPhase = "idle";
      this.isAnimating = false;
      this.sidebarCollapsed = collapsed;
      this.syncCollapsedHostState();
      return;
    }

    if (collapsed) {
      if (this.sidebarCollapsed || this.isAnimating) {
        return;
      }

      this.isAnimating = true;
      this.motionPhase = "collapse-exit";
      this._animationTimerId = window.setTimeout(() => {
        this.motionPhase = "collapse-enter";
        this.sidebarCollapsed = true;
        this.syncCollapsedHostState();
        this._animationTimerId = window.setTimeout(() => {
          this.motionPhase = "idle";
          this.isAnimating = false;
          this._animationTimerId = null;
        }, SIDEBAR_NAV_PHASE_MS);
      }, SIDEBAR_NAV_PHASE_MS);
      return;
    }

    if (!this.sidebarCollapsed && !this.isAnimating) {
      return;
    }

    this.isAnimating = true;
    this.motionPhase = "expand-exit";
    this._animationTimerId = window.setTimeout(() => {
      this.motionPhase = "expand-enter";
      this.sidebarCollapsed = false;
      this.syncCollapsedHostState();
      this._animationTimerId = window.setTimeout(() => {
        this.motionPhase = "idle";
        this.isAnimating = false;
        this._animationTimerId = null;
      }, SIDEBAR_NAV_PHASE_MS);
    }, SIDEBAR_NAV_PHASE_MS);
  }

  clearAnimationTimers() {
    if (!this._animationTimerId) {
      return;
    }

    window.clearTimeout(this._animationTimerId);
    this._animationTimerId = null;
  }

  prefersReducedMotion() {
    if (typeof window === "undefined" || !window.matchMedia) {
      return false;
    }

    return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  }

  syncCollapsedHostState() {
    const shouldCollapse = this.sidebarCollapsed;
    const hasAttribute = this.hasAttribute("data-collapsed");

    if (shouldCollapse === hasAttribute) {
      return;
    }

    if (shouldCollapse) {
      this.setAttribute("data-collapsed", "true");
      return;
    }

    this.removeAttribute("data-collapsed");
  }

  get viewportClass() {
    const classes = ["nav-viewport"];

    if (this.motionPhase !== "idle") {
      classes.push(`nav-viewport--${this.motionPhase}`);
      return classes.join(" ");
    }

    classes.push(
      this.sidebarCollapsed ? "nav-viewport--collapsed" : "nav-viewport--expanded"
    );
    return classes.join(" ");
  }

  get navPanels() {
    return [
      {
        key: "expanded",
        className: "nav-panel nav-panel--expanded nav-sidebar",
        items: this.buildMenuItemsView(false, "expanded"),
        isHidden: this.isExpandedPanelHidden,
      },
      {
        key: "collapsed",
        className:
          "nav-panel nav-panel--collapsed nav-sidebar nav-sidebar--collapsed",
        items: this.buildMenuItemsView(true, "collapsed"),
        isHidden: this.isCollapsedPanelHidden,
      },
    ];
  }

  get isExpandedPanelHidden() {
    if (this.motionPhase === "collapse-enter" || this.motionPhase === "expand-exit") {
      return true;
    }

    return this.motionPhase === "idle" && this.sidebarCollapsed;
  }

  get isCollapsedPanelHidden() {
    if (
      this.motionPhase === "collapse-exit" ||
      this.motionPhase === "expand-enter"
    ) {
      return true;
    }

    return this.motionPhase === "idle" && !this.sidebarCollapsed;
  }

  syncLocation(pageRef = this.currentPageRef) {
    const pathname = resolveCurrentPath(pageRef);
    const search = serializeSearch(resolveCurrentQueryParams(pageRef));
    const signature = `${pathname}${search}`;

    if (signature === this.locationSignature) {
      return;
    }

    this.locationSignature = signature;
    this.pathname = pathname;
    this.search = search;
    syncNavTrailFromLocation(pathname, search, pageRef);
  }

  @wire(CurrentPageReference)
  wiredPageRef(pageRef) {
    this.currentPageRef = pageRef;
    this.syncLocation(pageRef);
  }

  buildMenuItemsView(sidebarCollapsed, panelKey = "expanded") {
    const currentPath = this.pathname;
    const currentSearch = this.search;
    const pageRef = this.currentPageRef;

    return STATIC_NAV_ITEMS.map((item) => {
      if (item.type === "Divider") {
        return {
          id: item.id,
          isDivider: true,
        };
      }

      const mapped = mapItem(
        item,
        currentPath,
        currentSearch,
        pageRef,
        this.helpSiteUrl
      );
      const collapsedLink = sidebarCollapsed
        ? resolveCollapsedGroupLink(mapped)
        : null;

      if (sidebarCollapsed) {
        return {
          ...mapped,
          showLabel: false,
          showChildren: false,
          renderCollapsedLink: Boolean(collapsedLink),
          collapsedHref: collapsedLink?.href ?? mapped.href,
          collapsedType: collapsedLink?.type ?? mapped.type,
          collapsedTarget: collapsedLink?.target ?? mapped.target,
          collapsedGroupId: collapsedLink?.groupId ?? null,
          linkTarget: collapsedLink?.linkTarget ?? mapped.linkTarget,
          linkRel: collapsedLink?.linkRel ?? mapped.linkRel,
          itemTitle: mapped.isComingSoon ? mapped.ariaLabel : mapped.label,
          labelClass: "nav-item__label nav-item__label--hidden",
          linkClass: mapped.isComingSoon
            ? linkClass(false, true)
            : linkClass(mapped.active || Boolean(collapsedLink?.active)),
          ariaCurrent:
            mapped.active || collapsedLink?.active ? "page" : null,
        };
      }

      if (!mapped.hasChildren) {
        return {
          ...mapped,
          showLabel: true,
          showChildren: false,
          itemTitle: null,
          labelClass: "nav-item__label",
        };
      }

      const isExpanded = mapped.isCollapsible
        ? this.isGroupExpanded(mapped.id)
        : true;
      const headerLink = mapped.isCollapsible
        ? resolveCollapsedGroupLink(mapped)
        : null;

      return {
        ...mapped,
        showLabel: true,
        showChildren: true,
        itemTitle: null,
        labelClass: "nav-item__label",
        isExpanded,
        isCollapsed: !isExpanded,
        childrenClass: isExpanded
          ? "nav-group__children"
          : "nav-group__children nav-group__children--collapsed",
        chevronIcon: isExpanded
          ? "utility:chevrondown"
          : "utility:chevronright",
        chevronLabel: isExpanded ? "Collapse section" : "Expand section",
        panelId: `arc-nav-panel-${panelKey}-${mapped.id}`,
        headerHref: headerLink?.href ?? null,
        headerNavId: headerLink?.id ?? null,
        headerType: headerLink?.type ?? null,
        headerTarget: headerLink?.target ?? null,
        headerLinkTarget: headerLink?.linkTarget ?? null,
        headerLinkRel: headerLink?.linkRel ?? null,
        headerLinkClass: linkClass(Boolean(headerLink?.active)),
        headerAriaCurrent: headerLink?.active ? "page" : null,
      };
    });
  }

  isGroupExpanded(groupId) {
    if (groupId === MANUAL_CONTACTS_GROUP_ID) {
      return this.contactsExpanded;
    }

    if (groupId === MANUAL_WORK_GROUP_ID) {
      return this.workExpanded;
    }

    if (groupId === MANUAL_ISA_GROUP_ID) {
      return this.isaExpanded;
    }

    return true;
  }

  setGroupExpanded(groupId, isExpanded) {
    if (groupId === MANUAL_CONTACTS_GROUP_ID) {
      this.contactsExpanded = isExpanded;
    } else if (groupId === MANUAL_WORK_GROUP_ID) {
      this.workExpanded = isExpanded;
    } else if (groupId === MANUAL_ISA_GROUP_ID) {
      this.isaExpanded = isExpanded;
    } else {
      return;
    }

    writeGroupExpanded(groupId, isExpanded);
  }

  handleGroupToggle(event) {
    event.stopPropagation();
    const groupId = event.currentTarget.dataset.id;

    if (!COLLAPSIBLE_GROUP_STORAGE_KEYS[groupId]) {
      return;
    }

    this.setGroupExpanded(groupId, !this.isGroupExpanded(groupId));
  }

  handleGroupKeyDown(event) {
    if (event.key !== "Enter" && event.key !== " ") {
      return;
    }

    event.preventDefault();
    this.handleGroupToggle(event);
  }

  handleClick(event) {
    if (event.currentTarget.dataset.comingSoon === "true") {
      event.preventDefault();
      event.stopPropagation();
      return;
    }

    const navItemId = event.currentTarget.dataset.id;
    const groupId = event.currentTarget.dataset.groupId;
    const type = event.currentTarget.dataset.type;
    const target = event.currentTarget.dataset.target;
    const navTarget = findNavTargetById(navItemId);

    if (COLLAPSIBLE_GROUP_STORAGE_KEYS[groupId]) {
      this.setGroupExpanded(groupId, true);
    }

    if (!type || !target || type === "ExternalLink") {
      return;
    }

    event.preventDefault();
    event.stopPropagation();

    if (navTarget) {
      recordNavSelection({
        id: navTarget.id,
        label: navTarget.label,
        path: navTarget.target,
        objectApiName: navTarget.objectApiName,
      });
    }

    if (type === "InternalLink") {
      this[NavigationMixin.Navigate]({
        type: "standard__webPage",
        attributes: { url: target },
      });
      this.locationSignature = "";
      this.scheduleLocationSync();
      return;
    }

    if (type === "SalesforceObject") {
      this[NavigationMixin.Navigate]({
        type: "standard__objectPage",
        attributes: {
          objectApiName: target,
          actionName: "home",
        },
      });
      this.scheduleLocationSync();
    }
  }

  scheduleLocationSync() {
    [0, 100, 300, 600].forEach((delay) => {
      window.setTimeout(() => {
        this.syncLocation(this.currentPageRef);
      }, delay);
    });
  }
}

function readGroupExpanded(groupId, defaultValue = true) {
  const storageKey = COLLAPSIBLE_GROUP_STORAGE_KEYS[groupId];

  if (!storageKey) {
    return defaultValue;
  }

  try {
    const storedValue =
      sessionStorage.getItem(storageKey) ?? localStorage.getItem(storageKey);

    if (storedValue === null) {
      return defaultValue;
    }

    return storedValue === "true";
  } catch (error) {
    return defaultValue;
  }
}

function writeGroupExpanded(groupId, isExpanded) {
  const storageKey = COLLAPSIBLE_GROUP_STORAGE_KEYS[groupId];

  if (!storageKey) {
    return;
  }

  const serializedValue = isExpanded ? "true" : "false";

  try {
    sessionStorage.setItem(storageKey, serializedValue);
  } catch (error) {
    // sessionStorage may be unavailable
  }

  try {
    localStorage.setItem(storageKey, serializedValue);
  } catch (error) {
    // localStorage may be unavailable
  }
}

function resolveCollapsedGroupLink(mapped) {
  if (!mapped.hasChildren) {
    return null;
  }

  const activeChild = (mapped.subMenu || []).find((child) => child.active);
  const firstChild = mapped.subMenu?.[0];

  if (activeChild) {
    return {
      ...activeChild,
      groupId: mapped.id,
    };
  }

  if (firstChild) {
    return {
      ...firstChild,
      groupId: mapped.id,
    };
  }

  return null;
}

function mapItem(item, currentPath, currentSearch, pageRef, helpSiteUrl = "") {
  const children = item.subMenu || [];
  const hasChildren = children.length > 0;
  const isComingSoon = Boolean(item.comingSoon);
  const active =
    !hasChildren &&
    !isComingSoon &&
    isNavItemActive(item, currentPath, currentSearch, pageRef);
  const mappedChildren = children.map((child) => {
    const childActive = isNavItemActive(child, currentPath, currentSearch, pageRef);
    return {
      id: child.id,
      label: child.label,
      type: child.type,
      target: child.target,
      href: hrefFor(child, helpSiteUrl),
      active: childActive,
      linkClass: linkClass(childActive),
      ariaCurrent: childActive ? "page" : null,
      ...externalLinkAttributes(child),
    };
  });

  return {
    id: item.id,
    label: item.label,
    type: item.type,
    target: item.target,
    href: hrefFor(item, helpSiteUrl),
    iconUrl: buildIconUrl(item.icon),
    iconStyle: buildIconStyle(item.icon),
    hasIcon: Boolean(item.icon),
    hasChildren,
    isCollapsible: Boolean(item.isCollapsible),
    isComingSoon,
    active,
    linkClass: linkClass(active, isComingSoon),
    ariaCurrent: active ? "page" : null,
    ariaLabel: isComingSoon ? `${item.label} (Coming Soon)` : null,
    subMenu: mappedChildren,
    ...externalLinkAttributes(item),
  };
}

function linkClass(active, isComingSoon = false) {
  if (isComingSoon) {
    return "nav-item nav-item--coming-soon";
  }

  return active ? "nav-item nav-item--active" : "nav-item";
}

function hrefFor(item, helpSiteUrl = "") {
  if (!item?.target) {
    return "#";
  }
  if (item.type === "ExternalLink") {
    if (/^https?:\/\//i.test(item.target)) {
      return item.target;
    }

    const path = item.target.startsWith("/") ? item.target : `/${item.target}`;

    if (helpSiteUrl && path === HELP_SITE_PATH) {
      return `${helpSiteUrl}/`;
    }

    return buildPublishedExperienceSiteUrl(path);
  }
  return "#";
}

function externalLinkAttributes(item) {
  if (item?.type !== "ExternalLink" || item.opensInNewTab === false) {
    return {};
  }

  return {
    opensInNewTab: true,
    linkTarget: "_blank",
    linkRel: "noopener noreferrer",
  };
}