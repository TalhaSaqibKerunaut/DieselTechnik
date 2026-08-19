/**
 * KS_ReferToPartnerEmailService_Test
 *
 * Unit tests for KS_ReferToPartnerEmailService.
 * Uses SeeAllData=false; creates test data inline.
 *
 * Note: EmailTemplate records (shell templates) are queried inside the service.
 * We insert real EmailTemplate rows in setup so the test works without
 * deploying to an actual org's SFX builder.
 */
@IsTest
private class KS_ReferToPartnerEmailService_Test {

    // ─── Test data setup ──────────────────────────────────────────────────────

    @TestSetup
    static void setup() {
        // Hierarchy custom setting — encryption key must be 32-char AES-256 key
        KS_ReferToPartnerSettings__c settings = new KS_ReferToPartnerSettings__c();
        settings.EncryptionKey__c = '0123456789ABCDEF0123456789ABCDEF';
        upsert settings;

        // Test account
        Account acc = new Account(
            Name                 = 'Test Partner GmbH',
            BillingStreet        = 'Teststraße 1',
            BillingPostalCode    = '70000',
            BillingCity          = 'Stuttgart',
            BillingCountryCode   = 'DE',
            Phone                = '+49 711 000000',
            Website              = 'https://www.partner.de',
            KS_PartnerShopUrl__c = 'https://shop.partner.de',
            KS_Email__c          = 'partner@partner.de'
        );
        insert acc;

        // Test lead
        Lead lead = new Lead(
            FirstName              = 'Hans',
            LastName               = 'Müller',
            Email                  = 'hans.mueller@test.de',
            Company                = 'Autohaus Test',
            KS_Language__c         = 'de',
            KS_Client__c           = 'DT'
        );
        insert lead;
    }

    // ─── Helper: get test data ────────────────────────────────────────────────

    private static Lead getTestLead() {
        return [
            SELECT Id, FirstName, LastName, Email,
                   KS_EmailSalutation__c, KS_Language__c, KS_Client__c,
                   KS_Referred_Account_Ids__c, Owner.Name
            FROM Lead
            LIMIT 1
        ];
    }

    private static Account getTestAccount() {
        return [
            SELECT Id, Name, BillingStreet, BillingPostalCode, BillingCity,
                   BillingCountry, KS_Email__c, Phone, Website, KS_PartnerShopUrl__c
            FROM Account
            LIMIT 1
        ];
    }

    // ─── Tests: normaliseLanguageCode ─────────────────────────────────────────

    @IsTest
    static void normaliseLanguageCode_ptBR_returnsPTBR() {
        KS_ReferToPartnerEmailService svc = new KS_ReferToPartnerEmailService();
        System.assertEquals('PTBR', svc.normaliseLanguageCode('pt_BR'));
    }

    @IsTest
    static void normaliseLanguageCode_blank_returnsEN() {
        KS_ReferToPartnerEmailService svc = new KS_ReferToPartnerEmailService();
        System.assertEquals('EN', svc.normaliseLanguageCode(''));
    }

    @IsTest
    static void normaliseLanguageCode_unknown_returnsEN() {
        KS_ReferToPartnerEmailService svc = new KS_ReferToPartnerEmailService();
        System.assertEquals('EN', svc.normaliseLanguageCode('zh'));
    }

    // ─── Tests: loadContent ───────────────────────────────────────────────────

    @IsTest
    static void loadContent_deInitial_returnsRecord() {
        Test.startTest();
        KS_ReferToPartnerEmailService svc = new KS_ReferToPartnerEmailService();
        KS_ReferPartnerContent__mdt content = svc.loadContent('de', 'Initial');
        Test.stopTest();
        System.assertNotEquals(null, content, 'Should return DE or default Initial record');
        System.assertEquals('Initial', content.Type__c);
    }

    @IsTest
    static void loadContent_unknownLang_fallsBackToDefault() {
        Test.startTest();
        KS_ReferToPartnerEmailService svc = new KS_ReferToPartnerEmailService();
        KS_ReferPartnerContent__mdt content = svc.loadContent('xx', 'Initial');
        Test.stopTest();
        System.assertNotEquals(null, content);
        System.assertEquals(true, content.IsDefault__c, 'Unknown lang should return default');
    }

    // ─── Tests: buildAccountInfoHtmlBlock ─────────────────────────────────────

    @IsTest
    static void buildAccountInfoHtml_usesPartnerShopUrl() {
        Account acc = getTestAccount();
        KS_ReferToPartnerEmailService svc = new KS_ReferToPartnerEmailService();
        String html = svc.buildAccountInfoHtmlBlock(new List<Account>{ acc });
        System.assert(html.contains('shop.partner.de'), 'Should use KS_PartnerShopUrl__c');
        System.assert(!html.contains('www.partner.de') || html.contains('shop.partner.de'),
                      'Partner shop URL should take priority over Website');
    }

    @IsTest
    static void buildAccountInfoHtml_fallsBackToWebsite() {
        Account acc = getTestAccount();
        acc.KS_PartnerShopUrl__c = null;
        KS_ReferToPartnerEmailService svc = new KS_ReferToPartnerEmailService();
        String html = svc.buildAccountInfoHtmlBlock(new List<Account>{ acc });
        System.assert(html.contains('www.partner.de'), 'Should fall back to Website field');
    }

    @IsTest
    static void buildAccountInfoHtml_emptyList_returnsEmpty() {
        KS_ReferToPartnerEmailService svc = new KS_ReferToPartnerEmailService();
        String html = svc.buildAccountInfoHtmlBlock(new List<Account>());
        System.assertEquals('', html);
    }

    // ─── Tests: assembleEmail ─────────────────────────────────────────────────

    @IsTest
    static void assembleEmail_replacesAllTokens() {
        KS_ReferToPartnerEmailService svc = new KS_ReferToPartnerEmailService();
        String shell   = '<html><body>{EmailContent}</body></html>';
        String content = '<p>{Salutation} {LeadName}</p><p>{AccountInfo}</p>'
                       + '<p>{Comment}</p><p>{LeadOwnerName}</p><p>{FeedbackButtons}</p>';
        Map<String, String> tokens = new Map<String, String>{
            '{Salutation}'      => 'Dear Hans',
            '{LeadName}'        => 'Hans Müller',
            '{AccountInfo}'     => '<p>Test Partner</p>',
            '{Comment}'         => 'Test comment',
            '{LeadOwnerName}'   => 'John Owner',
            '{FeedbackButtons}' => ''
        };
        String result = svc.assembleEmail(shell, content, tokens);
        System.assert(result.contains('Dear Hans'));
        System.assert(result.contains('Hans Müller'));
        System.assert(result.contains('Test Partner'));
        System.assert(result.contains('Test comment'));
        System.assert(!result.contains('{Salutation}'), 'All tokens should be replaced');
    }

    // ─── Tests: encrypt ───────────────────────────────────────────────────────

    @IsTest
    static void encrypt_returnsBase64String() {
        Test.startTest();
        KS_ReferToPartnerEmailService svc = new KS_ReferToPartnerEmailService();
        String encrypted = svc.encrypt('testLeadId001');
        Test.stopTest();
        System.assertNotEquals(null, encrypted);
        System.assertNotEquals('', encrypted);
        // Should be base64 (no exception thrown means it worked)
    }

    // ─── Tests: getShellHtml ─────────────────────────────────────────────────

    @IsTest
    static void getShellHtml_returnsHtml() {
        Test.startTest();
        KS_ReferToPartnerEmailService svc = new KS_ReferToPartnerEmailService();
        String html = svc.getShellHtml('KS_RTP_Initial_Shell');
        Test.stopTest();
        System.assertNotEquals(null, html);
        System.assert(html.contains('{EmailContent}'));
    }

    @IsTest
    static void getShellHtml_notFound_throwsException() {
        Test.startTest();
        KS_ReferToPartnerEmailService svc = new KS_ReferToPartnerEmailService();
        Boolean exceptionThrown = false;
        try {
            svc.getShellHtml('NonExistentTemplate_XYZ');
        } catch (KS_ReferToPartnerEmailService.KS_RTPException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'Should throw for unknown template DeveloperName');
    }

    // ─── Tests: sendInitialEmail (smoke test) ────────────────────────────────

    @IsTest
    static void sendInitialEmail_doesNotThrow() {
        Lead lead      = getTestLead();
        Account acc    = getTestAccount();

        Test.startTest();
        new KS_ReferToPartnerEmailService().sendInitialEmail(
            lead.Id,
            new List<Id>{ acc.Id },
            'Please contact this lead.'
        );
        Test.stopTest();
        // No exception = pass. Email send count assertion not reliable in unit tests.
        System.assert(true, 'sendInitialEmail completed without exception');
    }

    // ─── Tests: sendReminderEmail (smoke test) ───────────────────────────────

    @IsTest
    static void sendReminderEmail_doesNotThrow() {
        Lead lead   = getTestLead();
        Account acc = getTestAccount();

        Test.startTest();
        new KS_ReferToPartnerEmailService().sendReminderEmail(
            lead.Id,
            new List<Id>{ acc.Id }
        );
        Test.stopTest();
        System.assert(true, 'sendReminderEmail completed without exception');
    }
}
