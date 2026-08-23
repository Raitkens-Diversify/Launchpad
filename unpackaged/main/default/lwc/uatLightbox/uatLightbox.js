import { LightningElement, api } from 'lwc';
import { formatDateTimeLong } from 'c/uatCardUtil';

/**
 * uatLightbox — the screenshot preview. A screenshot thumbnail used to be a
 * link to the shepherd *download* URL, so "look at the evidence" meant a file
 * landing in Downloads and being opened from there. This is the in-page
 * alternative: a full-size image in an overlay, previous / next across the
 * gallery it was opened from, ← → Esc on the keyboard, and Download still one
 * click away for anyone who wants the file.
 *
 * Image source: the ContentVersion download servlet serves the original bytes
 * and an <img> renders them inline regardless of the attachment header, which
 * is what the 720×480 thumbnail rendition could not give (screenshots of a
 * full Lightning page are unreadable at that size). If the original refuses
 * to load, the thumbnail rendition is the fallback, so the overlay never
 * shows a broken image for a file that has a thumbnail on screen.
 *
 * Stacking: the overlay is position: fixed at --env-z-lightbox (above the
 * 9000 modal layer), so it works from the report tree and from inside the
 * finding / run viewer dialogs alike. Escape is intercepted on window in the
 * capture phase because dsModalV2 listens for Escape on window too — without
 * that, closing the preview would close the dialog behind it as well.
 *
 * Contract: files = [FileDTO] (the IMAGE files of one gallery), index = the
 * one to open on. Emits `close`. Navigation is internal state.
 */
export default class UatLightbox extends LightningElement {
    @api files = [];
    @api index = 0;

    /** Internal cursor; seeded from `index` on connect, moved by prev/next. */
    current = 0;
    /** True once the full-size image has loaded; the spinner shows until then. */
    loaded = false;
    /** Set when the original failed and we fell back to the thumbnail. */
    fallback = false;

    _keydownHandler = null;
    _previousFocus = null;

    connectedCallback() {
        this.current = this.clamp(this.index);
        this._previousFocus = document.activeElement;
        this._keydownHandler = (event) => this.handleWindowKeydown(event);
        // Capture phase: runs before dsModalV2's bubble-phase Escape handler.
        window.addEventListener('keydown', this._keydownHandler, true);
    }

    renderedCallback() {
        if (!this._focused) {
            this._focused = true;
            const dialog = this.template.querySelector('.ulb__dialog');
            if (dialog) {
                dialog.focus();
            }
        }
    }

    disconnectedCallback() {
        if (this._keydownHandler) {
            window.removeEventListener('keydown', this._keydownHandler, true);
            this._keydownHandler = null;
        }
        const prev = this._previousFocus;
        if (prev && typeof prev.focus === 'function' && document.contains(prev)) {
            prev.focus();
        }
    }

    // ---- View ------------------------------------------------------------------

    get list() {
        return Array.isArray(this.files) ? this.files : [];
    }

    clamp(i) {
        const n = this.list.length;
        const v = Number(i) || 0;
        return n === 0 ? 0 : Math.min(Math.max(v, 0), n - 1);
    }

    get file() {
        return this.list[this.current] || null;
    }

    get hasFile() {
        return this.file !== null;
    }

    get src() {
        const f = this.file;
        if (!f) {
            return '';
        }
        if (this.fallback || !f.versionId) {
            return f.thumbnailUrl || f.downloadUrl;
        }
        return `/sfc/servlet.shepherd/version/download/${f.versionId}`;
    }

    get title() {
        return this.file ? this.file.title || 'Screenshot' : '';
    }

    get downloadUrl() {
        return this.file ? this.file.downloadUrl : '';
    }

    get hasMany() {
        return this.list.length > 1;
    }

    get position() {
        return this.hasMany ? `${this.current + 1} of ${this.list.length}` : '';
    }

    get prevDisabled() {
        return this.current <= 0;
    }

    get nextDisabled() {
        return this.current >= this.list.length - 1;
    }

    /** "Uploaded by Sarah Hindmarsh · Aug 19, 2026, 2:14 PM" when the DTO
     *  carries it (report payloads do; the tester widget's does too). */
    get metaLine() {
        const f = this.file;
        if (!f) {
            return '';
        }
        const parts = [];
        if (f.uploadedByName) {
            parts.push(`Uploaded by ${f.uploadedByName}`);
        }
        if (f.createdDate) {
            parts.push(formatDateTimeLong(f.createdDate));
        }
        return parts.join(' · ');
    }

    get stageClass() {
        return this.loaded ? 'ulb__stage ulb__stage--ready' : 'ulb__stage';
    }

    get dialogLabel() {
        return this.position ? `${this.title} (${this.position})` : this.title;
    }

    // ---- Navigation ------------------------------------------------------------

    go(delta) {
        const next = this.clamp(this.current + delta);
        if (next !== this.current) {
            this.current = next;
            this.loaded = false;
            this.fallback = false;
        }
    }

    handlePrev(event) {
        event.stopPropagation();
        this.go(-1);
    }

    handleNext(event) {
        event.stopPropagation();
        this.go(1);
    }

    close() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleClose(event) {
        event.stopPropagation();
        this.close();
    }

    /** Empty space closes — the backdrop or the stage around the image. The
     *  image, the bars and the buttons do not. */
    handleBackdropClick(event) {
        const t = event.target;
        if (t === event.currentTarget || (t.classList && t.classList.contains('ulb__stage'))) {
            this.close();
        }
    }

    handleWindowKeydown(event) {
        if (event.key === 'Escape') {
            event.stopImmediatePropagation();
            event.preventDefault();
            this.close();
        } else if (event.key === 'ArrowLeft') {
            event.stopImmediatePropagation();
            this.go(-1);
        } else if (event.key === 'ArrowRight') {
            event.stopImmediatePropagation();
            this.go(1);
        }
    }

    // ---- Image lifecycle -------------------------------------------------------

    handleLoad() {
        this.loaded = true;
    }

    handleError() {
        if (!this.fallback) {
            this.fallback = true;
            return;
        }
        // Both sources failed; show the frame anyway so the user can close or
        // download instead of staring at a spinner.
        this.loaded = true;
    }
}