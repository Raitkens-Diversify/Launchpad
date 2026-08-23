({
    init : function (component) {
        var flow = component.find("flowData");
        //YOUR FLOW API NAME SHOULD REPLACE Flow_Name BELOW 
        flow.startFlow("Advertising_Review");
    },
})