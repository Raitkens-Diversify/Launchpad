//It is used to make list of strings that are selected in checkbox group values in the flow 
public class Flow_convertCollection {
  
    @InvocableMethod(label='convertCollection')
    public static List<List<String>> convertCollection(List<String> values){
        if(!values.isEmpty()){
            String str=values[0];
            List<String> lstnew=str.split(';');
            List<List<String>> finalList=new List<List<String>>();
            finalList.add(lstnew);
            system.debug(finalList);
            return finalList;
        }else
            return null;
    }
}