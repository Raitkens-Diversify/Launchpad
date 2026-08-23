global class MultiSelectFlowValues {
    @InvocableMethod
    public static List<list<string>> CheckValues(List<string> values) {
        if(!(values.isEmpty())){
            string tempStr = values[0];
            List<String> lstnew = tempStr.split(';');
            list<list<string>> finalLst = new list<list<string>>();
            finalLst.add(lstnew);
            return finalLst;
        }
        else return null;
    }
}