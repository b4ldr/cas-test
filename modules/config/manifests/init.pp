class config {
    ensure_packages(['ldap-utils'])
    file {'/var/cache/debconf/slapd.preseed':
        ensure  => file,
        content => "slapd slapd/domain\tstring\texample.org\n"
    }
    package {'slapd':
        ensure       => present,
        responsefile => '/var/cache/debconf/slapd.preseed'
    }
    file {'/etc/ldap':
        ensure => directory,
    }
    file {'/etc/ldap/slapd.d':
        ensure  => directory,
        source  => 'puppet:///modules/config/slapd.d',
        purge   => true,
        recurse => true,
        notify  => Service['slapd'],
    }
    service {'slapd':
        ensure => running,
    }
    exec{'create test user':
        command => '/usr/bin/ldapadd -x -D "cn=admin,dc=example,dc=org" -w changeme -f /etc/ldap/slapd.d/user.ldif',
        require => [
            File['/etc/ldap/slapd.d'],
            Package['slapd'],
        ]
    }
}
