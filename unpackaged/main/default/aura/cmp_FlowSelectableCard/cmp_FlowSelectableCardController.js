({
	doInit : function(component, event, helper) {
        helper.getRecord(component, event, helper);
       console.log(component.get("v.onlyperson"));
    },
    handleCardClick : function (component, event, helper) {
        const recordId = event.currentTarget.dataset.id;
        if(component.get("v.personOrHousehold") == 'Person'){
            helper.assignSelectedPersonCard(component, recordId);
        } else {
            helper.assignSelectedCard(component, recordId);
        }
    }
})