/**
 * Coverage for ARCUtil's shared helper methods.
 */
@IsTest
private class ARCUtilTest {
  @IsTest
  static void buildLookupCacheKeyJoinsBothApiNamesWithTheSeparator() {
    String key = ARCUtil.buildLookupCacheKey('Account', 'Case');

    Assert.areEqual(
      'Account' + ARCConstants.LOOKUP_CACHE_KEY_SEPARATOR + 'Case',
      key,
      'The cache key concatenates both object names with the shared separator.'
    );
  }

  @IsTest
  static void formatNoRelatedRecordLinkedMessageBuildsTheFullSentence() {
    String message = ARCUtil.formatNoRelatedRecordLinkedMessage('Service__c', 'Account');

    Assert.areEqual(
      ARCConstants.ERROR_NO_RELATED_RECORD_LINKED +
        'Service__c' +
        ARCConstants.ERROR_RELATED_RECORD_LINKED_MIDDLE +
        'Account' +
        ARCConstants.ERROR_RELATED_RECORD_LINKED_SUFFIX,
      message,
      'The message names the related object first and the primary object second.'
    );
  }

  @IsTest
  static void relatedTableScopeFromValueDefaultsToMineForBlankInput() {
    Assert.areEqual(
      ARCConstants.RelatedTableScope.MINE,
      ARCUtil.relatedTableScopeFromValue(null),
      'A null scope value defaults to Mine.'
    );
    Assert.areEqual(
      ARCConstants.RelatedTableScope.MINE,
      ARCUtil.relatedTableScopeFromValue('   '),
      'A blank/whitespace scope value defaults to Mine.'
    );
  }

  @IsTest
  static void relatedTableScopeFromValueRecognizesTeamCaseInsensitively() {
    Assert.areEqual(
      ARCConstants.RelatedTableScope.TEAM,
      ARCUtil.relatedTableScopeFromValue('team'),
      'A lowercase team value resolves to Team.'
    );
    Assert.areEqual(
      ARCConstants.RelatedTableScope.TEAM,
      ARCUtil.relatedTableScopeFromValue(' TEAM '),
      'Mixed case and surrounding whitespace still resolve to Team.'
    );
  }

  @IsTest
  static void relatedTableScopeFromValueTreatsMineAndUnknownValuesAsMine() {
    Assert.areEqual(
      ARCConstants.RelatedTableScope.MINE,
      ARCUtil.relatedTableScopeFromValue('mine'),
      'An explicit mine value resolves to Mine.'
    );
    Assert.areEqual(
      ARCConstants.RelatedTableScope.MINE,
      ARCUtil.relatedTableScopeFromValue('garbage'),
      'An unrecognized value falls back to Mine rather than throwing.'
    );
  }
}