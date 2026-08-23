({
	init: function (cmp, event, helper) {
        cmp.set('v.mycolumns', [
            { label: 'Created By', fieldName: 'OwnerName__c', type: 'text'},
            {
                label: 'Created Date',
                fieldName: 'CreatedDate',
                type: 'date'
            },
            {
                label: 'Comment',
                fieldName: 'CommentBody__c',
                type: 'text',
                wrapText: true
                
            }
        ]);
        helper.getData(cmp);

            /*cmp.set('v.mydata', [{
                    Id: 'a',
                    CreatedById: 'Rachel Aitkens',
                    Comment__c: 'This is a very long task comment.'
                },
                {
                    Id: 'b',
                    CreatedById: 'Rachel Aitkens',
                    Comment__c: 'This is a very long task comment. This is a very long task comment. This is a very long task comment. This is a very long task comment. This is a very long task comment. This is a very long task comment. This is a very long task comment.'
            }]);*/
    }, 
    handleGotoRelatedList : function (cmp, event, helper) {
        var relatedListEvent = $A.get("e.force:navigateToRelatedList");
        relatedListEvent.setParams({
            "relatedListId": cmp.get("v.parentRelationshipApiName"),
            "parentRecordId": cmp.get("v.recordId")
        });
        relatedListEvent.fire();
    },
    viewAll: function (cmp, event, helper) {
        console.log('Hello from view all');
        if(cmp.get('v.viewMinMax') == 'View All') {
	        cmp.set('v.mydata', cmp.get('v.mydataAll'));
            cmp.set('v.viewMinMax', 'View Less');
        } else {
	        cmp.set('v.mydata', cmp.get('v.mydata5'));
            cmp.set('v.viewMinMax', 'View All');            
        }
    }
})