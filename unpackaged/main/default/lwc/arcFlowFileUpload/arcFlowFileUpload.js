/**
 * Flow-screen file upload for the ARC (LWR) site.
 *
 * Drop-in replacement for the standard forceContent:fileUpload flow component,
 * which is Aura-based and refuses to load in the LWR flow runtime ("We
 * couldn't load all the components on this page"). Same contract: an optional
 * label, a multiple toggle, and a contentDocIds output collecting the
 * ContentDocument ids of everything uploaded, which the flow then links to the
 * record it creates.
 */
import { LightningElement, api } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';

export default class ArcFlowFileUpload extends LightningElement {
    @api label = 'Upload Files';
    @api multiple = false;
    /** Optional record to attach uploads to; unset uploads unattached files. */
    @api recordId;
    @api contentDocIds = [];

    uploadedFileNames = [];

    get acceptsMultiple() {
        return this.multiple === true || this.multiple === 'true';
    }

    get hasUploads() {
        return this.uploadedFileNames.length > 0;
    }

    handleUploadFinished(event) {
        const files = event.detail?.files || [];
        if (!files.length) {
            return;
        }

        const ids = new Set(this.contentDocIds || []);
        files.forEach((file) => ids.add(file.documentId));
        this.contentDocIds = [...ids];
        this.uploadedFileNames = [
            ...this.uploadedFileNames,
            ...files.map((file) => file.name)
        ];

        this.dispatchEvent(
            new FlowAttributeChangeEvent('contentDocIds', this.contentDocIds)
        );
    }
}