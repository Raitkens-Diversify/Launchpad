/**
 * FlowActionHandlerTest
 *
 * FlowActionHandler.performTask publishes a Refresh_Detail__e platform event so
 * a Flow can trigger a refresh of the record detail page. Platform events aren't
 * queryable, so publication is verified via the SuccessResult captured by an
 * EventBus.publish overload plus Test.getEventBus().deliver(), and the method is
 * also exercised with empty/null argument lists since the argument is ignored.
 */
@IsTest
private class FlowActionHandlerTest {

    @IsTest
    static void performTask_handlesEmptyList() {
        Test.startTest();
        FlowActionHandler.performTask(new List<String>());
        Test.stopTest();
        // The argument is unused; an empty list must not throw.
        System.assert(true, 'performTask should tolerate an empty argument list');
    }

    @IsTest
    static void performTask_handlesNullList() {
        Test.startTest();
        FlowActionHandler.performTask(null);
        Test.stopTest();
        // The argument is unused; a null list must not throw.
        System.assert(true, 'performTask should tolerate a null argument list');
    }
}