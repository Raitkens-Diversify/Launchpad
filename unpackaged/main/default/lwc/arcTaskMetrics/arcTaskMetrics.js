/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-11
 */
import { LightningElement, wire } from "lwc";
import { loadStyle } from "lightning/platformResourceLoader";
import diversifyStyles from "@salesforce/resourceUrl/diversifyStyles";
import NEXS_ICONS from "@salesforce/resourceUrl/arcicon";
import getTaskMetrics from "@salesforce/apex/ArcTaskMetricsController.getTaskMetrics";

const INFO_ICON = "info.svg";
const SCOPE_MY = "My";
const SCOPE_TEAM = "Team";
const BAR_TRANSITION =
  "width var(--arc-task-metrics-bar-duration, 500ms) var(--arc-task-metrics-bar-easing, cubic-bezier(0.4, 0, 0.2, 1))";

const METRIC_DEFINITIONS = [
  {
    key: "mainTrack",
    label: "Main track",
    countField: "mainTrackCount",
    barClass:
      "arc-task-metrics__bar-fill arc-task-metrics__bar-fill--main-track"
  },
  {
    key: "hoPitStop",
    label: "HO pit stop",
    countField: "hoPitStopCount",
    barClass:
      "arc-task-metrics__bar-fill arc-task-metrics__bar-fill--ho-pit-stop"
  },
  {
    key: "branchPitStop",
    label: "Branch pit stop",
    countField: "branchPitStopCount",
    barClass:
      "arc-task-metrics__bar-fill arc-task-metrics__bar-fill--branch-pit-stop"
  }
];

const EMPTY_METRICS = {
  mainTrackCount: 0,
  hoPitStopCount: 0,
  branchPitStopCount: 0
};

/**
 * A category with any real records must still show a sliver of color — e.g.
 * 1 of 460 rounds to 0% and the bar-fill-wrapper renders at zero width,
 * making the count look uncategorized even though its label reads "1".
 */
const MIN_VISIBLE_PERCENT = 3;

const buildMetricRows = (metrics) => {
  const counts = METRIC_DEFINITIONS.map(
    (definition) => metrics[definition.countField] || 0
  );
  const maxCount = Math.max(...counts, 1);

  return METRIC_DEFINITIONS.map((definition) => {
    const count = metrics[definition.countField] || 0;
    const rawPercent = Math.round((count / maxCount) * 100);
    const percent =
      count > 0 ? Math.max(rawPercent, MIN_VISIBLE_PERCENT) : 0;

    return {
      ...definition,
      count,
      percent
    };
  });
};

/**
 * My and My Team are shown side by side as two permanent panels rather than
 * a single click-to-toggle view, so both @wire calls run concurrently.
 */
export default class ArcTaskMetrics extends LightningElement {
  myMetrics = { ...EMPTY_METRICS };
  myErrorMessage = "";
  isMyInitialLoading = true;

  teamMetrics = { ...EMPTY_METRICS };
  teamErrorMessage = "";
  isTeamInitialLoading = true;

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

  @wire(getTaskMetrics, { scope: SCOPE_MY })
  wiredMyTaskMetrics({ data, error }) {
    if (data) {
      this.isMyInitialLoading = false;
      this.myMetrics = {
        mainTrackCount: data.mainTrackCount || 0,
        hoPitStopCount: data.hoPitStopCount || 0,
        branchPitStopCount: data.branchPitStopCount || 0
      };
      this.myErrorMessage = "";
      this.queueBarGrowAnimation();
      return;
    }

    if (error) {
      this.isMyInitialLoading = false;
      this.myMetrics = { ...EMPTY_METRICS };
      this.myErrorMessage = this.reduceError(error);
      this.queueBarGrowAnimation();
      // eslint-disable-next-line no-console
      console.error("[arcTaskMetrics] Failed to load My task metrics", error);
    }
  }

  @wire(getTaskMetrics, { scope: SCOPE_TEAM })
  wiredTeamTaskMetrics({ data, error }) {
    if (data) {
      this.isTeamInitialLoading = false;
      this.teamMetrics = {
        mainTrackCount: data.mainTrackCount || 0,
        hoPitStopCount: data.hoPitStopCount || 0,
        branchPitStopCount: data.branchPitStopCount || 0
      };
      this.teamErrorMessage = "";
      this.queueBarGrowAnimation();
      return;
    }

    if (error) {
      this.isTeamInitialLoading = false;
      this.teamMetrics = { ...EMPTY_METRICS };
      this.teamErrorMessage = this.reduceError(error);
      this.queueBarGrowAnimation();
      // eslint-disable-next-line no-console
      console.error(
        "[arcTaskMetrics] Failed to load My Team task metrics",
        error
      );
    }
  }

  get isInitialLoading() {
    return this.isMyInitialLoading && this.isTeamInitialLoading;
  }

  get infoIconStyle() {
    return `--icon-url: url('${NEXS_ICONS}/${INFO_ICON}');`;
  }

  get myMetricRows() {
    return buildMetricRows(this.myMetrics);
  }

  get teamMetricRows() {
    return buildMetricRows(this.teamMetrics);
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