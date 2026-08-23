@isTest
public class MultiSelectFlowValues_Test{
    @isTest
    static void MultiSelectFlowValuesTest(){
        List<string> tempLst = new list<string>();
        tempLst.add('AccidentalCoder');
        tempLst.add('Salesforce');
        MultiselectFlowvalues.CheckValues(tempLst);
    }
}