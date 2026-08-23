({
    init : function (component) {
        var flow = component.find("flowData");
        var record = component.get("v.recordId");
        debugger;
        console.log(record);
        var inputVariables = [
            {
                name : 'recordId',
                type : 'String',
                value : record
            }
        ];
        flow.startFlow("Opportunity_New_Button_Override", inputVariables);
    }
})