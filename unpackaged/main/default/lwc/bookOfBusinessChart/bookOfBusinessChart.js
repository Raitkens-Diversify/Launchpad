/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-22
 */
import { LightningElement, api } from "lwc";
import { loadScript } from "lightning/platformResourceLoader";
import chartjs from "@salesforce/resourceUrl/chartjs";
import { CHART_TYPE_BAR, CHART_TYPE_PIE } from "c/bookOfBusinessUtils";

const LAYOUT_TRANSITION_MS = 200;

const formatAxisCurrency = (value) => {
  const numericValue = Number(value) || 0;
  const absoluteValue = Math.abs(numericValue);

  if (absoluteValue >= 1000000) {
    return `$${Math.round(numericValue / 1000000)}M`;
  }

  if (absoluteValue >= 1000) {
    return `$${Math.round(numericValue / 1000)}K`;
  }

  return `$${Math.round(numericValue)}`;
};

const barValueLabelsPlugin = {
  id: "barValueLabels",
  afterDatasetsDraw(chart) {
    const pluginSegments = chart.options.plugins.barValueLabels?.segments || [];
    const { ctx } = chart;
    const datasetMeta = chart.getDatasetMeta(0);

    datasetMeta.data.forEach((bar, index) => {
      const segment = pluginSegments[index];
      if (!segment) {
        return;
      }

      ctx.save();
      ctx.fillStyle = "#2b3544";
      ctx.font =
        "600 12px -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif";
      ctx.textBaseline = "middle";
      ctx.fillText(segment.valueLabel, bar.x + 8, bar.y);
      ctx.restore();
    });
  }
};

export default class BookOfBusinessChart extends LightningElement {
  @api chartData;
  @api selectedSegmentKey;
  @api chartType = CHART_TYPE_PIE;

  chart;
  chartJsLoaded = false;
  isExpanded = false;
  _renderSignature = "";

  connectedCallback() {
    loadScript(this, chartjs)
      .then(() => {
        this.chartJsLoaded = true;
        this.renderChart();
      })
      .catch((error) => {
        // eslint-disable-next-line no-console
        console.error("[bookOfBusinessChart] Failed to load Chart.js", error);
      });
  }

  disconnectedCallback() {
    this.destroyChart();
  }

  renderedCallback() {
    if (this.chartJsLoaded) {
      this.renderChart();
    }
  }

  get hasChartData() {
    return (this.chartData?.segments || []).length > 0;
  }

  get isBarChart() {
    return this.chartType === CHART_TYPE_BAR;
  }

  get isPieChart() {
    return this.chartType === CHART_TYPE_PIE;
  }

  get barChartButtonClass() {
    return this.isBarChart
      ? "div-toolbar__segment div-toolbar__segment--active"
      : "div-toolbar__segment";
  }

  get pieChartButtonClass() {
    return this.isPieChart
      ? "div-toolbar__segment div-toolbar__segment--active"
      : "div-toolbar__segment";
  }

  get cardClass() {
    return "div-card div-chart-dashboard__card";
  }

  get expandIconName() {
    return this.isExpanded ? "utility:contract_alt" : "utility:expand_alt";
  }

  get expandButtonLabel() {
    return this.isExpanded ? "Collapse chart card" : "Expand chart card to half width";
  }

  get canvasWrapClass() {
    return this.isBarChart
      ? "div-chart__canvas-wrap div-chart__canvas-wrap--bar"
      : "div-chart__canvas-wrap div-chart__canvas-wrap--pie";
  }

  get chartAriaLabel() {
    return this.isBarChart
      ? "AUM by segment bar chart"
      : "AUM by segment donut chart";
  }

  get legendItems() {
    return (this.chartData?.segments || []).map((segment) => ({
      ...segment,
      isSelected: segment.key === this.selectedSegmentKey,
      itemClass:
        segment.key === this.selectedSegmentKey
          ? "div-chart-legend__item div-chart-legend__item--active"
          : "div-chart-legend__item",
      swatchStyle: `background-color: ${segment.color}`
    }));
  }

  destroyChart() {
    if (this.chart) {
      this.chart.destroy();
      this.chart = null;
    }
  }

  buildRenderSignature() {
    const segments = this.chartData?.segments || [];
    return JSON.stringify({
      chartType: this.chartType,
      selectedSegmentKey: this.selectedSegmentKey,
      segments: segments.map((segment) => ({
        key: segment.key,
        value: segment.value,
        color: segment.color
      }))
    });
  }

  renderChart() {
    if (!this.chartJsLoaded || !window.Chart) {
      return;
    }

    const signature = this.buildRenderSignature();

    if (signature === this._renderSignature && this.chart) {
      return;
    }

    this._renderSignature = signature;
    this.destroyChart();

    const canvas = this.template.querySelector('[data-id="segment-chart"]');

    if (!canvas || !this.hasChartData) {
      return;
    }

    const segments = this.chartData.segments;

    if (this.isPieChart) {
      this.renderPieChart(canvas, segments);
      return;
    }

    this.renderBarChart(canvas, segments);
  }

  renderBarChart(canvas, segments) {
    const maxValue = Math.max(...segments.map((segment) => segment.value), 1);
    const axisMax = Math.ceil((maxValue * 1.15) / 1000000) * 1000000;

    this.chart = new window.Chart(canvas, {
      type: "bar",
      data: {
        labels: segments.map((segment) => segment.label),
        datasets: [
          {
            data: segments.map((segment) => segment.value),
            backgroundColor: segments.map((segment) => segment.color),
            borderRadius: 6,
            barThickness: 28,
            maxBarThickness: 32
          }
        ]
      },
      options: {
        indexAxis: "y",
        responsive: true,
        maintainAspectRatio: false,
        layout: {
          padding: {
            right: 48
          }
        },
        scales: {
          x: {
            beginAtZero: true,
            max: axisMax,
            border: {
              display: false
            },
            grid: {
              color: "#e5e7eb"
            },
            ticks: {
              color: "#706e6b",
              font: {
                size: 11
              },
              callback: (value) => formatAxisCurrency(value)
            }
          },
          y: {
            border: {
              display: false
            },
            grid: {
              display: false
            },
            ticks: {
              color: "#2b3544",
              font: {
                size: 12,
                weight: "500"
              }
            }
          }
        },
        plugins: {
          legend: {
            display: false
          },
          tooltip: {
            callbacks: {
              label: (context) => {
                const segment = segments[context.dataIndex];
                return `${segment.valueLabel} (${segment.shareLabel})`;
              }
            }
          },
          barValueLabels: {
            segments
          }
        },
        onClick: (_event, elements) => {
          this.handleChartSegmentClick(segments, elements);
        }
      },
      plugins: [barValueLabelsPlugin]
    });
  }

  renderPieChart(canvas, segments) {
    const selectedKey = this.selectedSegmentKey;

    this.chart = new window.Chart(canvas, {
      type: "doughnut",
      data: {
        labels: segments.map((segment) => segment.label),
        datasets: [
          {
            data: segments.map((segment) => segment.value),
            backgroundColor: segments.map((segment) => segment.color),
            borderColor: "#ffffff",
            borderWidth: 2,
            spacing: 2,
            offset: segments.map((segment) =>
              segment.key === selectedKey ? 6 : 0
            )
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
                return `${segment.valueLabel} (${segment.percentLabel})`;
              }
            }
          }
        },
        onClick: (_event, elements) => {
          this.handleChartSegmentClick(segments, elements);
        }
      }
    });
  }

  handleChartSegmentClick(segments, elements) {
    if (!elements.length) {
      return;
    }

    const segment = segments[elements[0].index];

    this.dispatchEvent(
      new CustomEvent("segmentselect", {
        detail: {
          segmentKey: segment.key
        }
      })
    );
  }

  handleChartTypeChange(event) {
    const nextChartType = event.currentTarget.dataset.chartType;

    if (!nextChartType || nextChartType === this.chartType) {
      return;
    }

    this.dispatchEvent(
      new CustomEvent("charttypechange", {
        detail: {
          chartType: nextChartType
        }
      })
    );

    this._renderSignature = "";
    this.destroyChart();
    this.renderChart();
  }

  handleExpandToggle() {
    this.isExpanded = !this.isExpanded;

    this.dispatchEvent(
      new CustomEvent("expandchange", {
        detail: {
          expanded: this.isExpanded
        }
      })
    );

    if (!this.isBarChart || !this.chart) {
      return;
    }

    // Redraw bar chart after parent aside column width transition.
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    window.setTimeout(() => {
      this.chart?.resize();
    }, LAYOUT_TRANSITION_MS + 20);
  }

  handleLegendSelect(event) {
    const segmentKey = event.currentTarget.dataset.key;

    this.dispatchEvent(
      new CustomEvent("segmentselect", {
        detail: {
          segmentKey
        }
      })
    );
  }

  handleLegendKeyDown(event) {
    if (event.key !== "Enter" && event.key !== " ") {
      return;
    }

    event.preventDefault();
    this.handleLegendSelect(event);
  }
}