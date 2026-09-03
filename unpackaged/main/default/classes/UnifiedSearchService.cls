/**
 * UnifiedSearchService
 *
 * Cross-app search aggregator for the Help Center + Resource Center (one LWR
 * site, two apps). Runs the two sides as parallel queries merged in Apex —
 * the mature Knowledge ranking pipeline (NexSKnowledgeController.searchRanked:
 * synonyms, fuzzy pass, popularity, did-you-mean) stays untouched, and
 * resources join its scoring scale through the scorer below.
 *
 * Contract decisions (2026-08-21 unification plan):
 *  - Grouped payload (articles / resources), each side ranked, BOTH carrying
 *    scores on the same scale — so a blended single list later is a UI-only
 *    flip, not an API change.
 *  - Symmetric degrade: each side pre-checks object access and catches its own
 *    failures; the other side's results always return, with the failed side
 *    flagged in meta. No side ever throws while the other is swallowed.
 *  - Cacheable: analytics stay a separate client round trip (searchLogUtil).
 *
 * Neutrally named on purpose: when the arc* fork converges, this is the one
 * search endpoint both surface families point at.
 *
 * Future optimization (deliberately NOT built): the two SOSL recalls could
 * merge into one multi-object FIND ... RETURNING Knowledge__kav(...),
 * Resource__c(...) with per-object LIMITs. At 2 SOSL per search against a
 * 20-SOSL budget there is nothing to buy yet, and the single-FIND form
 * complicates WITH DATA CATEGORY scoping — revisit only if transaction
 * pressure appears.
 */
public with sharing class UnifiedSearchService {

    // Resource results cap — same ceiling as both existing engines.
    private static final Integer MAX_RESULTS = 50;
    // Featured resources get the same flat boost Featured articles get.
    private static final Double FEATURED_BOOST = 3;
    // Typeahead cap across both kinds (matches the single-app dropdowns).
    private static final Integer MAX_TYPEAHEAD = 7;

    // ---- Wrappers exposed to LWC --------------------------------------------

    public class ResourceHit {
        @AuraEnabled public Id id;
        @AuraEnabled public String title;
        @AuraEnabled public String subtitle;      // Description__c
        @AuraEnabled public String slug;          // routing key
        @AuraEnabled public String resourceType;  // PDF/Form/Video/Template/External Link/Webinar
        @AuraEnabled public String externalUrl;
        /** Webinar-only: WebinarLifecycle status + sign-up link (null otherwise). */
        @AuraEnabled public String webinarStatus;
        @AuraEnabled public String registrationUrl;
        @AuraEnabled public String categorySlug;
        @AuraEnabled public Boolean featured;
        @AuraEnabled public Double score;
    }

    public class Meta {
        /** True when that side failed or was inaccessible — partial results. */
        @AuraEnabled public Boolean articlesDegraded = false;
        @AuraEnabled public Boolean resourcesDegraded = false;
        /** Knowledge engine provenance, passed through for the fuzzy banner. */
        @AuraEnabled public Boolean fuzzy = false;
        @AuraEnabled public String corrected;
        @AuraEnabled public String original;
    }

    public class UnifiedResults {
        @AuraEnabled public List<NexSKnowledgeController.ArticleSummary> articles =
            new List<NexSKnowledgeController.ArticleSummary>();
        @AuraEnabled public List<ResourceHit> resources = new List<ResourceHit>();
        @AuraEnabled public Meta meta = new Meta();
    }

    /** Normalized typeahead row — matches the c/dsSearchBar suggestion contract. */
    public class Suggestion {
        @AuraEnabled public Id id;
        @AuraEnabled public String title;
        @AuraEnabled public String subtitle;
        @AuraEnabled public String kind;     // 'article' | 'resource'
        @AuraEnabled public String routeKey; // article UrlName | resource Slug__c
    }

    // ---- Public API ----------------------------------------------------------

    /**
     * Full search across both apps. Grouped and scored per side; blank or
     * insignificant terms return empty sides (hosts render their own empties).
     */
    @AuraEnabled(cacheable=true)
    public static UnifiedResults search(String term) {
        UnifiedResults out = new UnifiedResults();
        if (String.isBlank(term)) {
            // A blank term is not a search — searchRanked would fall through to
            // its browse list, which is wrong for a results endpoint.
            return out;
        }

        // The isAccessible pre-checks live INSIDE the try blocks: for a user
        // without the Knowledge feature license, even describing/querying
        // Knowledge__kav throws NoAccessException ("entity is not api
        // accessible") — that must degrade like any other access gap, never
        // escape.
        try {
            if (!Schema.sObjectType.Knowledge__kav.isAccessible()) {
                out.meta.articlesDegraded = true;
            } else {
                NexSKnowledgeController.SearchResult sr =
                    NexSKnowledgeController.searchRanked(term, null, false);
                if (sr != null) {
                    out.articles = (sr.articles == null)
                        ? new List<NexSKnowledgeController.ArticleSummary>() : sr.articles;
                    out.meta.fuzzy = (sr.fuzzy == true);
                    out.meta.corrected = sr.corrected;
                    out.meta.original = sr.original;
                }
            }
        } catch (Exception e) {
            out.meta.articlesDegraded = true;
        }

        try {
            if (!Schema.sObjectType.Resource__c.isAccessible()) {
                out.meta.resourcesDegraded = true;
            } else {
                out.resources = searchResourcesScored(term);
            }
        } catch (Exception e) {
            out.meta.resourcesDegraded = true;
        }
        return out;
    }

    /**
     * Merged typeahead: article and resource suggestions interleaved by kind
     * (article first — the 10:1 content-volume ratio makes strict score
     * interleaving pointless at typeahead cost), capped at MAX_TYPEAHEAD.
     * Each side degrades silently — a dropdown is never worth an error.
     */
    @AuraEnabled(cacheable=true)
    public static List<Suggestion> typeahead(String term) {
        List<Suggestion> articles = new List<Suggestion>();
        List<Suggestion> resources = new List<Suggestion>();

        // Pre-checks inside the try blocks — see search(): a Knowledge-
        // unlicensed user throws on the describe itself.
        try {
            if (Schema.sObjectType.Knowledge__kav.isAccessible()) {
                for (NexSKnowledgeController.ArticleSummary a :
                        NexSKnowledgeController.typeahead(term, null)) {
                    Suggestion s = new Suggestion();
                    s.id = a.id;
                    s.title = a.title;
                    s.kind = 'article';
                    s.routeKey = a.urlName;
                    articles.add(s);
                }
            }
        } catch (Exception e) { /* articles side degrades silently */ }
        try {
            if (Schema.sObjectType.Resource__c.isAccessible()) {
                for (ResourceCenterService.ResourceCard c :
                        ResourceCenterService.typeahead(term)) {
                    Suggestion s = new Suggestion();
                    s.id = c.id;
                    s.title = c.name;
                    s.subtitle = c.resourceType;
                    s.kind = 'resource';
                    s.routeKey = c.slug;
                    resources.add(s);
                }
            }
        } catch (Exception e) { /* resources side degrades silently */ }

        List<Suggestion> merged = new List<Suggestion>();
        Integer ai = 0, ri = 0;
        while (merged.size() < MAX_TYPEAHEAD
               && (ai < articles.size() || ri < resources.size())) {
            if (ai < articles.size()) {
                merged.add(articles[ai++]);
            }
            if (merged.size() < MAX_TYPEAHEAD && ri < resources.size()) {
                merged.add(resources[ri++]);
            }
        }
        return merged;
    }

    // ---- Resource scoring ----------------------------------------------------

    /**
     * Scored resource search on the Knowledge engine's scale: same tokenizer /
     * stopwords / synonym expansion (via the controller's public seams), Name
     * weighted like a title, Description__c like a summary, Featured boosted
     * like a Featured article. No phrase/bigram/fuzzy passes — at the resource
     * catalog's size the field weights carry the signal.
     * Deliberately NOT ranked on Download_Count__c (documented lossy counter).
     */
    private static List<ResourceHit> searchResourcesScored(String term) {
        List<ResourceHit> out = new List<ResourceHit>();
        String clean = NexSKnowledgeController.sanitizeSearch(term);
        List<String> qTokens = NexSKnowledgeController.significantTokens(clean);
        if (qTokens.isEmpty()) {
            return out;
        }

        // Synonym expansion: recall + scoring, mirroring the article engine.
        Map<String, Set<String>> synonyms = NexSKnowledgeController.synonymMap();
        Map<String, Set<String>> tokenSynonyms = new Map<String, Set<String>>();
        Set<String> recallTokens = new Set<String>(qTokens);
        for (String qt : qTokens) {
            if (synonyms.containsKey(qt)) {
                tokenSynonyms.put(qt, synonyms.get(qt));
                recallTokens.addAll(synonyms.get(qt));
            }
        }

        // Recall: one SOSL over the resource catalog (active rows only).
        List<String> findParts = new List<String>();
        for (String t : recallTokens) {
            findParts.add(t.length() >= SearchConstants.MIN_PREFIX_LEN ? t + '*' : t);
        }
        String sosl =
            'FIND \'' + String.join(findParts, ' OR ') + '\' IN ALL FIELDS RETURNING Resource__c(' +
            'Id, Name, Slug__c, Resource_Type__c, Description__c, Is_Featured__c, ' +
            'External_URL__c, Category__r.Slug__c, ' +
            'Video_Embed_URL__c, Event_Datetime__c, Registration_URL__c ' +
            'WHERE Is_Active__c = true) LIMIT ' + MAX_RESULTS;
        List<List<SObject>> results = Search.query(sosl);
        List<Resource__c> rows = results.isEmpty()
            ? new List<Resource__c>() : (List<Resource__c>) results[0];

        List<ScoredResource> scored = new List<ScoredResource>();
        for (Resource__c r : rows) {
            Double s = scoreResource(qTokens, tokenSynonyms, r);
            if (s <= 0) {
                continue; // SOSL body-index-only hit with no field match
            }
            if (r.Is_Featured__c == true) {
                s += FEATURED_BOOST;
            }
            scored.add(new ScoredResource(r, s));
        }
        scored.sort();

        // Webinar hits carry their lifecycle so the card CTA can be "Sign up"
        // (Upcoming) or "Watch" (Recorded): one bulk file lookup, webinars only.
        Set<Id> webinarIds = new Set<Id>();
        for (ScoredResource sr : scored) {
            if (WebinarLifecycle.isWebinar(sr.row.Resource_Type__c)) {
                webinarIds.add(sr.row.Id);
            }
        }
        Map<Id, ResourceCenterService.FileInfo> files = webinarIds.isEmpty()
            ? new Map<Id, ResourceCenterService.FileInfo>()
            : ResourceCenterService.fileInfoByResource(webinarIds);
        Datetime now = System.now();

        for (ScoredResource sr : scored) {
            Resource__c r = sr.row;
            ResourceHit hit = new ResourceHit();
            hit.id = r.Id;
            hit.title = r.Name;
            hit.subtitle = r.Description__c;
            hit.slug = r.Slug__c;
            hit.resourceType = r.Resource_Type__c;
            hit.externalUrl = r.External_URL__c;
            hit.categorySlug = (r.Category__r != null) ? r.Category__r.Slug__c : null;
            hit.featured = (r.Is_Featured__c == true);
            hit.score = sr.score;
            hit.webinarStatus = WebinarLifecycle.statusFor(r, files.containsKey(r.Id), now);
            hit.registrationUrl = r.Registration_URL__c;
            out.add(hit);
        }
        return out;
    }

    /**
     * Per-token best-field score, mirroring the article scorer's match tiers:
     * exact word = full weight, prefix (either direction, >= MIN_PREFIX_LEN) =
     * 0.6x, a synonym match at SYN_MULTIPLIER of the same tier (max, not sum).
     */
    private static Double scoreResource(
            List<String> qTokens, Map<String, Set<String>> tokenSynonyms, Resource__c r) {
        List<String> nameWords = tokenize(r.Name);
        List<String> descWords = tokenize(r.Description__c);
        Double total = 0;
        for (String qt : qTokens) {
            Double best = Math.max(
                fieldScore(qt, nameWords, NexSKnowledgeController.W_TITLE),
                fieldScore(qt, descWords, NexSKnowledgeController.W_SUMMARY)
            );
            if (tokenSynonyms.containsKey(qt)) {
                for (String syn : tokenSynonyms.get(qt)) {
                    Double synBest = Math.max(
                        fieldScore(syn, nameWords, NexSKnowledgeController.W_TITLE),
                        fieldScore(syn, descWords, NexSKnowledgeController.W_SUMMARY)
                    );
                    best = Math.max(best, NexSKnowledgeController.SYN_MULTIPLIER * synBest);
                }
            }
            total += best;
        }
        return total;
    }

    private static Double fieldScore(String token, List<String> words, Double weight) {
        Double best = 0;
        for (String w : words) {
            if (w == token) {
                return weight; // exact — no higher tier exists for this field
            }
            if (token.length() >= SearchConstants.MIN_PREFIX_LEN
                && (w.startsWith(token) || token.startsWith(w))) {
                best = Math.max(best, weight * 0.6);
            }
        }
        return best;
    }

    private static List<String> tokenize(String text) {
        if (String.isBlank(text)) {
            return new List<String>();
        }
        List<String> out = new List<String>();
        for (String w : NexSKnowledgeController.sanitizeSearch(text).toLowerCase().split(' ')) {
            if (String.isNotBlank(w)) {
                out.add(w);
            }
        }
        return out;
    }

    /** Highest score first; ties by Featured, then Name A-Z (mirrors Scored). */
    private class ScoredResource implements Comparable {
        Resource__c row;
        Double score;
        ScoredResource(Resource__c row, Double score) {
            this.row = row;
            this.score = score;
        }
        public Integer compareTo(Object o) {
            ScoredResource other = (ScoredResource) o;
            if (score < other.score) { return 1; }
            if (score > other.score) { return -1; }
            Boolean af = (row.Is_Featured__c == true), bf = (other.row.Is_Featured__c == true);
            if (af != bf) { return af ? -1 : 1; }
            String an = (row.Name == null) ? '' : row.Name;
            String bn = (other.row.Name == null) ? '' : other.row.Name;
            return an.compareTo(bn);
        }
    }
}