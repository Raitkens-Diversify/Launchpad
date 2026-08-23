/**
 * NexSWelcomeController
 *
 * Backs the first-login "Welcome to NexS" video flow. Reads and sets the
 * Has_Seen_Welcome__c flag on the *running* user only — never another user.
 */
public with sharing class NexSWelcomeController {

    /**
     * @return true if the running user has already seen the welcome video.
     */
    @AuraEnabled(cacheable=true)
    public static Boolean getWelcomeState() {
        if (!Schema.sObjectType.User.fields.Has_Seen_Welcome__c.isAccessible()) {
            throw new AuraHandledException('You do not have access to the welcome flag.');
        }
        User u = [
            SELECT Has_Seen_Welcome__c
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];
        return u.Has_Seen_Welcome__c == true;
    }

    /**
     * Mark the welcome video as seen for the running user. Called when the
     * video component mounts, so the flag flips on first view.
     */
    @AuraEnabled
    public static void markWelcomeSeen() {
        if (!Schema.sObjectType.User.fields.Has_Seen_Welcome__c.isUpdateable()) {
            throw new AuraHandledException('You do not have permission to update the welcome flag.');
        }
        try {
            update new User(
                Id = UserInfo.getUserId(),
                Has_Seen_Welcome__c = true
            );
        } catch (Exception e) {
            throw new AuraHandledException('Could not save welcome state: ' + e.getMessage());
        }
    }
}