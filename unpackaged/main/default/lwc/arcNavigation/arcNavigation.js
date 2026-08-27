import { LightningElement, api, wire } from "lwc";
import { NavigationMixin, CurrentPageReference } from "lightning/navigation";
import NEXS_ICONS from "@salesforce/resourceUrl/arcicon";
import BUILT_BY_DIVERSIFY_LOGO from "@salesforce/resourceUrl/ArcBuiltByDiversify";
import CIRCLE_LOGO from "@salesforce/resourceUrl/ArcCircleLogo";
import { registerTourScope } from "c/tourDom";
import {
  readSidebarCollapsed,
  bootstrapSidebarCollapsedState,
  SIDEBAR_COLLAPSE_CHANGE_EVENT
} from "c/arcNavSidebarState";
import {
  STATIC_NAV_ITEMS,
  NAV_PATH_CHANGE_EVENT,
  UPGRADE_REQUESTED_EVENT,
  patchHistoryForNavigation,
  resolveCurrentPath,
  resolveCurrentQueryParams,
  serializeSearch,
  recordNavSelection,
  findNavTargetById,
  syncNavTrailFromLocation,
  isNavItemActive
} from "c/arcNavTrailState";

/** Hoang Long Vu To — Aug 12, 2026 */
const EXPANDED_GROUPS_STORAGE_KEY = "arc-nav-expanded-groups";

const groupHasBadge = (groupId) => {
  if (!groupId) {
    return false;
  }

  const group = STATIC_NAV_ITEMS.find((item) => item.id === groupId);
  return Boolean(group?.badge);
};

const buildIconUrl = (iconFile) => {
  return iconFile ? `${NEXS_ICONS}/${iconFile}` : null;
};

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

  builtByLogoUrl = BUILT_BY_DIVERSIFY_LOGO;
  circleLogoUrl = CIRCLE_LOGO;

  pathname = "";
  search = "";
  locationSignature = "";
  expandedGroups = {};
  sidebarCollapsed = false;
  currentPageRef;
  _locationPollId;

  connectedCallback() {
    // Lets a guided tour find the nav items by their data-tour-id. The nav
    // reaches the page through the LWR theme layout's sidebar slot, so it sits
    // in a shadow root that tourDom's breadth-first walk cannot reliably cross
    // — registering the template is the sanctioned way in.
    this._unregisterTourScope = registerTourScope(this.template);

    patchHistoryForNavigation();
    this.expandedGroups = readExpandedGroups();
    bootstrapSidebarCollapsedState();
    this.sidebarCollapsed = readSidebarCollapsed();
    this.syncCollapsedHostState();
    this._onSidebarCollapseChange = (event) => {
      const collapsed = Boolean(event.detail?.collapsed);

      if (this.sidebarCollapsed === collapsed) {
        return;
      }

      this.sidebarCollapsed = collapsed;
      this.syncCollapsedHostState();
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
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this._locationPollId = window.setInterval(this._onPathChange, 250);
    this._onDocumentClick = (event) => {
      const tab = event.target?.closest?.('[role="tab"]');

      if (!tab) {
        return;
      }

      [0, 50, 150, 400].forEach((delay) => {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        window.setTimeout(() => {
          this.syncLocation(this.currentPageRef);
        }, delay);
      });
    };
    document.addEventListener("click", this._onDocumentClick, true);
  }

  disconnectedCallback() {
    if (this._unregisterTourScope) {
      this._unregisterTourScope();
      this._unregisterTourScope = null;
    }
    window.removeEventListener("popstate", this._onPathChange);
    window.removeEventListener(NAV_PATH_CHANGE_EVENT, this._onPathChange);
    window.removeEventListener("hashchange", this._onPathChange);
    window.removeEventListener(
      SIDEBAR_COLLAPSE_CHANGE_EVENT,
      this._onSidebarCollapseChange
    );
    window.clearInterval(this._locationPollId);
    document.removeEventListener("click", this._onDocumentClick, true);
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

  get navClass() {
    return this.sidebarCollapsed
      ? "nav-sidebar nav-sidebar--collapsed"
      : "nav-sidebar";
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

  get menuItemsView() {
    const currentPath = this.pathname;
    const currentSearch = this.search;
    const pageRef = this.currentPageRef;
    const sidebarCollapsed = this.sidebarCollapsed;

    const entries = STATIC_NAV_ITEMS.filter((item) => !item.hidden).map(
      (item) => {
        if (item.type === "Divider") {
          return {
            id: item.id,
            isDivider: true
          };
        }

        const mapped = mapItem(item, currentPath, currentSearch, pageRef);
        const collapsedLink = sidebarCollapsed
          ? resolveCollapsedGroupLink(mapped)
          : null;

        if (sidebarCollapsed) {
          return {
            ...mapped,
            showLabel: false,
            showChildren: false,
            // Every collapsed item anchors a hover card now (a single-line
            // label for leaf items, the child list for groups) rather than
            // relying on the native title tooltip, so this is unconditional.
            renderCollapsedLink: true,
            collapsedHref: collapsedLink?.href ?? mapped.href,
            collapsedType: collapsedLink?.type ?? mapped.type,
            collapsedTarget: collapsedLink?.target ?? mapped.target,
            collapsedGroupId: collapsedLink?.groupId ?? null,
            itemTitle: null,
            labelClass: "nav-item__label nav-item__label--hidden",
            linkClass: linkClass(
              mapped.active || Boolean(collapsedLink?.active)
            ),
            ariaCurrent: mapped.active || collapsedLink?.active ? "page" : null
          };
        }

        if (!mapped.hasChildren) {
          return {
            ...mapped,
            showLabel: true,
            showChildren: false,
            itemTitle: null,
            labelClass: "nav-item__label"
          };
        }

        const hasActiveChild = (mapped.subMenu || []).some(
          (child) => child.active
        );
        const isExpanded = mapped.isCollapsible
          ? Boolean(this.expandedGroups[mapped.id]) || hasActiveChild
          : true;

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
          panelId: `arc-nav-panel-${mapped.id}`
        };
      }
    );

    /*
     * Everything from the last divider down hangs at the foot of the rail
     * rather than trailing the list. Nothing sits there at the moment — Apps
     * was the only footer item and has been removed — but the divider is
     * located rather than hard-coded by index, so the mechanism still works
     * if STATIC_NAV_ITEMS grows one again. The stylesheet does the pushing.
     */
    const lastDividerIndex = entries.reduce(
      (found, entry, index) => (entry.isDivider ? index : found),
      -1
    );

    return entries.map((entry, index) => ({
      ...entry,
      entryClass:
        index === lastDividerIndex
          ? "nav-entry nav-entry--starts-footer"
          : "nav-entry"
    }));
  }

  handleGroupToggle(event) {
    const groupId = event.currentTarget.dataset.id;

    if (!groupId) {
      return;
    }

    if (groupHasBadge(groupId)) {
      window.dispatchEvent(new CustomEvent(UPGRADE_REQUESTED_EVENT));
    }

    this.toggleGroupExpansion(groupId);
  }

  handleGroupKeyDown(event) {
    if (event.key !== "Enter" && event.key !== " ") {
      return;
    }

    event.preventDefault();
    this.handleGroupToggle(event);
  }

  handleChevronClick(event) {
    event.stopPropagation();
    const groupId = event.currentTarget.dataset.id;

    if (!groupId) {
      return;
    }

    this.toggleGroupExpansion(groupId);
  }

  toggleGroupExpansion(groupId) {
    const nextExpanded = {
      ...this.expandedGroups,
      [groupId]: !this.expandedGroups[groupId]
    };

    this.expandedGroups = nextExpanded;
    writeExpandedGroups(nextExpanded);
  }

  /**
   * Places the collapsed rail's flyout beside the icon it belongs to.
   *
   * The panel is `position: fixed` because the rail clips horizontally
   * (overflow-x: hidden on .theme-layout__sidebar), which would otherwise cut
   * the menu off at the rail's edge. Fixed escapes that, but it also means the
   * coordinates have to be supplied — hence measuring on the way in rather
   * than leaving it to CSS.
   */
  handleFlyoutOpen(event) {
    const anchor = event.currentTarget;
    const flyout = anchor.querySelector(".nav-flyout");
    if (!flyout) {
      return;
    }

    const rect = anchor.getBoundingClientRect();
    const GAP = 8;
    // Hidden with visibility rather than display, so it can still be measured
    // here and a long menu can be kept clear of the bottom of the window.
    const maxTop = window.innerHeight - flyout.offsetHeight - GAP;
    const top = Math.max(GAP, Math.min(rect.top, maxTop));

    flyout.style.top = `${Math.round(top)}px`;
    flyout.style.left = `${Math.round(rect.right)}px`;
  }

  handleClick(event) {
    const navItemId = event.currentTarget.dataset.id;
    const groupId = event.currentTarget.dataset.groupId;
    const type = event.currentTarget.dataset.type;
    const target = event.currentTarget.dataset.target;
    const navTarget = findNavTargetById(navItemId);

    if (groupHasBadge(groupId)) {
      event.preventDefault();
      event.stopPropagation();
      window.dispatchEvent(new CustomEvent(UPGRADE_REQUESTED_EVENT));
      return;
    }

    if (groupId && !this.expandedGroups[groupId]) {
      const nextExpanded = { ...this.expandedGroups, [groupId]: true };
      this.expandedGroups = nextExpanded;
      writeExpandedGroups(nextExpanded);
    }

    if (type === "ExternalLink") {
      return;
    }

    if (!type || !target) {
      event.preventDefault();
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
        groupLabel: navTarget.groupLabel,
        groupPath: navTarget.groupPath
      });
    }

    if (type === "InternalLink") {
      this[NavigationMixin.Navigate]({
        type: "standard__webPage",
        attributes: { url: target }
      });
      this.scheduleLocationSync();
      return;
    }

    if (type === "SalesforceObject") {
      this[NavigationMixin.Navigate]({
        type: "standard__objectPage",
        attributes: {
          objectApiName: target,
          actionName: "home"
        }
      });
      this.scheduleLocationSync();
    }
  }

  scheduleLocationSync() {
    [0, 100, 300, 600].forEach((delay) => {
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      window.setTimeout(() => {
        this.syncLocation(this.currentPageRef);
      }, delay);
    });
  }
}

function readExpandedGroups() {
  try {
    const storedValue =
      sessionStorage.getItem(EXPANDED_GROUPS_STORAGE_KEY) ??
      localStorage.getItem(EXPANDED_GROUPS_STORAGE_KEY);

    if (!storedValue) {
      return {};
    }

    const parsed = JSON.parse(storedValue);
    return parsed && typeof parsed === "object" ? parsed : {};
  } catch {
    return {};
  }
}

function writeExpandedGroups(expandedGroups) {
  const serializedValue = JSON.stringify(expandedGroups || {});

  try {
    sessionStorage.setItem(EXPANDED_GROUPS_STORAGE_KEY, serializedValue);
  } catch {
    // sessionStorage may be unavailable
  }

  try {
    localStorage.setItem(EXPANDED_GROUPS_STORAGE_KEY, serializedValue);
  } catch {
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
      groupId: mapped.id
    };
  }

  if (firstChild) {
    return {
      ...firstChild,
      groupId: mapped.id
    };
  }

  return null;
}

function mapItem(item, currentPath, currentSearch, pageRef) {
  // Entries flagged hidden in arcNavTrailState are defined but not rendered.
  const children = (item.subMenu || []).filter((child) => !child.hidden);
  const hasChildren = children.length > 0;
  const active =
    !hasChildren && isNavItemActive(item, currentPath, currentSearch, pageRef);
  const mappedChildren = children.map((child) => {
    const childActive = isNavItemActive(
      child,
      currentPath,
      currentSearch,
      pageRef
    );
    return {
      id: child.id,
      label: child.label,
      type: child.type,
      target: child.target,
      href: hrefFor(child),
      active: childActive,
      linkClass: linkClass(childActive),
      /* The collapsed rail's flyout needs its own class: .nav-item is centred
         and stripped of padding while collapsed, which suits a 44px icon
         column and not a labelled menu. */
      flyoutLinkClass: childActive
        ? "nav-flyout__link nav-flyout__link--active"
        : "nav-flyout__link",
      ariaCurrent: childActive ? "page" : null
    };
  });

  return {
    id: item.id,
    label: item.label,
    type: item.type,
    target: item.target,
    href: hrefFor(item),
    iconUrl: buildIconUrl(item.icon),
    iconStyle: buildIconStyle(item.icon),
    hasIcon: Boolean(item.icon),
    badge: item.badge || null,
    hasBadge: Boolean(item.badge),
    hasChildren,
    isCollapsible: Boolean(item.isCollapsible),
    active,
    linkClass: linkClass(active),
    ariaCurrent: active ? "page" : null,
    subMenu: mappedChildren
  };
}

function linkClass(active) {
  return active ? "nav-item nav-item--active" : "nav-item";
}

function hrefFor(item) {
  if (!item?.target) {
    return "#";
  }
  if (item.type === "ExternalLink") {
    return item.target;
  }
  return "#";
}