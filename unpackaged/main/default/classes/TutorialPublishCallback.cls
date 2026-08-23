/**
 * TutorialPublishCallback
 *
 * Async completion handler for TutorialAdminController.publish(). Writes the
 * deploy outcome back onto the draft records so the Tour Builder UI can poll
 * for it:
 *  - success: Published__c=true + Last_Published__c=now on tour and steps,
 *    Publish_Error__c cleared.
 *  - failure: Publish_Error__c populated; Published__c left untouched (metadata
 *    deploys are atomic, so the published CMDT is unchanged on failure).
 *
 * No sharing declaration on purpose: the callback runs asynchronously in
 * system context and the write-back must not depend on the enqueuing user's
 * record access.
 */
public class TutorialPublishCallback implements Metadata.DeployCallback {

    private Id draftTourId;

    public TutorialPublishCallback(Id draftTourId) {
        this.draftTourId = draftTourId;
    }

    public void handleResult(Metadata.DeployResult result, Metadata.DeployCallbackContext context) {
        List<Tutorial_Tour_Draft__c> tours = [
            SELECT Id, Published__c, Last_Published__c, Publish_Error__c,
                   (SELECT Id FROM Tutorial_Step_Drafts__r)
            FROM Tutorial_Tour_Draft__c
            WHERE Id = :draftTourId
            LIMIT 1
        ];
        if (tours.isEmpty()) {
            // Draft deleted while the deploy was in flight — nothing to write back.
            return;
        }
        Tutorial_Tour_Draft__c tour = tours[0];

        if (result != null && result.status == Metadata.DeployStatus.SUCCEEDED) {
            Datetime now = System.now();
            tour.Published__c = true;
            tour.Last_Published__c = now;
            tour.Publish_Error__c = null;
            update tour;

            List<Tutorial_Step_Draft__c> steps = new List<Tutorial_Step_Draft__c>();
            for (Tutorial_Step_Draft__c step : tour.Tutorial_Step_Drafts__r) {
                steps.add(new Tutorial_Step_Draft__c(
                    Id = step.Id,
                    Published__c = true,
                    Last_Published__c = now
                ));
            }
            if (!steps.isEmpty()) {
                update steps;
            }
        } else {
            tour.Publish_Error__c = describeFailure(result);
            update tour;
        }
    }

    private static String describeFailure(Metadata.DeployResult result) {
        if (result == null) {
            return 'Deployment failed (no result returned).';
        }
        String message = String.valueOf(result.status);
        // details/componentFailures can be null depending on how the deploy died.
        if (result.details != null && result.details.componentFailures != null
            && !result.details.componentFailures.isEmpty()) {
            message += ': ' + result.details.componentFailures[0].problem;
        } else if (result.errorMessage != null) {
            message += ': ' + result.errorMessage;
        }
        return message.abbreviate(255);
    }
}