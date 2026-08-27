/**
 * Where to send someone to approve Egnyte.
 *
 * WHY THIS EXISTS. Egnyte_integration_page renders <efs:egnyteload>, a Canvas
 * app. Until the running user has approved that app it renders "Application
 * Approval Required" with an Approve link, and inside ARC that link does nothing.
 * Three things stack up against it, and they were worked through in that order:
 *
 *   1. The embedding iframe was sandboxed without top-level navigation, so the
 *      click was refused outright. Fixed on the iframe; necessary, not enough.
 *   2. The prompt lives two frames down in a CROSS-ORIGIN canvas frame, so
 *      nothing client-side can read it or rewrite its link.
 *   3. The ARC site's CSP allows frame-src for launchpad.egnyte.com and
 *      falconpark.egnyte.com only. The approval page is a Salesforce page on the
 *      org domain, which is not on that list, so the navigation is blocked by the
 *      site's own policy no matter what the sandbox says.
 *
 * (3) is the one that cannot be worked around from inside the site: the same CSP
 * applies to any tab on the ARC origin. The approval therefore has to happen on
 * the ORG domain, where no community CSP applies and the flow behaves exactly as
 * it does in the CRM app -- which is where it works today.
 *
 * That URL cannot be built client-side. A community page knows its own origin and
 * nothing about the org's My Domain, so this returns it.
 *
 * Additive: nothing existing calls this and it calls nothing existing.
 * EgnyteVfEmbedController is deliberately untouched -- it builds SITE-origin URLs
 * for the embed, which is still the right thing for the embed.
 */
public with sharing class ArcEgnyteAccessController {
  private static final String RECORD_VF_PAGE = 'Egnyte_integration_page';

  /**
   * The Egnyte page on the org domain, for opening in a new top-level tab.
   *
   * @param recordId the account whose documents are wanted; blank is allowed and
   *        simply omits the id, which still reaches the approval prompt
   */
  @AuraEnabled(cacheable=true)
  public static String getApprovalUrl(String recordId) {
    // NOT named `url`: a local by that name shadows the platform Url class,
    // because Apex identifiers are case-insensitive.
    String origin = Url.getOrgDomainUrl().toExternalForm().removeEnd('/');

    String pageUrl = origin + '/apex/' + RECORD_VF_PAGE;
    if (String.isNotBlank(recordId)) {
      pageUrl += '?id=' + EncodingUtil.urlEncode(recordId.trim(), 'UTF-8');
    }
    return pageUrl;
  }
}