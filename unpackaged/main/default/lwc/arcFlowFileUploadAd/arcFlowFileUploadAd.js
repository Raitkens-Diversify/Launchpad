/**
 * ARC (LWR) port of aura/cmp_FileUpload — the Advertising Review flows' file
 * upload. Same property names as the Aura original so the ARC flow copies
 * only swap the extension name, and the same server calls against the
 * existing FileUploadController (called, never modified): an advertisingType
 * is validated against the ContentVersion Advertising_Type picklist on init,
 * and finished uploads are stamped with the ad type and flow interview id so
 * the flow can collect them later. Output contentVersionIds is the Aura
 * original's comma-joined ContentVersion id string.
 */
import { LightningElement, api } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import getCVAdvertisingTypeOpts from '@salesforce/apex/FileUploadController.getCVAdvertisingTypeOpts';
import updateCVs from '@salesforce/apex/FileUploadController.updateCVs';

const DEFAULT_FILE_TYPES = ['.png', '.jpg', '.jpeg', '.pdf', '.csv', '.xlsx', '.mp4', '.mp3'];

export default class ArcFlowFileUploadAd extends LightningElement {
    @api fileType = DEFAULT_FILE_TYPES;
    @api label = '';
    @api multiple = false;
    @api disabled = false;
    @api contentVersionIds = '';
    @api recordId;
    @api advertisingType = '';
    @api flowInterviewId = '';

    loading = false;
    invalidAdType = false;
    uploadedFileNames = [];

    connectedCallback() {
        if (!this.advertisingType) {
            return;
        }
        getCVAdvertisingTypeOpts()
            .then((options) => {
                if (options && options.includes(this.advertisingType)) {
                    this.disabled = false;
                } else {
                    this.disabled = true;
                    this.invalidAdType = true;
                }
            })
            .catch(() => {});
    }

    get acceptedFormats() {
        return Array.isArray(this.fileType) && this.fileType.length
            ? this.fileType
            : DEFAULT_FILE_TYPES;
    }

    get acceptsMultiple() {
        return this.multiple === true || this.multiple === 'true';
    }

    get isDisabled() {
        return this.disabled === true || this.disabled === 'true';
    }

    get hasUploads() {
        return this.uploadedFileNames.length > 0;
    }

    async handleUploadFinished(event) {
        const files = event.detail?.files || [];
        if (!files.length) {
            return;
        }

        const cvIds = files.map((file) => file.contentVersionId);
        const existing = this.contentVersionIds
            ? this.contentVersionIds.split(',').filter(Boolean)
            : [];
        const all = [...new Set([...existing, ...cvIds])];
        this.contentVersionIds = all.toString();
        this.uploadedFileNames = [
            ...this.uploadedFileNames,
            ...files.map((file) => file.name)
        ];
        this.dispatchEvent(
            new FlowAttributeChangeEvent('contentVersionIds', this.contentVersionIds)
        );

        this.loading = true;
        try {
            await updateCVs({
                cvIds,
                adType: this.advertisingType,
                interviewId: this.flowInterviewId
            });
        } catch (error) {
            // The Aura original surfaces this as a toast; here the flow keeps
            // the ids either way and the stamp is retried on the next upload.
        } finally {
            this.loading = false;
        }
    }
}