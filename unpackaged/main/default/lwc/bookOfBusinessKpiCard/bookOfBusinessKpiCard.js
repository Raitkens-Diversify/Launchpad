/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-22
 */
import { LightningElement, api } from "lwc";

export default class BookOfBusinessKpiCard extends LightningElement {
  @api label;
  @api value;
  @api subtext;
  @api trendLabel;
  @api trendDirection;

  get hasTrend() {
    return Boolean(this.trendLabel);
  }

  get trendClassName() {
    const direction = this.trendDirection === "negative" ? "negative" : "positive";
    return `div-kpi-card__trend div-kpi-card__trend--${direction}`;
  }
}