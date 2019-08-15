class { 'openldap::server': }
openldap::server::database { 'dc=example.com':
    ensure => present,
}
class { 'apereo_cas':
    server_name     => 'https://localhost:8443',
    keystore_source => 'puppet:///modules/apereo_cas/thekeystore',
    ldap_uris       => ['ldap://localhost:389'],
    ldap_start_tls  => false,
}

