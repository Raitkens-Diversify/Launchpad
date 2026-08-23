/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-17
 *
 * Builds the inner Egnyte integration iframe URL for EgnyteArcEmbed.page.
 */
public with sharing class EgnyteArcEmbedController {
    private static final String INNER_VF_PAGE = 'Egnyte_integration_page';
    private static final String RECORD_ID_PARAM = 'id';

    public String innerFrameUrl { get; private set; }

    public EgnyteArcEmbedController() {
        innerFrameUrl = buildInnerFrameUrl(
            ApexPages.currentPage().getParameters()
        );
    }

    @TestVisible
    private static String buildInnerFrameUrl(Map<String, String> params) {
        PageReference innerPage = new PageReference('/apex/' + INNER_VF_PAGE);
        Map<String, String> innerParams = innerPage.getParameters();

        if (params != null) {
            String recordId = params.get(RECORD_ID_PARAM);
            if (String.isNotBlank(recordId)) {
                innerParams.put(RECORD_ID_PARAM, recordId.trim());
            }

            String pageHeight = params.get('pageHeight');
            if (String.isNotBlank(pageHeight)) {
                innerParams.put('pageHeight', pageHeight.trim());
            }

            String permission = params.get('permission');
            if (String.isNotBlank(permission)) {
                innerParams.put('permission', permission.trim());
            }
        }

        innerParams.put('isdtp', 'nv');
        return innerPage.getUrl();
    }
}