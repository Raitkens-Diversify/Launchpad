@istest
public class Flow_RemoveCollection_Test{
    @istest
    static void testremoveCollection(){
        Flow_RemoveCollection.FlowInput flowInput=new Flow_RemoveCollection.FlowInput();
         List<Flow_RemoveCollection.FlowInput> flowInputList=new List<Flow_RemoveCollection.FlowInput>();
        List<Flow_RemoveCollection.FlowOutput> flowOutputList=new List<Flow_RemoveCollection.FlowOutput>();
        
        List<String> inputs=new List<String>();
        inputs.add('One');
         inputs.add('Two');
         inputs.add('Three');
          flowInput.coll=inputs;
        flowInput.itemToRemove='One';
  		flowInputList.add(flowInput);       
        test.startTest();
        flowOutputList=Flow_RemoveCollection.removeCollection(flowInputList);
        test.stopTest();
       // boolean b=flowOutputList[0].collRemoved.contains('One');
        system.assertEquals(flowOutputList[0].collRemoved.contains('One'), false);
        
    }

}