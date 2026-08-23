@isTest
public class Advertising_Item_TriggerHandlerTest {
    
    @testSetup
    private static void setup(){
        List<Advertising_Item__c> adItems = new List<Advertising_Item__c>();
        List<Advertising_Item__c> adItemsList = new List<Advertising_Item__c>();
        List<Case> caseList = new List<Case>();
        for(Integer i = 0; i < 2; i++){
            Case c = new Case();
            c.Status = 'New'; 
            caseList.add(c);
        }
        insert caseList;
        
        adItems.add(new Advertising_Item__c(Flow_Interview_ID__c = '0067686768678', Review_Case__c = caseList[0].Id, 
                                            Advertising_Type__c='Social Media Profile'));
        adItems.add(new Advertising_Item__c(Flow_Interview_ID__c = '0067686768678', Review_Case__c = caseList[1].Id,
                                            Advertising_Type__c='Social Media Profile'));        
        insert adItems;
        
        adItemsList.add(new Advertising_Item__c(Advertising_Type__c = 'Social Media Profile', 
                                                Flow_Interview_ID__c = 'abcd', Status__c = 'Under Review', Event__c = adItems[0].Id, Social_Media_Profile__c = adItems[0].Id));
        adItemsList.add(new Advertising_Item__c(Advertising_Type__c = 'Social Media Profile', 
                                                Flow_Interview_ID__c = 'abcd', Social_Media_Profile__c = adItems[1].Id));
        insert adItemsList;
        
        ContentVersion cv  = new ContentVersion(Title = 'Test picture 1', PathOnClient = 'Pic.jpg',
                                                VersionData = Blob.valueOf('Test Content'), IsMajorVersion = true,
                                                Advertising_Type__c = 'Event', Flow_Interview_ID__c = '123456');
        insert cv;
    }
    
    @isTest
    private static void testBeforeInsert(){
        List<Advertising_Item__c> adItemsList = [SELECT Id, Social_Media_Profile__c from Advertising_Item__c];
        Advertising_Item__c adI4 = new Advertising_Item__c();
        adI4.Advertising_Type__c = 'Social Media Content';
        adI4.Flow_Interview_ID__c = 'abcd';
        Test.startTest();
        insert adI4;
        Test.stopTest();
        Assert.areEqual(adItemsList[0].Id, [SELECT Id, Social_Media_Profile__c FROM Advertising_Item__c WHERE Id = :adI4.Id][0].Social_Media_Profile__c);  
        //for coverage
        delete adI4;
        undelete adI4;
    }
    
    @isTest 
    private static void testAfterInsert(){
        List<Advertising_Item__c> adItemList = [SELECT Id, Review_Case__c FROM Advertising_Item__c];
        List<Case> caseList = [SELECT Id FROM Case];
        List<Advertising_Item__c> adIToBeinserted = new List<Advertising_Item__c>();
        Advertising_Item__c adI = new Advertising_Item__c();
        adI.Advertising_Type__c = 'Social Media Content';
        adI.Flow_Interview_ID__c = 'abcd';
        adI.Event__c = adItemList[0].Id;
        adIToBeinserted.add(adI);
        Advertising_Item__c adI1 = new Advertising_Item__c();
        adI1.Advertising_Type__c = 'Social Media Content';
        adI1.Flow_Interview_ID__c = 'abcde';
        adIToBeinserted.add(adI1);
        Test.startTest();
        insert adIToBeinserted;
        Test.stopTest();
        Assert.areEqual(adItemList[0].Review_Case__c, [SELECT Id, Review_Case__c FROM Advertising_Item__c WHERE Id = :adIToBeinserted[0].Id][0].Review_Case__c);
        Assert.areEqual(1, [SELECT count() FROM Case WHERE Id NOT IN :caseList]);
        Assert.areEqual(adIToBeinserted[1].Id, [SELECT Id, Advertising_Item__c FROM Case WHERE Id NOT IN :caseList][0].Advertising_Item__c);   
    }
    
    @isTest
    private static void test_reparentContentDocuments(){
        ContentVersion cv = [SELECT Id, ContentDocument.Title, ContentDocumentId FROM ContentVersion
                             WHERE ContentDocument.Title = 'Test picture 1'];
        Advertising_Item__c adItem  = new Advertising_Item__c(Name = 'Test Ad Item', Advertising_Type__c = 'Event',
                                                              Flow_Interview_ID__c = '123456');
        List<ContentDocumentLink> cdlsBeforeInsert = [SELECT Id, ContentDocumentId, LinkedEntityId, LinkedEntity.Name,
                                                      ShareType, Visibility FROM ContentDocumentLink WHERE ContentDocumentId = :cv.ContentDocumentId 
                                                     ];
        Test.startTest();
        insert adItem;
        Test.stopTest();
        List<ContentDocumentLink> cdlsAfterInsert = [SELECT Id, ContentDocumentId, LinkedEntityId, LinkedEntity.Name,
                                                     ShareType, Visibility FROM ContentDocumentLink WHERE ContentDocumentId = :cv.ContentDocumentId 
                                                    ];
        Assert.isTrue(cdlsBeforeInsert.size() == 1);
        Assert.isTrue(cdlsAfterInsert.size() == 2);
    } 
    
    @isTest
    private static void testSetRecordLock(){
        //If we create a new Advertising Item without Event__c field value, it will throw error due to future method.
        Advertising_Item__c adItem = [SELECT Id, Status__c, Event__c FROM  Advertising_Item__c WHERE Status__c = 'Under Review' LIMIT 1];
        Test.startTest();
        adItem.Status__c = 'Approved';
        update adItem;
        Test.stopTest();
        adItem = [SELECT Id, Status__c, Record_Locked__c FROM Advertising_Item__c WHERE Id = :adItem.Id];
        Assert.areEqual(true, adItem.Record_Locked__c);
    }
}