/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-12
 */
import { LightningElement, wire } from "lwc";
import { loadScript, loadStyle } from "lightning/platformResourceLoader";
import chartjs from "@salesforce/resourceUrl/chartjs";
import diversifyStyles from "@salesforce/resourceUrl/diversifyStyles";
import getCaseMetrics from "@salesforce/apex/ArcCaseMetricsController.getCaseMetrics";

const SCOPE_MY = "My";
const SCOPE_TEAM = "Team";

const SCOPE_OPTIONS = [
  { value: SCOPE_MY, label: "My" },
  { value: SCOPE_TEAM, label: "My Team" },
];

const SEGMENT_COLORS = [
  "#032d60",
  "#066afe",
  "#fe5c4c",
  "#9050e9",
  "#22c55e",
  "#41b5ff",
  "#f59e0b",
  "#64748b",
];

const resolveSegmentColor = (segmentKey, index) => {
  const normalizedKey = (segmentKey || "").toLowerCase();

  if (normalizedKey.includes("ho-submission") || normalizedKey.includes("ho submission")) {
    return "#032d60";
  }

  if (normalizedKey.includes("branch-goal") || normalizedKey.includes("branch goal")) {
    return "#066afe";
  }

  if (normalizedKey.includes("ho-goal") || normalizedKey.includes("ho goal")) {
    return "#fe5c4c";
  }

  return SEGMENT_COLORS[index % SEGMENT_COLORS.length];
};

export default class ArcCaseMetrics extends LightningElement {
  scope = SCOPE_MY;
  segments = [];
  totalCount = 0;
  errorMessage = "";
  isInitialLoading = true;
  chart;
  chartJsLoaded = false;
  _stylesLoaded = false;
  _renderSignature = "";

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
        this.renderChart();
      })
      .catch((error) => {
        // eslint-disable-next-line no-console
        console.error("[arcCaseMetrics] Failed to load Chart.js", error);
      });
  }

  disconnectedCallback() {
    this.destroyChart();
  }

  renderedCallback() {
    if (this.chartJsLoaded && !this.isInitialLoading) {
      this.renderChart();
    }
  }

  @wire(getCaseMetrics, { scope: "$scope" })
  wiredCaseMetrics({ data, error }) {
    if (data) {
      this.isInitialLoading = false;
      this.totalCount = data.totalCount || 0;
      this.segments = (data.segments || []).map((segment, index) => {
        const count = segment.count || 0;
        const share = this.totalCount > 0 ? Math.round((count / this.totalCount) * 100) : 0;
        const color = resolveSegmentColor(segment.key, index);

        return {
          key: segment.key,
          label: segment.label,
          count,
          share,
          countLabel: `(${count})`,
          color,
          swatchStyle: `background-color: ${color}`,
        };
      });
      this.errorMessage = "";
      this._renderSignature = "";
      return;
    }

    if (error) {
      this.isInitialLoading = false;
      this.segments = [];
      this.totalCount = 0;
      this.errorMessage = this.reduceError(error);
      this._renderSignature = "";
      // eslint-disable-next-line no-console
      console.error("[arcCaseMetrics] Failed to load case metrics", error);
    }
  }

  get scopeOptions() {
    return SCOPE_OPTIONS;
  }

  get hasChartData() {
    return this.segments.length > 0;
  }

  destroyChart() {
    if (this.chart) {
      this.chart.destroy();
      this.chart = null;
    }
  }

  buildRenderSignature() {
    return JSON.stringify({
      scope: this.scope,
      segments: this.segments.map((segment) => ({
        key: segment.key,
        count: segment.count,
        color: segment.color,
      })),
    });
  }

  renderChart() {
    if (!this.chartJsLoaded || !window.Chart || this.isInitialLoading) {
      return;
    }

    const signature = this.buildRenderSignature();
    if (signature === this._renderSignature && this.chart) {
      return;
    }

    this._renderSignature = signature;
    this.destroyChart();

    const canvas = this.template.querySelector('[data-id="case-metrics-chart"]');
    if (!canvas || !this.hasChartData) {
      return;
    }

    this.chart = new window.Chart(canvas, {
      type: "doughnut",
      data: {
        labels: this.segments.map((segment) => segment.label),
        datasets: [
          {
            data: this.segments.map((segment) => segment.count),
            backgroundColor: this.segments.map((segment) => segment.color),
            borderColor: "#ffffff",
            borderWidth: 2,
            spacing: 2,
          },
        ],
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        cutout: "62%",
        plugins: {
          legend: {
            display: false,
          },
          tooltip: {
            callbacks: {
              label: (context) => {
                const segment = this.segments[context.dataIndex];
                return `${segment.label}: ${segment.count} (${segment.share}%)`;
              },
            },
          },
        },
      },
    });
  }

  handleScopeChange(event) {
    const nextScope = event.detail?.value;
    if (!nextScope || nextScope === this.scope) {
      return;
    }

    this.scope = nextScope;
    this.isInitialLoading = true;
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