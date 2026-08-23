public class FlowActionHandler {

    @InvocableMethod(label='Refresh Record Detail Page' description='This action calls a refresh on the record detail page')
    public static void performTask(List<String> invocableMethodArgument) {
        System.debug('I am here');
        Refresh_Detail__e event = new Refresh_Detail__e();
        EventBus.publish(event);
    }
}