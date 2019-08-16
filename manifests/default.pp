class { 'config': }
class { 'apereo_cas':
    server_name         => 'https://localhost:8443',
    keystore_source     => 'puppet:///modules/apereo_cas/thekeystore',
    ldap_uris           => ['ldap://localhost:389'],
    ldap_start_tls      => false,
    ldap_bind_dn        => 'cn=admin,dc=example,dc=org',
    ldap_attribute_list => ['preferredLanguage'],
    log_level           => 'DEBUG',
}
