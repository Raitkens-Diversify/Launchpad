import { LightningElement, api } from 'lwc';

/**
 * uatEvidenceGallery — the evidence grid the admin surfaces render (Cycle
 * Report tree, run viewer, Test Case detail). Image tiles open the file in
 * c-uat-lightbox, paging across the images of THIS gallery; other files stay
 * links to the download URL, because there is nothing to preview.
 *
 * One component instead of the same fifteen lines of markup in five places:
 * the moment a thumbnail stopped being "a link to the download" the
 * behaviour grew a state machine, and that belongs in one file.
 *
 * Props: files = [FileDTO]; removable + busy add a Remove action per tile
 * (emits `remove` with {contentDocumentId, title}; the host owns the confirm
 * and the delete); empty-text renders when there are no files.
 */
export default class UatEvidenceGallery extends LightningElement {
    @api files = [];
    @api removable = false;
    @api busy = false;
    @api emptyText;

    /** Index into `images` of the tile that was clicked, or null. */
    previewIndex = null;

    get list() {
        return Array.isArray(this.files) ? this.files : [];
    }

    get hasFiles() {
        return this.list.length > 0;
    }

    get showEmpty() {
        return !this.hasFiles && Boolean(this.emptyText);
    }

    get images() {
        return this.list.filter((f) => f && f.isImage);
    }

    get tiles() {
        let imageIndex = -1;
        return this.list.map((f) => {
            const isImage = Boolean(f && f.isImage);
            if (isImage) {
                imageIndex += 1;
            }
            return {
                key: f.contentDocumentId,
                contentDocumentId: f.contentDocumentId,
                title: f.title || 'File',
                isImage,
                imageIndex: isImage ? String(imageIndex) : null,
                thumbnailUrl: f.thumbnailUrl,
                downloadUrl: f.downloadUrl,
                openLabel: `Preview ${f.title || 'screenshot'}`,
                docLabel: `Download ${f.title || 'file'}`,
                extensionLabel: f.extension ? String(f.extension).toUpperCase() : 'FILE'
            };
        });
    }

    get previewOpen() {
        return this.previewIndex !== null;
    }

    handleOpen(event) {
        const i = Number(event.currentTarget.dataset.index);
        if (Number.isNaN(i)) {
            return;
        }
        this.previewIndex = i;
    }

    handlePreviewClose() {
        this.previewIndex = null;
    }

    handleRemove(event) {
        const ds = event.currentTarget.dataset;
        this.dispatchEvent(
            new CustomEvent('remove', {
                detail: { contentDocumentId: ds.docid, title: ds.title }
            })
        );
    }
}