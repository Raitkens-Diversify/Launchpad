import { LightningElement } from "lwc";
import fetchHasSeenWelcome from "@salesforce/apex/ArcHomeWelcomeController.fetchHasSeenWelcome";
import markWelcomeSeen from "@salesforce/apex/ArcHomeWelcomeController.markWelcomeSeen";

/**
 * arcWelcomeExperience
 *
 * First-login experience for ARC, in two stages inside one panel: the welcome
 * message, then — only if the user asks for it — a guided walkthrough of the
 * app drawn as a scaled-down picture of it (c/arcTourPreview). This component
 * owns eligibility and which step is current; it draws none of it.
 *
 * WHY A PICTURE RATHER THAN THE REAL APP. An earlier version drove the real
 * thing: it navigated to each page, waited for the route and the @wire, then
 * spotlighted whatever arrived. That worked, but every step cost a route
 * transition plus a server round trip — most of a second of dead screen, ten
 * times over — and it could only show a case if the user happened to have an
 * open one, so the tour was a different length for different people. Drawing
 * the app instead makes a step change a single paint, always lands the
 * highlight in the right place, and shows the same thing to everyone on their
 * first day. The cost is that the preview's sample content has to be kept
 * plausible by hand; its chrome cannot drift, because the sidebar is rendered
 * from the same STATIC_NAV_ITEMS the real navigation uses.
 *
 * Because nothing navigates any more, this component belongs on the Home page
 * (where it is placed today), not in the theme layout.
 *
 * Normally shows once, on the first login ever, then never again: it opens only
 * when fetchHasSeenWelcome comes back false, and leaving marks the flag through
 * ArcHomeWelcomeController, which persists on the user's own
 * User_Preference__c row rather than anything client-side — a different browser
 * or a cleared cache cannot bring it back. ALWAYS_SHOW below overrides that for
 * demos; see the note on it.
 *
 * fetchHasSeenWelcome is a non-cacheable imperative call, not
 * @wire(getHasSeenWelcome). The cacheable version is held client-side by
 * Lightning Data Service with no invalidation when markWelcomeSeen writes, so
 * a wired read kept reporting the pre-dismiss false after the flag had already
 * flipped and the walkthrough reopened on the next page view in the same
 * session.
 *
 * EVERY exit marks it seen — Finish, Skip, the ×, and Escape. The requirement
 * is "once ever", so a user who leaves early has still had their one showing.
 */

/**
 * Demo mode. While this is true the walkthrough opens on EVERY visit to Home
 * instead of only on a user's first login ever, so it can be shown repeatedly
 * without resetting anyone's User_Preference__c row. Requested 2026-08-21 as a
 * temporary setting.
 *
 * The seen flag is still written on exit while this is on — it is read that is
 * skipped, not the write — so flipping this back to false restores once-ever
 * behaviour straight away with no stored state to clean up.
 *
 * Set back to false before this reaches real users, or everyone gets the tour
 * on every page view.
 */
const ALWAYS_SHOW = true;

/**
 * The walkthrough.
 *
 *  screen — which page c/arcTourPreview draws (a key into its SCREENS map).
 *  navId  — the sidebar entry to light, from STATIC_NAV_ITEMS. The preview
 *           expands whichever group holds it, so a child id is safe here.
 *  region — the part of the drawn page to light: "tiles", "charts", "list",
 *           "tabs", "path", "tracks", "current-task", "hero" or "header". Both
 *           navId and region light at once, which is the point: every step
 *           shows the thing AND where it lives in the rail.
 *
 * Every step is a fixed pair of those, so the tour is the same length and the
 * same shape for every user — no step can fail to resolve.
 */
const STEPS = [
  {
    key: "home",
    screen: "home",
    navId: "arc-nav-home",
    region: "tiles",
    title: "Start here",
    body: "Home is your dashboard. It opens on the cases and tasks assigned to you and your team, whatever is waiting on the home office, and announcements from the firm."
  },
  {
    key: "contacts",
    screen: "contacts",
    navId: "arc-nav-contacts",
    region: "tabs",
    title: "Find a client",
    body: "Everyone you work with lives under Contacts — individuals, households, businesses, retirement plans, and trusts and estates. Each one is a tab on the same list."
  },
  {
    key: "cases",
    screen: "cases",
    navId: "arc-nav-work-cases",
    region: "list",
    title: "Work is grouped into cases",
    body: "A case is one piece of business — an account opening, a maintenance request — and it carries every task that belongs to it. Cases live under Work in the sidebar."
  },
  {
    key: "case-path",
    screen: "case",
    navId: "arc-nav-work-cases",
    region: "path",
    title: "Where a case stands",
    body: "Open a case and the path across the top tells you where it has got to. The highlighted step is the current one, so you can see at a glance what has happened and what comes next."
  },
  {
    key: "case-tracks",
    screen: "case",
    navId: "arc-nav-work-tasks",
    region: "tracks",
    title: "Main track and pit stops",
    body: "Main track tasks are the ordinary steps that carry a case forward, and are yours to complete. A pit stop is work parked with someone else — the home office or the branch — so you can tell progress from waiting."
  },
  {
    key: "tasks",
    screen: "tasks",
    navId: "arc-nav-work-tasks",
    region: "list",
    title: "Every task in one place",
    body: "The Tasks list gathers your work across all of your cases, split the same way. Group it, filter it, and save the view you want to come back to."
  },
  {
    key: "isas",
    screen: "isas",
    navId: "arc-nav-isas",
    region: "list",
    title: "Accounts and agreements",
    body: "Investments & Agreements holds your clients' accounts, their directly held investments, and the service agreements that go with them."
  },
  {
    key: "compliance",
    screen: "compliance",
    navId: "arc-nav-compliance-advertising-reviews",
    region: "list",
    title: "Submit for compliance",
    body: "Advertising Reviews is where material goes for approval. Submit it, follow it through review, and the history stays alongside it."
  },
  {
    key: "resources",
    screen: "resources",
    navId: "arc-nav-learning",
    region: "hero",
    title: "Guides and answers",
    body: "The Resource Center has the guides, articles and forms you will need. The ? in the header brings you straight back here from anywhere in ARC."
  },
  {
    key: "settings",
    screen: "settings",
    navId: null,
    region: "header",
    title: "Your account",
    body: "Your own details, notification preferences and password live behind the gear icon at the top right. That is the tour — welcome to ARC."
  }
];

export default class ArcWelcomeExperience extends LightningElement {
  /** The panel renders no DOM at all while this is false. */
  isOpen = false;

  /** "welcome" for the opening message, "tour" for the walkthrough. */
  stage = "welcome";

  stepIndex = 0;

  /** Guards against writing the flag twice. */
  _seenRecorded = false;
  _destroyed = false;
  _keydownHandler = null;

  connectedCallback() {
    /*
     * Escape leaves the walkthrough. dsModalV2 already closes itself on Escape
     * and that reaches us as `dismiss`, so this handler exists only to keep the
     * behaviour identical if the panel is ever hosted without it.
     */
    this._keydownHandler = (event) => {
      if (event.key === "Escape" && this.isOpen) {
        this.finish();
      }
    };
    window.addEventListener("keydown", this._keydownHandler);

    if (ALWAYS_SHOW) {
      this.isOpen = true;
      return;
    }

    fetchHasSeenWelcome()
      .then((seen) => {
        if (seen === false && !this._destroyed) {
          this.isOpen = true;
        }
      })
      .catch((error) => {
        // Don't strand a returning user behind a welcome that failed to load —
        // fail closed, the same way the Help Center's own welcome flow does.
        this.isOpen = false;
        // eslint-disable-next-line no-console
        console.error(
          "[arcWelcomeExperience] Failed to load welcome state",
          error
        );
      });
  }

  disconnectedCallback() {
    this._destroyed = true;
    if (this._keydownHandler) {
      window.removeEventListener("keydown", this._keydownHandler);
      this._keydownHandler = null;
    }
  }

  // ---- current step ------------------------------------------------------

  get currentStep() {
    return STEPS[this.stepIndex] || STEPS[0];
  }

  get stepCount() {
    return STEPS.length;
  }

  get stepTitle() {
    return this.currentStep.title;
  }

  get stepBody() {
    return this.currentStep.body;
  }

  get screen() {
    return this.currentStep.screen;
  }

  get navId() {
    return this.currentStep.navId;
  }

  get region() {
    return this.currentStep.region;
  }

  // ---- panel events ------------------------------------------------------

  /** "Let's Go" — same panel, second stage. */
  handleStart() {
    this.stepIndex = 0;
    this.stage = "tour";
  }

  handleNext() {
    if (this.stepIndex < STEPS.length - 1) {
      this.stepIndex += 1;
      return;
    }
    this.finish();
  }

  handleBack() {
    if (this.stepIndex > 0) {
      this.stepIndex -= 1;
    }
  }

  handleSkip() {
    this.finish();
  }

  /** The × or Escape, at either stage. Still counts as the one showing. */
  handleDismiss() {
    this.finish();
  }

  /**
   * Closes immediately and records the flag in the background, so a slow
   * request cannot leave the panel sitting over the page the user just asked to
   * get into. If the write fails the flag stays false and the welcome opens
   * once more on a later visit, rather than the failure being swallowed.
   */
  finish() {
    this.isOpen = false;

    if (this._seenRecorded) {
      return;
    }
    this._seenRecorded = true;

    markWelcomeSeen().catch((error) => {
      this._seenRecorded = false;
      // eslint-disable-next-line no-console
      console.error(
        "[arcWelcomeExperience] Failed to save welcome state",
        error
      );
    });
  }
}