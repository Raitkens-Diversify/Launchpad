/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-13
 */
@IsTest
private class NotificationDigestSchedulerTest {
  @IsTest
  static void execute_startsDigestRuleBatchForCadence() {
    Test.startTest();
    new NotificationDigestScheduler(
      NotificationConstants.DIGEST_FREQUENCY_DAILY
    ).execute(null);
    Test.stopTest();

    List<AsyncApexJob> batchJobs = [
      SELECT Status, ApexClass.Name
      FROM AsyncApexJob
      WHERE ApexClass.Name = 'NotificationDigestRuleBatch'
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];

    System.assertEquals(1, batchJobs.size());
    System.assertEquals('NotificationDigestRuleBatch', batchJobs[0].ApexClass.Name);
  }
}