/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-17
 */
@IsTest
private class EgnyteArcEmbedControllerTest {
    @IsTest
    static void buildInnerFrameUrl_includesRecordParams() {
        Map<String, String> params = new Map<String, String>{
            'id' => '001TO000008Zp6JYAS',
            'pageHeight' => '600px',
            'permission' => 'read'
        };

        String url = EgnyteArcEmbedController.buildInnerFrameUrl(params);

        System.assert(url.contains('/apex/Egnyte_integration_page'), url);
        System.assert(url.contains('id=001TO000008Zp6JYAS'), url);
        System.assert(url.contains('pageHeight=600px'), url);
        System.assert(url.contains('permission=read'), url);
        System.assert(url.contains('isdtp=nv'), url);
    }

    @IsTest
    static void controller_setsInnerFrameUrl() {
        PageReference pageRef = Page.EgnyteArcEmbed;
        pageRef.getParameters().put('id', '001TO000008Zp6JYAS');
        Test.setCurrentPage(pageRef);

        EgnyteArcEmbedController controller = new EgnyteArcEmbedController();

        System.assertNotEquals(null, controller.innerFrameUrl);
        System.assert(
            controller.innerFrameUrl.contains('Egnyte_integration_page'),
            controller.innerFrameUrl
        );
    }
}