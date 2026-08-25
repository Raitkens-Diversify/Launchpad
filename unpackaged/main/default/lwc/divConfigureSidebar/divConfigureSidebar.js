/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-14
 */
import { LightningElement, api } from "lwc";
import { loadStyle } from "lightning/platformResourceLoader";
import diversifyStyles from "@salesforce/resourceUrl/diversifyStyles";

const DRAWER_TRANSITION_MS = 300;

export default class DivConfigureSidebar extends LightningElement {
  @api title = "Configure";
  @api applyLabel = "Apply";
  @api resetLabel = "Reset";

  _isOpen = false;
  isPresent = false;
  isAnimatedOpen = false;
  stylesLoaded = false;
  _escapeHandler;
  _closeTimerId;

  @api
  get isOpen() {
    return this._isOpen;
  }

  set isOpen(value) {
    const nextIsOpen = Boolean(value);

    if (nextIsOpen === this._isOpen) {
      return;
    }

    this._isOpen = nextIsOpen;
    this.clearCloseTimer();

    if (nextIsOpen) {
      this.isPresent = true;
      this.isAnimatedOpen = false;
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      requestAnimationFrame(() => {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        requestAnimationFrame(() => {
          if (this._isOpen) {
            this.isAnimatedOpen = true;
          }
        });
      });
      return;
    }

    this.isAnimatedOpen = false;
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this._closeTimerId = window.setTimeout(() => {
      if (!this._isOpen) {
        this.isPresent = false;
      }

      this._closeTimerId = null;
    }, DRAWER_TRANSITION_MS);
  }

  get drawerClass() {
    return this.isAnimatedOpen ? "div-drawer div-drawer--open" : "div-drawer";
  }

  connectedCallback() {
    if (!this.stylesLoaded) {
      loadStyle(this, diversifyStyles)
        .then(() => {
          this.stylesLoaded = true;
        })
        .catch((error) => {
          console.error("[divConfigureSidebar] Failed to load diversifyStyles", error);
        });
    }

    this._escapeHandler = this.handleEscapeKey.bind(this);
    window.addEventListener("keydown", this._escapeHandler);
  }

  disconnectedCallback() {
    window.removeEventListener("keydown", this._escapeHandler);
    this.clearCloseTimer();
  }

  clearCloseTimer() {
    if (this._closeTimerId) {
      window.clearTimeout(this._closeTimerId);
      this._closeTimerId = null;
    }
  }

  handleEscapeKey(event) {
    if (event.key !== "Escape" || !this.isOpen) {
      return;
    }

    event.preventDefault();
    event.stopPropagation();
    this.handleClose();
  }

  handleClose() {
    this.dispatchEvent(new CustomEvent("close"));
  }

  handleApply() {
    this.dispatchEvent(new CustomEvent("apply"));
  }

  handleReset() {
    this.dispatchEvent(new CustomEvent("reset"));
  }
}