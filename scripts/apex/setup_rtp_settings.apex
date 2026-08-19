// Sets the RTP V2 encryption key for the current org.
// Run once per org after deployment: sf apex run --file scripts/apex/setup_rtp_settings.apex --target-org <alias>
// IMPORTANT: use a different key in production — never reuse the dev key.
KS_ReferToPartnerSettings__c settings = KS_ReferToPartnerSettings__c.getOrgDefaults();
settings.EncryptionKey__c = '0123456789ABCDEF0123456789ABCDEF'; // 32-char AES-256 key (dev only)
upsert settings;
System.debug('RTP settings saved. EncryptionKey length: ' + settings.EncryptionKey__c.length());
