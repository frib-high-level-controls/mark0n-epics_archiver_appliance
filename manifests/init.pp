# This class sets up a the EPICS Archiver Appliance on a node. This node can
# be a member of a cluster of machines. The following services will be
# deployed:
# -management interface
# -archive engine
# -retrieval process
# -ETL process
#
class archiver_appliance(
  $nodes_fqdn                = $archiver_appliance::params::nodes_fqdn,
  $loadbalancer              = $archiver_appliance::params::loadbalancer,
  $archappl_tarball_url      = $archiver_appliance::params::archappl_tarball_url,
  $archappl_tarball_md5sum   = $archiver_appliance::params::archappl_tarball_md5sum,
  $tomcatjdbc_tarball_url    = $archiver_appliance::params::tomcatjdbc_tarball_url,
  $tomcatjdbc_tarball_md5sum = $archiver_appliance::params::tomcatjdbc_tarball_md5sum,
  $short_term_storage        = $archiver_appliance::params::short_term_storage,
  $mid_term_storage          = $archiver_appliance::params::mid_term_storage,
  $long_term_storage         = $archiver_appliance::params::long_term_storage,
  $mysql_db                  = $archiver_appliance::params::mysql_db,
  $mysql_username            = $archiver_appliance::params::mysql_username,
  $mysql_password            = $archiver_appliance::params::mysql_password,
  $enable_mysql_backups      = $archiver_appliance::params::enable_mysql_backups,
  $mysql_backup_hour         = $archiver_appliance::params::mysql_backup_hour,
  $mysql_backup_minute       = $archiver_appliance::params::mysql_backup_minute,
  $mysql_backup_dir          = $archiver_appliance::params::mysql_backup_dir,
  $install_java              = $archiver_appliance::params::install_java,
  $policies_file             = $archiver_appliance::params::policies_file,
  $policies_file_source      = $archiver_appliance::params::policies_file_source,
  $policies_file_content     = $archiver_appliance::params::policies_file_content,
  $properties_file           = $archiver_appliance::params::properties_file,
  $properties_file_source    = $archiver_appliance::params::properties_file_source,
  $properties_file_content   = $archiver_appliance::params::properties_file_content,
) inherits archiver_appliance::params {
  validate_string($mysql_db)
  validate_string($mysql_username)
  validate_string($mysql_password)
  validate_bool($enable_mysql_backups)
  validate_string($mysql_backup_dir)
  validate_string($policies_file)
  validate_string($policies_file_source)
  validate_string($policies_file_content)
  validate_string($properties_file)
  validate_string($properties_file_source)
  validate_string($properties_file_content)

  $identity = inline_template('appliance<%= @nodes_fqdn.index(@fqdn) %>')
  $mysql_backup_present = $enable_mysql_backups ? {
    false   => 'absent',
    default => 'present',
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

  mysql::db { $mysql_db:
    user     => $mysql_username,
    password => $mysql_password,
    host     => 'localhost',
    charset  => 'utf8',
    collate  => 'utf8_general_ci',
    grant    => ['ALL'],
  }

  exec { 'create MySQL tables for archiver appliance':
    command => "/usr/bin/mysql --user=${mysql_username} --password=${mysql_password} --database=${mysql_db} < /tmp/archappl/install_scripts/archappl_mysql.sql",
    onlyif  => "/usr/bin/test `/usr/bin/mysql --user=${mysql_username} --password=${mysql_password} --database=${mysql_db} --batch --skip-column-names -e \'SHOW TABLES\' | /usr/bin/wc -l` -lt 4",
    require => [
      Mysql::Db[$mysql_db],
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
    content => template('archiver_appliance/context.xml'),
    owner   => tomcat7,
    require => Exec['deploy multiple tomcats'],
  }

  file { '/var/lib/tomcat7-archappl/etl/conf/context.xml':
    ensure  => file,
    content => template('archiver_appliance/context.xml'),
    owner   => tomcat7,
    require => Exec['deploy multiple tomcats'],
  }

  file { '/var/lib/tomcat7-archappl/mgmt/conf/context.xml':
    ensure  => file,
    content => template('archiver_appliance/context.xml'),
    owner   => tomcat7,
    require => Exec['deploy multiple tomcats'],
  }

  file { '/var/lib/tomcat7-archappl/retrieval/conf/context.xml':
    ensure  => file,
    content => template('archiver_appliance/context.xml'),
    owner   => tomcat7,
    require => Exec['deploy multiple tomcats'],
  }

  if $policies_file_source == undef and $policies_file_content == undef {
    exec { $policies_file:
      command => "unzip -p /var/lib/tomcat7-archappl/mgmt/webapps/mgmt.war WEB-INF/classes/policies.py > ${policies_file}",
      path    => '/usr/local/bin:/usr/bin:/bin',
      creates => $policies_file,
      require => [
        Package['unzip'],
        File['/etc/archappl'],
        File['/var/lib/tomcat7-archappl/mgmt/webapps/mgmt.war'],
      ],
      notify  => [
        Service['archappl-engine'],
        Service['archappl-etl'],
        Service['archappl-mgmt'],
        Service['archappl-retrieval'],
      ],
    }
  } else {
    file { $policies_file:
      ensure  => file,
      source  => $policies_file_source,
      content => $policies_file_content,
      owner   => root,
      group   => root,
      mode    => '0644',
      notify  => [
        Service['archappl-engine'],
        Service['archappl-etl'],
        Service['archappl-mgmt'],
        Service['archappl-retrieval'],
      ],
    }
  }

  if $properties_file_source == undef and $properties_file_content == undef {
    exec { $properties_file:
      command => "unzip -p /var/lib/tomcat7-archappl/mgmt/webapps/mgmt.war WEB-INF/classes/archappl.properties > ${properties_file}",
      path    => '/usr/local/bin:/usr/bin:/bin',
      creates => $properties_file,
      require => [
        Package['unzip'],
        File['/etc/archappl'],
        File['/var/lib/tomcat7-archappl/mgmt/webapps/mgmt.war'],
      ],
    }
  } else {
    file { $properties_file:
      ensure  => file,
      source  => $properties_file_source,
      content => $properties_file_content,
      owner   => root,
      group   => root,
      mode    => '0644',
      notify  => [
        Service['archappl-engine'],
        Service['archappl-etl'],
        Service['archappl-mgmt'],
        Service['archappl-retrieval'],
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

  class { 'mysql::client':
  }

  file { '/usr/local/bin/backup_archiver_appliance_db.sh':
    ensure  => $mysql_backup_present,
    content => template('archiver_appliance/usr/local/bin/backup_archiver_appliance_db.sh'),
    owner   => 'root',
    group   => 'root',
    mode    => '0755',
  }

  cron { 'backup-pv-configuration':
    ensure  => $mysql_backup_present,
    command => '/usr/local/bin/backup_archiver_appliance_db.sh',
    user    => root,
    hour    => $mysql_backup_hour,
    minute  => $mysql_backup_minute,
    require => [
      Class['mysql::client'],
      File['/usr/local/bin/backup_archiver_appliance_db.sh'],
    ],
  }
}