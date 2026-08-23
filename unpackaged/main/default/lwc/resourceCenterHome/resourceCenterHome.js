import { LightningElement, wire } from 'lwc';
import { iconPath } from 'c/rcIcons';
import getTopLevelCategories from '@salesforce/apex/ResourceCenterService.getTopLevelCategories';
import getFeaturedResources from '@salesforce/apex/ResourceCenterService.getFeaturedResources';

/**
 * resourceCenterHome — landing view: hero + search, featured strip, and the
 * grid of top-level category tiles. Emits (composed) events the orchestrator
 * catches: `rcsearch { term }` and `categoryselect { slug }`.
 */
export default class ResourceCenterHome extends LightningElement {
    categories;
    categoriesError = false;
    categoriesLoading = true;

    featured;
    featuredLoading = true;

    @wire(getTopLevelCategories)
    wiredCategories({ data, error }) {
        if (data) {
            this.categories = data;
            this.categoriesLoading = false;
        } else if (error) {
            this.categoriesError = true;
            this.categoriesLoading = false;
        }
    }

    @wire(getFeaturedResources)
    wiredFeatured({ data }) {
        if (data) {
            this.featured = data;
        }
        this.featuredLoading = false;
    }

    get categoryItems() {
        return (this.categories || []).map((c) => ({
            ...c,
            iconPath: iconPath(c.iconName)
        }));
    }
    get hasCategories() {
        return this.categories && this.categories.length > 0;
    }
    get hasFeatured() {
        return this.featured && this.featured.length > 0;
    }
    get showCategoriesEmpty() {
        return !this.categoriesLoading && !this.categoriesError && !this.hasCategories;
    }

    handleSuggestionSelect(event) {
        this.dispatchEvent(new CustomEvent('resourceselect', {
            detail: { slug: event.detail.slug }, bubbles: true, composed: true
        }));
    }
    handleSearchSubmit(event) {
        const term = (event.detail.value || '').trim();
        if (term) {
            this.dispatchEvent(new CustomEvent('rcsearch', {
                detail: { term }, bubbles: true, composed: true
            }));
        }
    }
    handleCategory(event) {
        const slug = event.currentTarget.dataset.slug;
        this.dispatchEvent(new CustomEvent('categoryselect', {
            detail: { slug }, bubbles: true, composed: true
        }));
    }
    handleGetHelp() {
        this.dispatchEvent(new CustomEvent('guideopen', {
            bubbles: true, composed: true
        }));
    }
}