/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-11
 */
import { LightningElement, wire } from "lwc";
import { loadStyle } from "lightning/platformResourceLoader";
import diversifyStyles from "@salesforce/resourceUrl/diversifyStyles";
import getTaskMetrics from "@salesforce/apex/ArcTaskMetricsController.getTaskMetrics";

const SCOPE_MY = "My";
const SCOPE_TEAM = "Team";
const BAR_TRANSITION =
  "width var(--arc-task-metrics-bar-duration, 500ms) var(--arc-task-metrics-bar-easing, cubic-bezier(0.4, 0, 0.2, 1))";

const SCOPE_OPTIONS = [
  { value: SCOPE_MY, label: "My" },
  { value: SCOPE_TEAM, label: "My Team" },
];

const METRIC_DEFINITIONS = [
  {
    key: "mainTrack",
    label: "Main track",
    countField: "mainTrackCount",
    barClass:
      "arc-task-metrics__bar-fill arc-task-metrics__bar-fill--main-track",
  },
  {
    key: "hoPitStop",
    label: "HO pit stop",
    countField: "hoPitStopCount",
    barClass:
      "arc-task-metrics__bar-fill arc-task-metrics__bar-fill--ho-pit-stop",
  },
  {
    key: "branchPitStop",
    label: "Branch pit stop",
    countField: "branchPitStopCount",
    barClass:
      "arc-task-metrics__bar-fill arc-task-metrics__bar-fill--branch-pit-stop",
  },
];

export default class ArcTaskMetrics extends LightningElement {
  scope = SCOPE_MY;
  metrics = {
    mainTrackCount: 0,
    hoPitStopCount: 0,
    branchPitStopCount: 0,
  };
  errorMessage = "";
  isInitialLoading = true;
  _stylesLoaded = false;
  _shouldAnimateBars = false;
  _prefersReducedMotion = false;
  _animationGeneration = 0;
  _animationTimeoutIds = [];

  connectedCallback() {
    this._prefersReducedMotion = window.matchMedia(
      "(prefers-reduced-motion: reduce)"
    ).matches;

    if (this._stylesLoaded) {
      return;
    }

    this._stylesLoaded = true;
    loadStyle(this, diversifyStyles).catch((error) => {
      // eslint-disable-next-line no-console
      console.error("[arcTaskMetrics] Failed to load diversifyStyles", error);
    });
  }

  renderedCallback() {
    if (!this._shouldAnimateBars || this.isInitialLoading) {
      return;
    }

    this._shouldAnimateBars = false;
    this.animateBarWidths();
  }

  @wire(getTaskMetrics, { scope: "$scope" })
  wiredTaskMetrics({ data, error }) {
    if (data) {
      this.isInitialLoading = false;
      this.metrics = {
        mainTrackCount: data.mainTrackCount || 0,
        hoPitStopCount: data.hoPitStopCount || 0,
        branchPitStopCount: data.branchPitStopCount || 0,
      };
      this.errorMessage = "";
      this.queueBarGrowAnimation();
      return;
    }

    if (error) {
      this.isInitialLoading = false;
      this.metrics = {
        mainTrackCount: 0,
        hoPitStopCount: 0,
        branchPitStopCount: 0,
      };
      this.errorMessage = this.reduceError(error);
      this.queueBarGrowAnimation();
      // eslint-disable-next-line no-console
      console.error("[arcTaskMetrics] Failed to load task metrics", error);
    }
  }

  get scopeOptions() {
    return SCOPE_OPTIONS;
  }

  get metricRows() {
    const counts = METRIC_DEFINITIONS.map(
      (definition) => this.metrics[definition.countField] || 0
    );
    const maxCount = Math.max(...counts, 1);

    return METRIC_DEFINITIONS.map((definition) => {
      const count = this.metrics[definition.countField] || 0;
      const percent = Math.round((count / maxCount) * 100);

      return {
        ...definition,
        count,
        percent,
      };
    });
  }

  queueBarGrowAnimation() {
    this._shouldAnimateBars = true;
  }

  clearBarAnimationTimeouts() {
    this._animationTimeoutIds.forEach((timeoutId) => {
      window.clearTimeout(timeoutId);
    });
    this._animationTimeoutIds = [];
  }

  animateBarWidths() {
    const wrappers = this.template.querySelectorAll("[data-bar-target-width]");

    if (!wrappers.length) {
      return;
    }

    this.clearBarAnimationTimeouts();
    const animationGeneration = ++this._animationGeneration;

    wrappers.forEach((wrapper) => {
      const targetWidth = `${wrapper.dataset.barTargetWidth}%`;

      if (this._prefersReducedMotion) {
        wrapper.style.width = targetWidth;
        return;
      }

      wrapper.style.transition = "none";
      wrapper.style.width = "0%";
    });

    if (this._prefersReducedMotion) {
      return;
    }

    // Force layout so width: 0 is committed before the grow transition runs.
    // eslint-disable-next-line no-unused-expressions
    wrappers[0].offsetWidth;

    wrappers.forEach((wrapper, index) => {
      const targetWidth = `${wrapper.dataset.barTargetWidth}%`;
      const delayMs = index * 50;

      const applyTargetWidth = () => {
        if (animationGeneration !== this._animationGeneration) {
          return;
        }

        wrapper.style.transition = BAR_TRANSITION;
        wrapper.style.width = targetWidth;
      };

      if (delayMs === 0) {
        applyTargetWidth();
        return;
      }

      // eslint-disable-next-line @lwc/lwc/no-async-operation
      const timeoutId = window.setTimeout(applyTargetWidth, delayMs);
      this._animationTimeoutIds.push(timeoutId);
    });
  }

  handleScopeChange(event) {
    const nextScope = event.detail?.value;
    if (!nextScope || nextScope === this.scope) {
      return;
    }

    this.scope = nextScope;
  }

  reduceError(error) {
    if (Array.isArray(error?.body)) {
      return error.body.map((item) => item.message).join(", ");
    }

    if (typeof error?.body?.message === "string") {
      return error.body.message;
    }

    if (typeof error?.message === "string") {
      return error.message;
    }

    return "Unable to load task metrics.";
  }
}