/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-12
 *
 * Draggable floating panel that renders the compact layout of a record.
 */
import { LightningElement, api, track } from 'lwc';
import {
    clampPreviewPanelPosition,
    PREVIEW_PANEL_HEIGHT,
    PREVIEW_PANEL_WIDTH
} from 'c/fscRelUtils';

export default class FscRelMemberPopover extends LightningElement {
    @api recordId;
    @api objectApiName = 'Account';
    @api memberName = '';
    @api left = 24;
    @api top = 24;
    @api useFixedPosition = false;
    @api useScrollRelativeBoundary = false;
    @api constrainToBoundary = false;
    @api boundaryLeft = 0;
    @api boundaryTop = 0;
    @api boundaryRight = 0;
    @api boundaryBottom = 0;
    @api boundaryScrollLeft = 0;
    @api boundaryScrollTop = 0;
    @api boundaryClientWidth = 0;
    @api boundaryClientHeight = 0;
    @api disableDrag = false;

    @track _internalLeft = 24;
    @track _internalTop = 24;

    _dragContext;
    _positionRecordId;

    get hasBoundary() {
        if (!this.constrainToBoundary) {
            return false;
        }

        if (this.useScrollRelativeBoundary) {
            return this.boundaryClientWidth > 0 && this.boundaryClientHeight > 0;
        }

        return (
            this.boundaryRight > this.boundaryLeft &&
            this.boundaryBottom > this.boundaryTop
        );
    }

    get boundaryRect() {
        if (this.useScrollRelativeBoundary) {
            return {
                scrollRelative: true,
                scrollLeft: this.boundaryScrollLeft,
                scrollTop: this.boundaryScrollTop,
                clientWidth: this.boundaryClientWidth,
                clientHeight: this.boundaryClientHeight
            };
        }

        return {
            left: this.boundaryLeft,
            top: this.boundaryTop,
            right: this.boundaryRight,
            bottom: this.boundaryBottom
        };
    }

    renderedCallback() {
        if (this.useScrollRelativeBoundary) {
            this.template.host.classList.add('member-popover-host_scroll-relative');
        } else {
            this.template.host.classList.remove('member-popover-host_scroll-relative');
        }

        if (!this.recordId) {
            this._positionRecordId = null;
            return;
        }

        if (this.disableDrag) {
            this.applyPosition(Number(this.left) || 0, Number(this.top) || 0);
            return;
        }

        if (!this._positionRecordId) {
            this.applyPosition(this.left, this.top);
            this._positionRecordId = this.recordId;
            return;
        }

        if (this.recordId !== this._positionRecordId) {
            this._positionRecordId = this.recordId;
        }
    }

    get panelClass() {
        const classes = ['member-panel', 'slds-popover', 'slds-popover_panel'];

        if (this.useFixedPosition) {
            classes.push('member-panel_fixed');
        }

        return classes.join(' ');
    }

    get panelStyle() {
        return `left: ${this._internalLeft}px; top: ${this._internalTop}px;`;
    }

    get headerClass() {
        const classes = ['member-panel__header', 'slds-p-around_x-small'];

        if (this.disableDrag) {
            classes.push('member-panel__header--anchored');
        }

        return classes.join(' ');
    }

    getPanelDimensions() {
        const panel = this.template.querySelector('.member-panel');

        return {
            panelWidth: panel?.offsetWidth || PREVIEW_PANEL_WIDTH,
            panelHeight: panel?.offsetHeight || PREVIEW_PANEL_HEIGHT
        };
    }

    applyPosition(left, top) {
        if (!this.hasBoundary) {
            this._internalLeft = left;
            this._internalTop = top;
            return;
        }

        const { panelWidth, panelHeight } = this.getPanelDimensions();
        const clamped = clampPreviewPanelPosition(left, top, this.boundaryRect, {
            panelWidth,
            panelHeight
        });

        this._internalLeft = clamped.left;
        this._internalTop = clamped.top;
    }

    handleDragStart(event) {
        if (this.disableDrag) {
            return;
        }

        if (event.button !== 0) {
            return;
        }

        if (event.target.closest('lightning-button-icon')) {
            return;
        }

        event.preventDefault();

        this._dragContext = {
            startX: event.clientX,
            startY: event.clientY,
            originLeft: this._internalLeft,
            originTop: this._internalTop
        };

        window.addEventListener('mousemove', this.handleWindowMouseMove);
        window.addEventListener('mouseup', this.handleWindowMouseUp);
    }

    handleWindowMouseMove = (event) => {
        if (!this._dragContext) {
            return;
        }

        const deltaX = event.clientX - this._dragContext.startX;
        const deltaY = event.clientY - this._dragContext.startY;

        this.applyPosition(
            this._dragContext.originLeft + deltaX,
            this._dragContext.originTop + deltaY
        );
    };

    handleWindowMouseUp = () => {
        this._dragContext = undefined;
        window.removeEventListener('mousemove', this.handleWindowMouseMove);
        window.removeEventListener('mouseup', this.handleWindowMouseUp);
    };

    handleCloseClick() {
        this.dispatchEvent(
            new CustomEvent('close', {
                bubbles: true,
                composed: true
            })
        );
    }

    disconnectedCallback() {
        this.template.host.classList.remove('member-popover-host_scroll-relative');
        this.handleWindowMouseUp();
    }
}