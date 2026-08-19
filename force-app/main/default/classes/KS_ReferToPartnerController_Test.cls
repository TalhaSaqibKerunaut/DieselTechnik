/**
 * KS_ReferToPartnerController_Test
 *
 * Unit tests for KS_ReferToPartnerController.
 */
@IsTest
private class KS_ReferToPartnerController_Test {

    @TestSetup
    static void setup() {
        // Encryption key (required by email service invoked in submitReferral)
        KS_ReferToPartnerSettings__c settings = new KS_ReferToPartnerSettings__c();
        settings.EncryptionKey__c = '0123456789ABCDEF0123456789ABCDEF';
        upsert settings;

        // Accounts
        insert new List<Account>{
            new Account(
                Name = 'DE Partner', BillingCountryCode = 'DE',
                BillingCity = 'Munich',
                KS_QualifiedRefertoPartner__c = true,
                KS_Email__c = 'de@partner.de'
            ),
            new Account(
                Name = 'FR Partner', BillingCountryCode = 'FR',
                BillingCity = 'Paris',
                KS_QualifiedRefertoPartner__c = true,
                KS_Email__c = 'fr@partner.fr'
            )
        };

        // Lead from Germany
        insert new Lead(
            FirstName = 'Klaus', LastName = 'Schmidt',
            Email = 'k.schmidt@test.de',
            Company = 'Test GmbH',
            CountryCode = 'DE',
            KS_Language__c = 'de',
            KS_Client__c = 'DT'
        );
    }

    private static Lead getTestLead() {
        return [SELECT Id, Email, CountryCode, StateCode, HasOptedOutOfEmail,
                       KS_Referred_Account_Ids__c, KS_Language__c, KS_Client__c
                FROM Lead LIMIT 1];
    }

    private static Account getDEAccount() {
        return [SELECT Id FROM Account WHERE Name = 'DE Partner' LIMIT 1];
    }

    // ─── getQualifiedAccounts ─────────────────────────────────────────────────

    @IsTest
    static void getQualifiedAccounts_returnsPreferredAccounts() {
        Lead lead = getTestLead();
        Test.startTest();
        KS_ReferToPartnerController.AccountQueryResult result =
            KS_ReferToPartnerController.getQualifiedAccounts(lead.Id);
        Test.stopTest();
        System.assertNotEquals(null, result);
        System.assertNotEquals(null, result.preferredAccounts);
    }

    @IsTest
    static void getQualifiedAccounts_noEmail_throwsAuraHandledException() {
        Lead noEmailLead = new Lead(
            FirstName = 'No', LastName = 'Email',
            Company = 'Test', Email = null,
            CountryCode = 'DE', KS_Language__c = 'de', KS_Client__c = 'DT'
        );
        insert noEmailLead;

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            KS_ReferToPartnerController.getQualifiedAccounts(noEmailLead.Id);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'Should throw AuraHandledException for lead with no email');
    }

    @IsTest
    static void getQualifiedAccounts_optedOut_throwsAuraHandledException() {
        Lead optedOutLead = new Lead(
            FirstName = 'Opted', LastName = 'Out',
            Company = 'Test', Email = 'opted@test.de',
            CountryCode = 'DE', HasOptedOutOfEmail = true,
            KS_Language__c = 'de', KS_Client__c = 'DT'
        );
        insert optedOutLead;

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            KS_ReferToPartnerController.getQualifiedAccounts(optedOutLead.Id);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'Should throw AuraHandledException for opted-out lead');
    }

    // ─── submitReferral ───────────────────────────────────────────────────────

    @IsTest
    static void submitReferral_createsRelationAndUpdatesLead() {
        Lead lead    = getTestLead();
        Account acc  = getDEAccount();

        Test.startTest();
        KS_ReferToPartnerController.submitReferral(lead.Id, new List<Id>{ acc.Id }, 'Test comment');
        Test.stopTest();

        // Verify business relation was created
        List<KS_BusinessRelation__c> rels = [
            SELECT Id, KS_Lead__c, KS_TargetAccount__c, KS_RelationshipType__c
            FROM KS_BusinessRelation__c
            WHERE KS_Lead__c = :lead.Id
        ];
        System.assertEquals(1, rels.size(), 'One business relation should be created');
        System.assertEquals('is Customer from', rels[0].KS_RelationshipType__c);
        System.assertEquals(acc.Id, rels[0].KS_TargetAccount__c);

        // Verify lead was updated
        Lead updated = [
            SELECT KS_Referred_Account_Ids__c, KS_Referred_Date__c,
                   KS_Comments__c, KS_is_Feedback_Submitted__c, KS_Refer_To_Partner_Feedback__c
            FROM Lead WHERE Id = :lead.Id
        ];
        System.assertNotEquals(null, updated.KS_Referred_Account_Ids__c);
        System.assertEquals(Date.today(), updated.KS_Referred_Date__c);
        System.assertEquals('Test comment', updated.KS_Comments__c, 'Comments should be written to lead');
        System.assertEquals(false, updated.KS_is_Feedback_Submitted__c, 'Feedback submitted flag should be reset');
        System.assertEquals(null, updated.KS_Refer_To_Partner_Feedback__c, 'Previous feedback should be cleared');
    }

    @IsTest
    static void submitReferral_emptyAccountIds_throwsException() {
        Lead lead = getTestLead();
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            KS_ReferToPartnerController.submitReferral(lead.Id, new List<Id>(), null);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'Should throw when no accounts selected');
    }
}
