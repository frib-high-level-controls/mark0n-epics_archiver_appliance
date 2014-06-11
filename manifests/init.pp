# This class sets up a the EPICS Archiver Appliance on a node. This node can
# be a member of a cluster of machines. The following services will be
# deployed:
# -management interface
# -archive engine
# -retrieval process
# -ETL process
#
class archiver_appliance(
  $nodes_fqdn                = undef,
  $loadbalancer              = undef,
  $archappl_tarball_url      = undef,
  $archappl_tarball_md5sum   = undef,
  $tomcatjdbc_tarball_url    = undef,
  $tomcatjdbc_tarball_md5sum = undef,
  $short_term_storage        = '/srv/sts',
  $mid_term_storage          = '/srv/mts',
  $long_term_storage         = '/srv/lts',
  $install_java              = true,
  $policies_file             = undef,
  $properties_file           = undef,
) {
  validate_string($policies_file)
  validate_string($properties_file)

  $identity = inline_template("appliance<%= @nodes_fqdn.index(@fqdn) %>")
  $real_policies_file = $policies_file ? {
    undef   => '/etc/archappl/policies.py',
    default => $policies_file,
  }
  $real_properties_file = $properties_file ? {
    undef   => '/etc/archappl/archappl.properties',
    default => $properties_file,
  }

  File { owner => root, group => root, mode => '0644' }

  if($install_java) {
    class { 'java':
      distribution => 'jdk',
      before       => [
        Service['archappl-mgmt'],
        Service['archappl-etl'],
        Service['archappl-retrieval'],
        Service['archappl-engine'],
      ],
    }
  }

  if !defined(Package['unzip']) {
    package { 'unzip':
      ensure => installed,
    }
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
    onlyif  => '/usr/bin/test `/usr/bin/mysql --user=archappl --password=archappl --database=archappl --batch --skip-column-names -e \'SHOW TABLES\' | /usr/bin/wc -l` -lt 4',
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
      "ARCHAPPL_MYIDENTITY=${identity}",
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
    ensure  => link,
    target  => '../../java/mysql-connector-java.jar',
    require => [
      Package['libmysql-java'],
      Package['tomcat7'],
    ],
  }

  file { '/usr/share/tomcat7/lib/mysql.jar':
    ensure  => link,
    target  => '../../java/mysql.jar',
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

  if $policies_file == undef {
    exec { $real_policies_file:
      command => "unzip -p /var/lib/tomcat7-archappl/mgmt/webapps/mgmt.war WEB-INF/classes/policies.py > ${real_policies_file}",
      path    => '/usr/local/bin:/usr/bin:/bin',
      creates => $real_policies_file,
      require => [
        Package['unzip'],
        File['/etc/archappl'],
        File['/var/lib/tomcat7-archappl/mgmt/webapps/mgmt.war'],
      ],
    }
  }

  if $properties_file == undef {
    exec { $real_properties_file:
      command => "unzip -p /var/lib/tomcat7-archappl/mgmt/webapps/mgmt.war WEB-INF/classes/archappl.properties > ${real_properties_file}",
      path    => '/usr/local/bin:/usr/bin:/bin',
      creates => $real_properties_file,
      require => [
        Package['unzip'],
        File['/etc/archappl'],
        File['/var/lib/tomcat7-archappl/mgmt/webapps/mgmt.war'],
      ],
    }
  }

  # for some reason the WAR files do not get exploded automatically anymore
  # we work around this issue by unpacking them ourselves
  exec { 'explode WAR file for engine container':
    command => 'unzip -d /var/lib/tomcat7-archappl/engine/webapps/engine /var/lib/tomcat7-archappl/engine/webapps/engine.war',
    path    => '/usr/local/bin:/usr/bin:/bin',
    creates => '/var/lib/tomcat7-archappl/engine/webapps/engine',
    require => File['/var/lib/tomcat7-archappl/engine/webapps/engine.war'],
  }

  exec { 'explode WAR file for etl container':
    command => 'unzip -d /var/lib/tomcat7-archappl/etl/webapps/etl /var/lib/tomcat7-archappl/etl/webapps/etl.war',
    path    => '/usr/local/bin:/usr/bin:/bin',
    creates => '/var/lib/tomcat7-archappl/etl/webapps/etl',
    require => File['/var/lib/tomcat7-archappl/etl/webapps/etl.war'],
  }

  exec { 'explode WAR file for mgmt container':
    command => 'unzip -d /var/lib/tomcat7-archappl/mgmt/webapps/mgmt /var/lib/tomcat7-archappl/mgmt/webapps/mgmt.war',
    path    => '/usr/local/bin:/usr/bin:/bin',
    creates => '/var/lib/tomcat7-archappl/mgmt/webapps/mgmt',
    require => File['/var/lib/tomcat7-archappl/mgmt/webapps/mgmt.war'],
  }

  exec { 'explode WAR file for retrieval container':
    command => 'unzip -d /var/lib/tomcat7-archappl/retrieval/webapps/retrieval /var/lib/tomcat7-archappl/retrieval/webapps/retrieval.war',
    path    => '/usr/local/bin:/usr/bin:/bin',
    creates => '/var/lib/tomcat7-archappl/retrieval/webapps/retrieval',
    require => File['/var/lib/tomcat7-archappl/retrieval/webapps/retrieval.war'],
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
      Package['libmysql-java'],
      File['/usr/share/tomcat7/lib/log4j.properties'],
      Exec['create MySQL tables for archiver appliance'],
      File['/var/lib/tomcat7-archappl/mgmt/webapps/mgmt.war'],
      File['/var/lib/tomcat7-archappl/mgmt/conf/context.xml'],
      Exec['explode WAR file for mgmt container'],
      File[$short_term_storage],
      File[$mid_term_storage],
      File[$long_term_storage],
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
      Package['libmysql-java'],
      File['/usr/share/tomcat7/lib/log4j.properties'],
      Exec['create MySQL tables for archiver appliance'],
      File['/var/lib/tomcat7-archappl/etl/webapps/etl.war'],
      File['/var/lib/tomcat7-archappl/etl/conf/context.xml'],
      Exec['explode WAR file for etl container'],
      File[$short_term_storage],
      File[$mid_term_storage],
      File[$long_term_storage],
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
      Package['libmysql-java'],
      File['/usr/share/tomcat7/lib/log4j.properties'],
      Exec['create MySQL tables for archiver appliance'],
      File['/var/lib/tomcat7-archappl/retrieval/webapps/retrieval.war'],
      File['/var/lib/tomcat7-archappl/retrieval/conf/context.xml'],
      Exec['explode WAR file for retrieval container'],
      File[$short_term_storage],
      File[$mid_term_storage],
      File[$long_term_storage],
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
      Package['libmysql-java'],
      File['/usr/share/tomcat7/lib/log4j.properties'],
      Exec['create MySQL tables for archiver appliance'],
      File['/var/lib/tomcat7-archappl/engine/webapps/engine.war'],
      File['/var/lib/tomcat7-archappl/engine/conf/context.xml'],
      Exec['explode WAR file for engine container'],
      File[$short_term_storage],
      File[$mid_term_storage],
      File[$long_term_storage],
      File['/etc/default/archappl-engine'],
      File['/etc/init.d/archappl-engine'],
    ],
  }
}