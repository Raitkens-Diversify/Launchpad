import { LightningElement, wire } from "lwc";
import { CurrentPageReference } from "lightning/navigation";
import { loadStyle } from "lightning/platformResourceLoader";
import diversifyStyles from "@salesforce/resourceUrl/diversifyStyles";
import {
  readSidebarCollapsed,
  bootstrapSidebarCollapsedState,
  SIDEBAR_COLLAPSE_CHANGE_EVENT,
  SIDEBAR_COLLAPSED_WIDTH,
  SIDEBAR_LWR_EXPANDED_WIDTH
} from "c/arcNavSidebarState";
import { NAV_PATH_CHANGE_EVENT } from "c/arcNavTrailState";

/*
 * The gap between clicking a nav link and the routed-in page actually
 * rendering anything is a real blank .theme-layout__main — there's no
 * default/placeholder content in that slot, so whatever the router hasn't
 * mounted yet is a bare white rect. patchHistoryForNavigation (installed by
 * arcNavigation) dispatches NAV_PATH_CHANGE_EVENT right after every
 * pushState/replaceState, which covers NavigationMixin.Navigate too since it
 * ultimately calls the same (patched) history API — so this is the one place
 * that can react to "a route is in flight" for every navigation site-wide.
 */
const ROUTE_TRANSITION_SAFETY_MS = 4000;

/*
 * Routes that are shown to someone who is not (yet) signed in, or who has hit
 * a system page. None of them should carry the app's chrome: a nav menu whose
 * every destination needs a session, a breadcrumb describing where the user
 * last was, or an empty sidebar rail.
 *
 * Matched on the route's last path segment, lower-cased, against the
 * urlPrefix values in digitalExperiences/site/ARC1/sfdc_cms__route/*. Path
 * rather than CurrentPageReference because the pageRef for these routes does
 * not carry the routeType, and path works identically on the published host,
 * the live-preview host and the Builder canvas.
 */
const CHROMELESS_ROUTE_SEGMENTS = new Set([
  "login",
  "forgotpassword",
  "checkpasswordresetemail",
  "selfregister",
  "register",
  "error",
  "service-not-available",
  "too-many-requests"
]);

/** True when the current path is one of the routes above. */
const isChromelessRoute = () => {
  try {
    const segments = window.location.pathname.split("/").filter(Boolean);
    const last = segments[segments.length - 1];
    return Boolean(last) && CHROMELESS_ROUTE_SEGMENTS.has(last.toLowerCase());
  } catch {
    /* Never let a location quirk cost the app its whole chrome. */
    return false;
  }
};

/** Hoang Long Vu To — Aug 12, 2026 */

const isPreviewContext = (pageRef) => {
  if (pageRef?.state?.view === "preview") {
    return true;
  }

  try {
    const { hostname, search } = window.location;
    if (hostname.includes(".preview.")) {
      return true;
    }

    /*
     * Experience Builder renders the site in an iframe on the live-preview
     * origin, whose hostname reads "live-preview." and so never matched the
     * ".preview." test above. Without this the frame-context fallback in
     * isExperienceBuilderDesignMode read "I am iframed" as "I am the edit
     * canvas", dropped the runtime shell for good, and let the header and
     * sidebar scroll away with the page.
     *
     * This deliberately does NOT exempt the edit canvas. Toggling Live Preview
     * does not reload the frame — the builder keeps the very same document and
     * only swaps the chrome around it, so BOTH modes report
     * app=commeditor&view=editor and nothing in the URL or page state can tell
     * them apart. Given the choice, the canvas gets the runtime shell too: a
     * preview that does not behave like the site is the more expensive of the
     * two wrong answers, and the canvas stays editable because the main region
     * keeps its own scrollbar.
     */
    if (hostname.includes("live-preview.")) {
      return true;
    }

    const params = new URLSearchParams(search);
    if (params.has("live-preview") || params.get("preview") === "true") {
      return true;
    }
  } catch {
    // ignore
  }

  try {
    if (pageRef?.state?.app === "commeditor" && window.self === window.top) {
      return true;
    }
  } catch {
    // ignore
  }

  return false;
};

const isExperienceBuilderDesignMode = (pageRef) => {
  if (isPreviewContext(pageRef)) {
    return false;
  }

  if (pageRef?.state?.app === "commeditor") {
    try {
      // Edit canvas is embedded in the builder iframe; preview opens top-level.
      return window.self !== window.top;
    } catch {
      return true;
    }
  }

  if (pageRef?.state?.app) {
    return false;
  }

  // pageRef not wired yet — infer from frame context until navigation resolves.
  try {
    return window.self !== window.top;
  } catch {
    return false;
  }
};

/**
 * Custom LWR theme layout with a persistent sidebar region alongside the
 * standard header/footer regions and the default main-content slot.
 *
 * @slot header
 * @slot sidebar
 * @slot footer
 */
export default class ThemeLayoutSidebar extends LightningElement {
  _collapsed = null;
  _pageRef;
  isRouteTransitioning = false;
  /*
   * Tracked rather than a getter: a getter over window.location would not
   * re-evaluate when the router changes the path without remounting this
   * component, so the chrome would stay hidden (or shown) across a
   * login -> home navigation. Recomputed wherever the path can change.
   */
  showChrome = !isChromelessRoute();
  _mainObserver;
  _routeTransitionSafetyTimer;

  connectedCallback() {
    loadStyle(this, diversifyStyles).catch((error) => {
      // eslint-disable-next-line no-console
      console.error(
        "[themeLayoutSidebar] Failed to load diversifyStyles",
        error
      );
    });
    this.syncRuntimeShellClass();
    this.syncChromeVisibility();
    bootstrapSidebarCollapsedState();
    this.syncSidebarWidth(readSidebarCollapsed(), { force: true });
    this._onSidebarCollapseChange = (event) => {
      this.syncSidebarWidth(Boolean(event.detail?.collapsed));
    };
    window.addEventListener(
      SIDEBAR_COLLAPSE_CHANGE_EVENT,
      this._onSidebarCollapseChange
    );

    this._onNavPathChange = () => {
      this.syncChromeVisibility();
      this.beginRouteTransition();
    };
    window.addEventListener("popstate", this._onNavPathChange);
    window.addEventListener(NAV_PATH_CHANGE_EVENT, this._onNavPathChange);
  }

  renderedCallback() {
    this.observeRailHeight();
    this.syncHeaderSlotLayout();
  }

  disconnectedCallback() {
    window.removeEventListener(
      SIDEBAR_COLLAPSE_CHANGE_EVENT,
      this._onSidebarCollapseChange
    );
    window.removeEventListener("popstate", this._onNavPathChange);
    window.removeEventListener(NAV_PATH_CHANGE_EVENT, this._onNavPathChange);
    this._railObserver?.disconnect();
    this._railObserver = null;
    this._mainObserver?.disconnect();
    this._mainObserver = null;
    window.clearTimeout(this._routeTransitionSafetyTimer);
  }

  /**
   * Shows the branded spinner over .theme-layout__main the instant a
   * navigation starts, and clears it as soon as the routed-in page's first
   * DOM mutation lands (a MutationObserver on that same region) — with a
   * fixed timeout as a backstop so the overlay can never get stuck up if a
   * page happens to render without ever mutating that subtree.
   */
  beginRouteTransition() {
    this.isRouteTransitioning = true;

    window.clearTimeout(this._routeTransitionSafetyTimer);
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this._routeTransitionSafetyTimer = window.setTimeout(() => {
      this.endRouteTransition();
    }, ROUTE_TRANSITION_SAFETY_MS);

    const main = this.template.querySelector(".theme-layout__main");
    if (!main || typeof MutationObserver === "undefined") {
      return;
    }

    this._mainObserver?.disconnect();
    this._mainObserver = new MutationObserver(() => {
      this.endRouteTransition();
    });
    this._mainObserver.observe(main, { childList: true, subtree: true });
  }

  endRouteTransition() {
    if (!this.isRouteTransitioning) {
      return;
    }

    this.isRouteTransitioning = false;
    window.clearTimeout(this._routeTransitionSafetyTimer);
    this._mainObserver?.disconnect();
    this._mainObserver = null;
  }

  /**
   * Publishes the rail's measured height as --arc-rail-height so slotted nav
   * content can fill it.
   *
   * The nav cannot work this out for itself. The platform's region and
   * component wrappers between the slot and the nav are plain blocks, so a
   * percentage height cannot be threaded down to it, and deriving the height
   * in CSS undershoots or overshoots as soon as the header or footer changes —
   * calc(100vh - header) was 30px out because of the footer. Measuring the one
   * element that actually is the rail keeps the two in step.
   */
  observeRailHeight() {
    const rail = this.template.querySelector(".theme-layout__sidebar");
    if (!rail) {
      return;
    }

    /*
     * Written to the rail itself rather than to the host. `this.style` is
     * unsupported below API version 62 — this bundle is on 60, and the runtime
     * warns about it — and the guard around it would have swallowed this
     * silently. The rail is the slot's parent in the flattened tree, so the
     * value inherits into the slotted nav from here just the same.
     */
    const publish = (height) => {
      if (height > 0) {
        rail.style.setProperty("--arc-rail-height", `${Math.round(height)}px`);
      }
    };

    // Cover the first paint; the observer alone would miss it if the rail is
    // already at its final size by the time it is attached.
    publish(rail.getBoundingClientRect().height);

    if (this._railObserver || typeof ResizeObserver === "undefined") {
      return;
    }

    /*
     * Publishing back onto the observed element inside the notification
     * itself is exactly the pattern that trips "ResizeObserver loop
     * completed with undelivered notifications" — if the mutation feeds
     * back into the rail's own content rect (e.g. via a slotted child sized
     * off --arc-rail-height), the browser wants to re-notify within the same
     * frame and gives up with that warning instead. Deferring the publish to
     * the next frame lets this cycle's notifications finish delivering
     * first, so there's nothing left pending to loop on.
     */
    this._railObserver = new ResizeObserver((entries) => {
      const height = entries[0]?.contentRect?.height;
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      window.requestAnimationFrame(() => publish(height));
    });
    this._railObserver.observe(rail);
  }

  /**
   * Forces the slotted header content (logo/search/icons) to fill the header
   * row instead of shrink-wrapping to its own content width.
   *
   * This used to be a `::slotted(*)` rule in the CSS. That works in
   * Experience Builder's Preview (native shadow), but LWC's synthetic shadow
   * — used for the real authenticated runtime — never gives `::slotted()`
   * any elements to match: synthetic shadow hoists component styles into
   * plain global stylesheets, and `::slotted()` is only meaningful inside an
   * actual shadow root's own stylesheet. Confirmed live: inserting the exact
   * same rule via the CSSOM matched nothing, while a plain attribute
   * selector on the assigned node matched fine — so this sets the same
   * properties directly via JS instead, which works under either shadow
   * mode since it never depends on `::slotted()` resolving at all.
   */
  syncHeaderSlotLayout() {
    if (!this.classList.contains("arc-runtime-shell")) {
      return;
    }

    const slot = this.template.querySelector('slot[name="header"]');
    const assigned = slot?.assignedElements ? slot.assignedElements() : [];

    for (const el of assigned) {
      el.style.setProperty("display", "block");
      el.style.setProperty("flex", "1 1 auto");
      el.style.setProperty("min-width", "0");
      el.style.setProperty("max-height", "100%");
      el.style.setProperty("box-sizing", "border-box");
    }
  }

  @wire(CurrentPageReference)
  handlePageRef(pageRef) {
    this._pageRef = pageRef;
    this.syncRuntimeShellClass();
    /* The wire re-fires on navigation, which covers routes reached without a
       history push (a full page load straight onto /login, say). */
    this.syncChromeVisibility();
  }

  /**
   * Header, sidebar and breadcrumb are hidden on the login and system routes.
   *
   * They live in this layout rather than in the pages, and this layout is
   * shared: Work and Envelope_Detail use it too and have no sidebar of their
   * own, so the header nav is their only navigation. Hiding by route keeps
   * their chrome intact while the login page gets none of it — which is why
   * this is done here and not by removing components from the layout.
   */
  syncChromeVisibility() {
    const showChrome = !isChromelessRoute();
    if (this.showChrome !== showChrome) {
      this.showChrome = showChrome;
    }
    this.classList.toggle("arc-chromeless", !showChrome);
  }

  syncRuntimeShellClass() {
    const inDesignMode = isExperienceBuilderDesignMode(this._pageRef);
    this.classList.toggle("arc-runtime-shell", !inDesignMode);
    this.classList.toggle("arc-design-mode", inDesignMode);
  }

  syncSidebarWidth(isCollapsed, { force = false } = {}) {
    if (!force && this._collapsed === isCollapsed) {
      return;
    }

    this._collapsed = isCollapsed;

    const width = isCollapsed
      ? SIDEBAR_COLLAPSED_WIDTH
      : SIDEBAR_LWR_EXPANDED_WIDTH;

    // Some preview/dev-runtime contexts intermittently fail to expose
    // `.style` on the host during connectedCallback; guard so that quirk
    // can't throw and abort the rest of this component's setup.
    if (this.style) {
      this.style.setProperty("--arc-sidebar-width", width);
    }
    this.classList.toggle("arc-sidebar-collapsed", isCollapsed);
  }
}