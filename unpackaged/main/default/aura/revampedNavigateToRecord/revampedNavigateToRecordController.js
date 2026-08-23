({
    invoke : function(component, event, helper) {
        // Get the record ID attribute
        $A.get('e.force:refreshView').fire();
        var record = component.get("v.recordId");

        if (!record) {
            console.error("Record ID is undefined.");
            return;
        }

        // Delay the navigation slightly to ensure the record is fully committed
        window.setTimeout($A.getCallback(function() {
            // Get the Lightning event that opens a record in a new tab
            var redirect = $A.get("e.force:navigateToSObject");

            // Check if the event is properly initialized
            if (redirect) {
                // Pass the record ID to the event
                redirect.setParams({
                    "recordId": record
                });

                // Open the record
                redirect.fire();
            } else {
                console.error("The navigateToSObject event is not available.");
            }
        }), 500); // 500ms delay
    }
})