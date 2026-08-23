public with sharing class ConvertCSVToStringCollection {

    @invocableMethod(label='Convert Comma-separated-values to String Collection'
                     description='Converts a Comma-separated-values string (eg, from a field) to a String Collection' 
                     category= 'Utilities')
    public static List<Response> execute (List<Request> requests) {

        List<Response> responseList = new List<Response>();
        for (Request curRequest : requests) {
            if(curRequest.delimiter == null) {
                curRequest.delimiter = ',';
            }

            Response response = new Response();
            response.stringCollection = new List<String>();
            List<String> stringList = curRequest.csvString?.split(curRequest.delimiter);
            System.debug(stringList);
            for(String s : stringList){
                if(!response.stringCollection.contains(s)){
                    response.stringCollection.add(s);
                }
            }
            responseList.add(response);
        }

        return responseList;
    }

    public class Request {
        @invocableVariable(label='Input String' description='Input' required=true)
        public String csvString;
        
        @invocableVariable(label='Delimiter' description='Delimiter string; defaults to comma (,)' required=false)
        public String delimiter;
        
    }

    public class Response {
        @invocableVariable(label='String Collection' description='Collection variable to store output')
        public List<String> stringCollection;

    }
}