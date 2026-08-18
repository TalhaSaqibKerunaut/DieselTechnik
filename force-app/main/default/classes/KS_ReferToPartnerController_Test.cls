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

        // Shell email templates
        insert new EmailTemplate(
            Name = 'KS RTP Initial Shell', DeveloperName = 'KS_RTP_Initial_Shell',
            TemplateType = 'html', FolderId = UserInfo.getUserId(),
            HtmlValue = '<html><body>{EmailContent}</body></html>',
            Body = 'Shell', Subject = 'Refer', IsActive = true
        );
        insert new EmailTemplate(
            Name = 'KS RTP Reminder Shell', DeveloperName = 'KS_RTP_Reminder_Shell',
            TemplateType = 'html', FolderId = UserInfo.getUserId(),
            HtmlValue = '<html><body>{EmailContent}</body></html>',
            Body = 'Shell', Subject = 'Reminder', IsActive = true
        );

        // Accounts
        insert new List<Account>{
            new Account(
                Name = 'DE Partner', BillingCountry = 'DE',
                BillingCity = 'Munich',
                KS_ReferToPartner__c = true,
                KS_Email__c = 'de@partner.de'
            ),
            new Account(
                Name = 'FR Partner', BillingCountry = 'FR',
                BillingCity = 'Paris',
                KS_ReferToPartner__c = true,
                KS_Email__c = 'fr@partner.fr'
            )
        };

        // Lead from Germany
        insert new Lead(
            FirstName = 'Klaus', LastName = 'Schmidt',
            Email = 'k.schmidt@test.de',
            Company = 'Test GmbH',
            Country = 'DE',
            KS_Language__c = 'de',
            KS_Client__c = 'DT'
        );
    }

    private static Lead getTestLead() {
        return [SELECT Id, Email, Country, State, HasOptedOutOfEmail,
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
            Country = 'DE', KS_Language__c = 'de', KS_Client__c = 'DT'
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
            Country = 'DE', HasOptedOutOfEmail = true,
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
            SELECT Id, KS_Lead__c, KS_Account__c, KS_Status__c
            FROM KS_BusinessRelation__c
            WHERE KS_Lead__c = :lead.Id
        ];
        System.assertEquals(1, rels.size(), 'One business relation should be created');
        System.assertEquals('Referred', rels[0].KS_Status__c);
        System.assertEquals(acc.Id, rels[0].KS_Account__c);

        // Verify lead was updated
        Lead updated = [
            SELECT KS_Referred_Account_Ids__c, KS_Referred_Date__c
            FROM Lead WHERE Id = :lead.Id
        ];
        System.assertNotEquals(null, updated.KS_Referred_Account_Ids__c);
        System.assertEquals(Date.today(), updated.KS_Referred_Date__c);
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
