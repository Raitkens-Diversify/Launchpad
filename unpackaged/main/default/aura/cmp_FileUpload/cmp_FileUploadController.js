({
    doInit : function(component, event, helper) {
        if(component.get('v.advertisingType') != null && component.get('v.advertisingType') != '' && component.get('v.advertisingType') != undefined){
            helper.init(component, event, helper);
        } else {
            helper.updateCVsNonAdReview(component, event, helper);
        }
    },
    
	handleUploadFinished : function(component, event, helper) {
		var uploadedFiles = event.getParam("files");
        var cvIds = uploadedFiles.map((file) => file.contentVersionId);
        var cvIdsString = cvIds.toString();
        component.set('v.contentVersionIds', cvIdsString);
        helper.updateCVs(component, event, cvIds);
	}
})