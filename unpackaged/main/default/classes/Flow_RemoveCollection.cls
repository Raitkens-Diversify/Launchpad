global class Flow_RemoveCollection {

    @InvocableMethod(label='Flow_RemoveCollection' description='Pass in a Collection of Strings and which to remove and it will pass back the collection without that value.')
    global static List<FlowOutput> removeCollection(List<FlowInput> inputs){
        

        List<String> collection = inputs[0].coll;
        List<String> collectionItems = collection;
        System.debug('collectionItems: ' + collectionItems);
        System.debug('itemToRemove: ' + inputs[0].itemToRemove);
        String item = inputs[0].itemToRemove;
        
        if(collectionItems.contains(inputs[0].itemToRemove)){
            System.debug('collection DOES CONTAIN');
            collectionItems.remove(collectionItems.indexOf(inputs[0].itemToRemove));
        }
        System.debug('collection after removal: ' + collectionItems);
        List <FlowOutput> outputs = new List<FlowOutput>();
        FlowOutput objOutput = new FlowOutput();
        System.debug('collRemoved: ' + objOutput.collRemoved);
        objOutput.collRemoved = collectionItems;
       
      // system.debug(objOutput.iscollectionEmpty);
        System.debug('collRemoved after adding collection: ' + objOutput.collRemoved);
        outputs.add(objOutput);
        System.debug('outputs: ' + outputs);
        return outputs;
    }
    
    global class FlowInput {
        
        @InvocableVariable
        global List<String> coll;
        
        @InvocableVariable
        global String itemToRemove;
    }
    
    global class FlowOutput {
        
        @InvocableVariable
        global List<String> collRemoved;
        
    }
}