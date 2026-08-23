@isTest
public class Flow_EditCollection_Test {
    
    @isTest
    public static void editCollectionTest(){
        Flow_EditCollection.FlowInput FlowInput = new Flow_EditCollection.FlowInput();
        List<string> coll = new List<string>();
        String str = 'test1;test2;test3';
        coll.add(str);
        FlowInput.coll = coll;
        
        FlowInput.itemToRemove = 'test2';
        List<Flow_EditCollection.FlowInput> input = new List<Flow_EditCollection.FlowInput>();
		input.add(FlowInput);
        
        List<string> coll1 = new List<string>{'test1','test3'};
        
        Test.startTest();
        List<Flow_EditCollection.FlowOutput> FlowInputRemoved= Flow_EditCollection.editCollection(input);
        Test.StopTest();
        
        system.assertEquals(coll1, FlowInputRemoved[0].collRemoved);
    }
}