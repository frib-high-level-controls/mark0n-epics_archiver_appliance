class archiver_appliance(
  $nodes_fqdn = undef,
  $loadbalancer,
  $archappl_tarball_url,
  $archappl_tarball_md5sum,
  $mysqlconnector_tarball_url,
  $mysqlconnector_tarball_md5sum,
  $tomcatjdbc_tarball_url,
  $tomcatjdbc_tarball_md5sum,
  $short_term_storage = '/srv/sts',
  $mid_term_storage = '/srv/mts',
  $long_term_storage = '/srv/lts',
) {
  include apt

  File { owner => root, group => root, mode => '0644' }

  package { 'openjdk-7-jdk':
    ensure => installed,
  }

  package { 'tomcat7':
    ensure => installed,
  }

  # Archiver appliance uses its own tomcat containers so we do not need the
  # default one.
  service { 'tomcat7':
    ensure     => stopped,
    enable     => false,
    hasrestart => true,
    hasstatus  => true,
    require    => Package['tomcat7'],
  }

  class { '::mysql::server':
    package_name    => 'mysql-server',
    package_ensure  => present,
    service_enabled => true,
  }

  mysql::db { 'archappl':
    user     => 'archappl',
    password => 'archappl',
    host     => 'localhost',
    charset  => 'utf8',
    collate  => 'utf8_general_ci',
    grant    => ['ALL'],
  }

  exec { 'create MySQL tables for archiver appliance':
    command => '/usr/bin/mysql --user=archappl --password=archappl --database=archappl < /tmp/archappl/install_scripts/archappl_mysql.sql',
    onlyif  => "/usr/bin/test `/usr/bin/mysql --user=archappl --password=archappl --database=archappl --batch --skip-column-names -e 'SHOW TABLES' | /usr/bin/wc -l` -lt 4",
    require => [
      Mysql::Db['archappl'],
      Archive['archappl']
    ]
  }

  package { 'libmysql-java':
    ensure => installed,
  }

  file { '/usr/share/tomcat7/lib/log4j.properties':
    ensure  => file,
    source  => 'puppet:///modules/archiver_appliance/log4j.properties',
    require => Package['tomcat7'],
  }

  file { '/etc/archappl':
    ensure => directory,
    owner  => root,
    group  => root,
    mode   => '0755',
  }

  file { '/etc/archappl/appliances.xml':
    ensure  => file,
    content => template('archiver_appliance/appliances.xml'),
  }

  archive { 'archappl':
    ensure        => present,
    url           => $archappl_tarball_url,
    src_target    => '/tmp',
    target        => '/tmp/archappl',
    extension     => 'tar.gz',
    checksum      => true,
    digest_string => $archappl_tarball_md5sum,
    timeout       => 600,
  }

  exec { 'deploy multiple tomcats':
    command     => '/usr/bin/python /tmp/archappl/install_scripts/deployMultipleTomcats.py /var/lib/tomcat7-archappl/',
    environment => [
      'TOMCAT_HOME=/var/lib/tomcat7/',
      'ARCHAPPL_MYIDENTITY=appliance0',
      'ARCHAPPL_APPLIANCES=/etc/archappl/appliances.xml',
    ],
    creates     => '/var/lib/tomcat7-archappl',
    require     => [
      Package['tomcat7'],
      Archive['archappl'],
      File['/etc/archappl/appliances.xml'],
    ],
    notify      => File['/var/lib/tomcat7-archappl'],
  }

  file { '/var/lib/tomcat7-archappl':
    ensure  => directory,
    recurse => true,
    owner   => tomcat7,
    group   => tomcat7,
  }

  file { '/usr/share/tomcat7/lib/mysql-connector-java.jar':
    ensure => link,
    target => '../../java/mysql-connector-java.jar',
    require => [
      Package['libmysql-java'],
      Package['tomcat7'],
    ],
  }

  file { '/usr/share/tomcat7/lib/mysql.jar':
    ensure => link,
    target => '../../java/mysql.jar',
    require => [
      Package['libmysql-java'],
      Package['tomcat7'],
    ],
  }

  archive { 'apache-tomcat-jdbc':
    ensure        => present,
    url           => $tomcatjdbc_tarball_url,
    src_target    => '/tmp',
    target        => '/usr/share/tomcat7/lib',
    extension     => 'tar.gz',
    checksum      => true,
    digest_string => $tomcatjdbc_tarball_md5sum,
    timeout       => 600,
  }

  file { '/var/lib/tomcat7-archappl/engine/webapps/engine.war':
    ensure  => file,
    source  => '/tmp/archappl/engine.war',
    owner   => tomcat7,
    require => Exec['deploy multiple tomcats'],
  }

  file { '/var/lib/tomcat7-archappl/etl/webapps/etl.war':
    ensure  => file,
    source  => '/tmp/archappl/etl.war',
    owner   => tomcat7,
    require => Exec['deploy multiple tomcats'],
  }

  file { '/var/lib/tomcat7-archappl/mgmt/webapps/mgmt.war':
    ensure  => file,
    source  => '/tmp/archappl/mgmt.war',
    owner   => tomcat7,
    require => Exec['deploy multiple tomcats'],
  }

  file { '/var/lib/tomcat7-archappl/retrieval/webapps/retrieval.war':
    ensure  => file,
    source  => '/tmp/archappl/retrieval.war',
    owner   => tomcat7,
    require => Exec['deploy multiple tomcats'],
  }

  file { '/var/lib/tomcat7-archappl/engine/conf/context.xml':
    ensure  => file,
    source  => 'puppet:///modules/archiver_appliance/context.xml',
    owner   => tomcat7,
    require => Exec['deploy multiple tomcats'],
  }

  file { '/var/lib/tomcat7-archappl/etl/conf/context.xml':
    ensure  => file,
    source  => 'puppet:///modules/archiver_appliance/context.xml',
    owner   => tomcat7,
    require => Exec['deploy multiple tomcats'],
  }

  file { '/var/lib/tomcat7-archappl/mgmt/conf/context.xml':
    ensure  => file,
    source  => 'puppet:///modules/archiver_appliance/context.xml',
    owner   => tomcat7,
    require => Exec['deploy multiple tomcats'],
  }

  file { '/var/lib/tomcat7-archappl/retrieval/conf/context.xml':
    ensure  => file,
    source  => 'puppet:///modules/archiver_appliance/context.xml',
    owner   => tomcat7,
    require => Exec['deploy multiple tomcats'],
  }

  if !defined(File[$short_term_storage]) {
    file { $short_term_storage:
      ensure  => directory,
      owner   => 'tomcat7',
      require => Package['tomcat7'],
    }
  }

  if !defined(File[$mid_term_storage]) {
    file { $mid_term_storage:
      ensure  => directory,
      owner   => 'tomcat7',
      require => Package['tomcat7'],
    }
  }

  if !defined(File[$long_term_storage]) {
    file { $long_term_storage:
      ensure  => directory,
      owner   => 'tomcat7',
      require => Package['tomcat7'],
    }
  }

  file { '/etc/default/archappl-engine':
    ensure  => file,
    content => template('archiver_appliance/etc/default/archappl-engine'),
    notify  => Service['archappl-engine'],
  }

  file { '/etc/default/archappl-etl':
    ensure  => file,
    content => template('archiver_appliance/etc/default/archappl-etl'),
    notify  => Service['archappl-etl'],
  }

  file { '/etc/default/archappl-mgmt':
    ensure  => file,
    content => template('archiver_appliance/etc/default/archappl-mgmt'),
    notify  => Service['archappl-mgmt'],
  }

  file { '/etc/default/archappl-retrieval':
    ensure  => file,
    content => template('archiver_appliance/etc/default/archappl-retrieval'),
    notify  => Service['archappl-retrieval'],
  }

  file { '/etc/init.d/archappl-engine':
    ensure => file,
    source => 'puppet:///modules/archiver_appliance/etc/init.d/archappl-engine',
    mode   => '0755',
  }

  file { '/etc/init.d/archappl-etl':
    ensure => file,
    source => 'puppet:///modules/archiver_appliance/etc/init.d/archappl-etl',
    mode   => '0755',
  }

  file { '/etc/init.d/archappl-mgmt':
    ensure => file,
    source => 'puppet:///modules/archiver_appliance/etc/init.d/archappl-mgmt',
    mode   => '0755',
  }

  file { '/etc/init.d/archappl-retrieval':
    ensure => file,
    source => 'puppet:///modules/archiver_appliance/etc/init.d/archappl-retrieval',
    mode   => '0755',
  }

  service { 'archappl-mgmt':
    ensure     => running,
    enable     => true,
    hasrestart => true,
    hasstatus  => true,
    require    => [
      File['/usr/share/tomcat7/lib/mysql-connector-java.jar'],
      File['/usr/share/tomcat7/lib/mysql.jar'],
      Archive['apache-tomcat-jdbc'],
      Package['openjdk-7-jdk'],
      Package['libmysql-java'],
      File['/usr/share/tomcat7/lib/log4j.properties'],
      Exec['create MySQL tables for archiver appliance'],
      File['/var/lib/tomcat7-archappl/mgmt/webapps/mgmt.war'],
      File['/var/lib/tomcat7-archappl/mgmt/conf/context.xml'],
      File['/srv/sts'],
      File['/srv/mts'],
      File['/srv/lts'],
      File['/etc/default/archappl-mgmt'],
      File['/etc/init.d/archappl-mgmt'],
    ],
  }

  service { 'archappl-etl':
    ensure     => running,
    enable     => true,
    hasrestart => true,
    hasstatus  => true,
    require    => [
      File['/usr/share/tomcat7/lib/mysql-connector-java.jar'],
      File['/usr/share/tomcat7/lib/mysql.jar'],
      Archive['apache-tomcat-jdbc'],
      Package['openjdk-7-jdk'],
      Package['libmysql-java'],
      File['/usr/share/tomcat7/lib/log4j.properties'],
      Exec['create MySQL tables for archiver appliance'],
      File['/var/lib/tomcat7-archappl/etl/webapps/etl.war'],
      File['/var/lib/tomcat7-archappl/etl/conf/context.xml'],
      File['/srv/sts'],
      File['/srv/mts'],
      File['/srv/lts'],
      File['/etc/default/archappl-etl'],
      File['/etc/init.d/archappl-etl'],
    ],
  }

  service { 'archappl-retrieval':
    ensure     => running,
    enable     => true,
    hasrestart => true,
    hasstatus  => true,
    require    => [
      File['/usr/share/tomcat7/lib/mysql-connector-java.jar'],
      File['/usr/share/tomcat7/lib/mysql.jar'],
      Archive['apache-tomcat-jdbc'],
      Package['openjdk-7-jdk'],
      Package['libmysql-java'],
      File['/usr/share/tomcat7/lib/log4j.properties'],
      Exec['create MySQL tables for archiver appliance'],
      File['/var/lib/tomcat7-archappl/retrieval/webapps/retrieval.war'],
      File['/var/lib/tomcat7-archappl/retrieval/conf/context.xml'],
      File['/srv/sts'],
      File['/srv/mts'],
      File['/srv/lts'],
      File['/etc/default/archappl-retrieval'],
      File['/etc/init.d/archappl-retrieval'],
    ],
  }

  service { 'archappl-engine':
    ensure     => running,
    enable     => true,
    hasrestart => true,
    hasstatus  => true,
    require    => [
      File['/usr/share/tomcat7/lib/mysql-connector-java.jar'],
      File['/usr/share/tomcat7/lib/mysql.jar'],
      Archive['apache-tomcat-jdbc'],
      Package['openjdk-7-jdk'],
      Package['libmysql-java'],
      File['/usr/share/tomcat7/lib/log4j.properties'],
      Exec['create MySQL tables for archiver appliance'],
      File['/var/lib/tomcat7-archappl/engine/webapps/engine.war'],
      File['/var/lib/tomcat7-archappl/engine/conf/context.xml'],
      File['/srv/sts'],
      File['/srv/mts'],
      File['/srv/lts'],
      File['/etc/default/archappl-engine'],
      File['/etc/init.d/archappl-engine'],
    ],
  }
}