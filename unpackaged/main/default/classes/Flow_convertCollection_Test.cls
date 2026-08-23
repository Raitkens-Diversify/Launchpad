@istest
public class Flow_convertCollection_Test {
	@istest
    static void convertCollectiontest(){
        List<String> tempList=new List<String>();
        tempList.add('test string one;test string two');
        List<List<String>> testResults=new List<List<String>>();
        testResults.add(new List<String>{'test string one','test string two'});
       // testResults.add(tempList);
        test.startTest();
        List<List<String>> resultstrings=Flow_convertCollection.convertCollection(tempList);
        test.stopTest();
  			system.assertEquals(testResults, resultstrings);
        system.debug(resultstrings);
    }
    
}