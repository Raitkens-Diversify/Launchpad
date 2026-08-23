/**
 * HelpGuidePublishCallback
 *
 * Async completion handler for HelpGuideAdminController.publish(). Writes the
 * deploy outcome back to the draft guide so the Help Guide Builder can poll:
 *  - success: Published__c=true + Last_Published__c=now, Publish_Error__c cleared.
 *  - failure: Publish_Error__c populated; Published__c left untouched (metadata
 *    deploys are atomic, so the published CMDT is unchanged on failure).
 *
 * No sharing declaration on purpose: the callback runs asynchronously in system
 * context and the write-back must not depend on the enqueuing user's access.
 */
public class HelpGuidePublishCallback implements Metadata.DeployCallback {

    private Id draftGuideId;

    public HelpGuidePublishCallback(Id draftGuideId) {
        this.draftGuideId = draftGuideId;
    }

    public void handleResult(Metadata.DeployResult result, Metadata.DeployCallbackContext context) {
        List<Help_Guide_Draft__c> guides = [
            SELECT Id, Published__c, Last_Published__c, Publish_Error__c
            FROM Help_Guide_Draft__c
            WHERE Id = :draftGuideId
            LIMIT 1
        ];
        if (guides.isEmpty()) {
            return; // Draft deleted mid-deploy — nothing to write back.
        }
        Help_Guide_Draft__c guide = guides[0];

        if (result != null && result.status == Metadata.DeployStatus.SUCCEEDED) {
            guide.Published__c = true;
            guide.Last_Published__c = System.now();
            guide.Publish_Error__c = null;
        } else {
            guide.Publish_Error__c = describeFailure(result);
        }
        update guide;
    }

    private static String describeFailure(Metadata.DeployResult result) {
        if (result == null) {
            return 'Deployment failed (no result returned).';
        }
        String message = String.valueOf(result.status);
        if (result.details != null && result.details.componentFailures != null
            && !result.details.componentFailures.isEmpty()) {
            message += ': ' + result.details.componentFailures[0].problem;
        } else if (result.errorMessage != null) {
            message += ': ' + result.errorMessage;
        }
        return message.abbreviate(255);
    }
}