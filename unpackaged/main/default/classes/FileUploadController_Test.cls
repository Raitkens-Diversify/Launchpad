@isTest
public class FileUploadController_Test {
    
    @testSetup
    public static void setup(){
        List<ContentVersion> cvs = new List<ContentVersion>();
        cvs.add(new ContentVersion(Title = 'Test picture 1', PathOnClient = 'Pic.jpg',
                                   VersionData = Blob.valueOf('Test Content'), IsMajorVersion = true));
        
        cvs.add(new ContentVersion(Title = 'Test picture 2', PathOnClient = 'Pic2.jpg',
                                   VersionData = Blob.valueOf('Test Content 2'), IsMajorVersion = true));
        insert cvs;
    }
    
    @isTest
    public static void test_updateCVs(){
        List<ContentVersion> cvs = [SELECT Id, Advertising_Type__c FROM ContentVersion];
        List<String> cvIds = new List<String>{cvs[0].Id, cvs[1].Id};
            Test.startTest();
        FileUploadController.updateCVs(cvIds, 'Event', null);
        Test.stopTest();
        List<ContentVersion> cvsAfterUpdate = [SELECT Id, Advertising_Type__c FROM ContentVersion WHERE Advertising_Type__c = 'Event'];
        Assert.areEqual(2, cvsAfterUpdate.size());
    }
    
    @isTest
    public static void test_getCVAdvertisingTypeOpts(){
        Test.startTest();
        List<String> adTypeOpts = FileUploadController.getCVAdvertisingTypeOpts();
        Test.stopTest();
        Assert.isTrue(adTypeOpts.size() > 0);
    }
    
    @isTest
    public static void test_updateCVsNonAdReview(){
        List<ContentVersion> cvs = [SELECT Id, Advertising_Type__c FROM ContentVersion];
        List<String> cvIds = new List<String>{cvs[0].Id, cvs[1].Id};
            Test.startTest();
        FileUploadController.updateCVsNonAdReview(cvIds,  null);
        Test.stopTest();
        List<ContentVersion> cvsAfterUpdate = [SELECT Id, Advertising_Type__c FROM ContentVersion WHERE Advertising_Type__c = 'Event'];
        //Assert.areEqual(2, cvsAfterUpdate.size());
    }
}