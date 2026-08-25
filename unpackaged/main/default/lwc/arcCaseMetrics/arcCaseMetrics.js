/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-12
 */
import { LightningElement, wire } from "lwc";
import { loadScript, loadStyle } from "lightning/platformResourceLoader";
import chartjs from "@salesforce/resourceUrl/chartjs";
import diversifyStyles from "@salesforce/resourceUrl/diversifyStyles";
import NEXS_ICONS from "@salesforce/resourceUrl/arcicon";
import getCaseMetrics from "@salesforce/apex/ArcCaseMetricsController.getCaseMetrics";

const INFO_ICON = "info.svg";

const SCOPE_MY = "My";
const SCOPE_TEAM = "Team";

const SEGMENT_COLORS = [
  "#032d60",
  "#066afe",
  "#fe5c4c",
  "#9050e9",
  "#22c55e",
  "#41b5ff",
  "#f59e0b",
  "#64748b"
];

const resolveSegmentColor = (segmentKey, index) => {
  const normalizedKey = (segmentKey || "").toLowerCase();

  if (
    normalizedKey.includes("ho-submission") ||
    normalizedKey.includes("ho submission")
  ) {
    return "#032d60";
  }

  if (
    normalizedKey.includes("branch-goal") ||
    normalizedKey.includes("branch goal")
  ) {
    return "#066afe";
  }

  if (normalizedKey.includes("ho-goal") || normalizedKey.includes("ho goal")) {
    return "#fe5c4c";
  }

  return SEGMENT_COLORS[index % SEGMENT_COLORS.length];
};

const mapSegments = (data) => {
  const totalCount = data?.totalCount || 0;

  return (data?.segments || []).map((segment, index) => {
    const count = segment.count || 0;
    const share = totalCount > 0 ? Math.round((count / totalCount) * 100) : 0;
    const color = resolveSegmentColor(segment.key, index);

    return {
      key: segment.key,
      label: segment.label,
      count,
      share,
      countLabel: `${count}`,
      color,
      swatchStyle: `background-color: ${color}`
    };
  });
};

/**
 * My and My Team are shown side by side as two permanent panels rather than
 * a single click-to-toggle view, so both @wire calls run concurrently and
 * each panel gets its own Chart.js doughnut instance.
 */
export default class ArcCaseMetrics extends LightningElement {
  myTotalCount = 0;
  mySegments = [];
  myErrorMessage = "";
  isMyInitialLoading = true;

  teamTotalCount = 0;
  teamSegments = [];
  teamErrorMessage = "";
  isTeamInitialLoading = true;

  myChart;
  teamChart;
  chartJsLoaded = false;
  _stylesLoaded = false;
  _myRenderSignature = "";
  _teamRenderSignature = "";

  connectedCallback() {
    if (!this._stylesLoaded) {
      this._stylesLoaded = true;
      loadStyle(this, diversifyStyles).catch((error) => {
        // eslint-disable-next-line no-console
        console.error("[arcCaseMetrics] Failed to load diversifyStyles", error);
      });
    }

    loadScript(this, chartjs)
      .then(() => {
        this.chartJsLoaded = true;
        this.renderCharts();
      })
      .catch((error) => {
        // eslint-disable-next-line no-console
        console.error("[arcCaseMetrics] Failed to load Chart.js", error);
      });
  }

  disconnectedCallback() {
    this.destroyCharts();
  }

  renderedCallback() {
    if (this.chartJsLoaded) {
      this.renderCharts();
    }
  }

  @wire(getCaseMetrics, { scope: SCOPE_MY })
  wiredMyCaseMetrics({ data, error }) {
    if (data) {
      this.isMyInitialLoading = false;
      this.myTotalCount = data.totalCount || 0;
      this.mySegments = mapSegments(data);
      this.myErrorMessage = "";
      this._myRenderSignature = "";
      return;
    }

    if (error) {
      this.isMyInitialLoading = false;
      this.mySegments = [];
      this.myTotalCount = 0;
      this.myErrorMessage = this.reduceError(error);
      this._myRenderSignature = "";
      // eslint-disable-next-line no-console
      console.error("[arcCaseMetrics] Failed to load My case metrics", error);
    }
  }

  @wire(getCaseMetrics, { scope: SCOPE_TEAM })
  wiredTeamCaseMetrics({ data, error }) {
    if (data) {
      this.isTeamInitialLoading = false;
      this.teamTotalCount = data.totalCount || 0;
      this.teamSegments = mapSegments(data);
      this.teamErrorMessage = "";
      this._teamRenderSignature = "";
      return;
    }

    if (error) {
      this.isTeamInitialLoading = false;
      this.teamSegments = [];
      this.teamTotalCount = 0;
      this.teamErrorMessage = this.reduceError(error);
      this._teamRenderSignature = "";
      // eslint-disable-next-line no-console
      console.error(
        "[arcCaseMetrics] Failed to load My Team case metrics",
        error
      );
    }
  }

  get infoIconStyle() {
    return `--icon-url: url('${NEXS_ICONS}/${INFO_ICON}');`;
  }

  get isInitialLoading() {
    return this.isMyInitialLoading && this.isTeamInitialLoading;
  }

  get hasMyChartData() {
    return this.mySegments.length > 0;
  }

  get hasTeamChartData() {
    return this.teamSegments.length > 0;
  }

  destroyCharts() {
    if (this.myChart) {
      this.myChart.destroy();
      this.myChart = null;
    }

    if (this.teamChart) {
      this.teamChart.destroy();
      this.teamChart = null;
    }
  }

  buildRenderSignature(segments) {
    return JSON.stringify(
      segments.map((segment) => ({
        key: segment.key,
        count: segment.count,
        color: segment.color
      }))
    );
  }

  renderCharts() {
    if (!this.chartJsLoaded || !window.Chart) {
      return;
    }

    this.renderChart({
      loading: this.isMyInitialLoading,
      segments: this.mySegments,
      canvasId: "case-metrics-chart-my",
      signatureKey: "_myRenderSignature",
      chartKey: "myChart"
    });

    this.renderChart({
      loading: this.isTeamInitialLoading,
      segments: this.teamSegments,
      canvasId: "case-metrics-chart-team",
      signatureKey: "_teamRenderSignature",
      chartKey: "teamChart"
    });
  }

  renderChart({ loading, segments, canvasId, signatureKey, chartKey }) {
    if (loading || !segments.length) {
      return;
    }

    const signature = this.buildRenderSignature(segments);
    if (signature === this[signatureKey] && this[chartKey]) {
      return;
    }

    this[signatureKey] = signature;

    if (this[chartKey]) {
      this[chartKey].destroy();
      this[chartKey] = null;
    }

    const canvas = this.template.querySelector(`[data-id="${canvasId}"]`);
    if (!canvas) {
      return;
    }

    this[chartKey] = new window.Chart(canvas, {
      type: "doughnut",
      data: {
        labels: segments.map((segment) => segment.label),
        datasets: [
          {
            data: segments.map((segment) => segment.count),
            backgroundColor: segments.map((segment) => segment.color),
            borderColor: "#ffffff",
            borderWidth: 2,
            spacing: 2
          }
        ]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        cutout: "62%",
        plugins: {
          legend: {
            display: false
          },
          tooltip: {
            callbacks: {
              label: (context) => {
                const segment = segments[context.dataIndex];
                return `${segment.label}: ${segment.count} (${segment.share}%)`;
              }
            }
          }
        }
      }
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

    return "Unable to load case metrics.";
  }
}