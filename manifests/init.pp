class archiver_appliance($nodes_fqdn = undef, $loadbalancer) {
  File { owner => root, group => root, mode => '0644' }

  package { 'openjdk-7-jdk':
    ensure	=> installed,
  }

  package { 'tomcat7':
    ensure	=> installed,
  }

  # work around problems with Java name resolution
  file { '/etc/hosts':
    ensure	=> file,
    source	=> 'puppet:///modules/archiver_appliance/etc/hosts',
    owner	=> root,
    group	=> root,
    mode	=> 644,
  }

  class { '::mysql::server':
    package_name	=> 'mysql-server',
    package_ensure	=> present,
    service_enabled	=> true,
  }

  mysql::db { 'archappl':
    user	=> 'archappl',
    password	=> 'archappl',
    host	=> 'localhost',
    charset	=> 'utf8',
    collate	=> 'utf8_general_ci',
    grant	=> ['ALL'],
  }

  exec { 'create MySQL tables for archiver appliance':
    command	=> '/usr/bin/mysql --user=archappl --password=archappl --database=archappl < /tmp/install_scripts/archappl_mysql.sql',
    onlyif	=> "/usr/bin/test `/usr/bin/mysql --user=archappl --password=archappl --database=archappl --batch --skip-column-names -e 'SHOW TABLES' | /usr/bin/wc -l` -lt 4",
    require	=> Mysql::Db['archappl'],
  }

  package { 'libmysql-java':
    ensure	=> installed,
  }

  file { '/usr/share/tomcat7/lib/log4j.properties':
    ensure	=> file,
    source	=> 'puppet:///modules/archiver_appliance/log4j.properties',
    require	=> Package['tomcat7'],
  }

  file { '/etc/archappl':
    ensure	=> directory,
    owner	=> root,
    group	=> root,
    mode	=> 755,
  }

  file { '/etc/archappl/appliances.xml':
    ensure	=> file,
    content	=> template('archiver_appliance/appliances.xml'),
  }

  file { '/tmp/archappl_v0.0.1_SNAPSHOT_19-December-2013T10-26-34.tar.gz':
    ensure	=> file,
    source	=> 'puppet:///modules/archiver_appliance/archappl_v0.0.1_SNAPSHOT_19-December-2013T10-26-34.tar.gz',
  }

  exec { 'extract archiver appliance archive':
    command	=> '/bin/tar -xzf /tmp/archappl_v0.0.1_SNAPSHOT_19-December-2013T10-26-34.tar.gz',
    cwd		=> '/tmp/',
    creates	=> '/tmp/engine.war',
    subscribe	=> File['/tmp/archappl_v0.0.1_SNAPSHOT_19-December-2013T10-26-34.tar.gz'],
  }

  exec { 'deploy multiple tomcats':
    command	=> '/usr/bin/python /tmp/install_scripts/deployMultipleTomcats.py /var/lib/tomcat7-archappl/',
    environment	=> [
      'TOMCAT_HOME=/var/lib/tomcat7/',
      'ARCHAPPL_MYIDENTITY=appliance0',
      'ARCHAPPL_APPLIANCES=/etc/archappl/appliances.xml',
    ],
    creates	=> '/var/lib/tomcat7-archappl',
    require	=> [
      Package['tomcat7'],
      Exec['extract archiver appliance archive'],
      File['/etc/archappl/appliances.xml'],
    ],
    notify	=> File['/var/lib/tomcat7-archappl'],
  }

  file { '/var/lib/tomcat7-archappl':
    ensure	=> directory,
    recurse	=> true,
    owner	=> tomcat7,
    group	=> tomcat7,
  }

  file { '/usr/share/tomcat7/lib/mysql-connector-java-5.1.27-bin.jar':
    ensure	=> file,
    source	=> 'puppet:///modules/archiver_appliance/mysql-connector-java-5.1.27-bin.jar',
    require	=> Package['tomcat7'],
  }

  file { '/tmp/apache-tomcat-jdbc-1.1.0.1-bin.tar.gz':
    ensure	=> file,
    source	=> 'puppet:///modules/archiver_appliance/apache-tomcat-jdbc-1.1.0.1-bin.tar.gz',
  }

  exec { 'install Tomcat JDBC Connection Pool':
    command	=> '/bin/tar -xzf /tmp/apache-tomcat-jdbc-1.1.0.1-bin.tar.gz -C /usr/share/tomcat7/lib/',
    creates	=> '/usr/share/tomcat7/lib/tomcat-jdbc.jar',
    require	=> Package['tomcat7'],
    subscribe	=> File['/tmp/apache-tomcat-jdbc-1.1.0.1-bin.tar.gz'],
  }

  file { '/var/lib/tomcat7-archappl/engine/webapps/engine.war':
    ensure	=> file,
    source	=> '/tmp/engine.war',
    owner	=> tomcat7,
    require	=> Exec['deploy multiple tomcats'],
  }

  file { '/var/lib/tomcat7-archappl/etl/webapps/etl.war':
    ensure	=> file,
    source	=> '/tmp/etl.war',
    owner	=> tomcat7,
    require	=> Exec['deploy multiple tomcats'],
  }

  file { '/var/lib/tomcat7-archappl/mgmt/webapps/mgmt.war':
    ensure	=> file,
    source	=> '/tmp/mgmt.war',
    owner	=> tomcat7,
    require	=> Exec['deploy multiple tomcats'],
  }

  file { '/var/lib/tomcat7-archappl/retrieval/webapps/retrieval.war':
    ensure	=> file,
    source	=> '/tmp/retrieval.war',
    owner	=> tomcat7,
    require	=> Exec['deploy multiple tomcats'],
  }

  file { '/var/lib/tomcat7-archappl/engine/conf/context.xml':
    ensure	=> file,
    source	=> 'puppet:///modules/archiver_appliance/context.xml',
    owner	=> tomcat7,
    require	=> Exec['deploy multiple tomcats'],
  }

  file { '/var/lib/tomcat7-archappl/etl/conf/context.xml':
    ensure	=> file,
    source	=> 'puppet:///modules/archiver_appliance/context.xml',
    owner	=> tomcat7,
    require	=> Exec['deploy multiple tomcats'],
  }

  file { '/var/lib/tomcat7-archappl/mgmt/conf/context.xml':
    ensure	=> file,
    source	=> 'puppet:///modules/archiver_appliance/context.xml',
    owner	=> tomcat7,
    require	=> Exec['deploy multiple tomcats'],
  }

  file { '/var/lib/tomcat7-archappl/retrieval/conf/context.xml':
    ensure	=> file,
    source	=> 'puppet:///modules/archiver_appliance/context.xml',
    owner	=> tomcat7,
    require	=> Exec['deploy multiple tomcats'],
  }

  file { '/srv/sts':
    ensure	=> directory,
  }

  file { '/srv/mts':
    ensure	=> directory,
  }

  file { '/srv/lts':
    ensure	=> directory,
  }

  file { '/etc/default/archappl-engine':
    ensure	=> file,
    content	=> template('archiver_appliance/default/archappl-engine'),
    notify	=> Service['archappl-engine'],
  }

  file { '/etc/default/archappl-etl':
    ensure	=> file,
    content	=> template('archiver_appliance/default/archappl-etl'),
    notify	=> Service['archappl-etl'],
  }

  file { '/etc/default/archappl-mgmt':
    ensure	=> file,
    content	=> template('archiver_appliance/default/archappl-mgmt'),
    notify	=> Service['archappl-mgmt'],
  }

  file { '/etc/default/archappl-retrieval':
    ensure	=> file,
    content	=> template('archiver_appliance/default/archappl-retrieval'),
    notify	=> Service['archappl-retrieval'],
  }

  file { '/etc/init.d/archappl-engine':
    ensure	=> file,
    source	=> 'puppet:///modules/archiver_appliance/etc/init.d/archappl-engine',
    mode	=> 755,
  }

  file { '/etc/init.d/archappl-etl':
    ensure	=> file,
    source	=> 'puppet:///modules/archiver_appliance/etc/init.d/archappl-etl',
    mode	=> 755,
  }

  file { '/etc/init.d/archappl-mgmt':
    ensure	=> file,
    source	=> 'puppet:///modules/archiver_appliance/etc/init.d/archappl-mgmt',
    mode	=> 755,
  }

  file { '/etc/init.d/archappl-retrieval':
    ensure	=> file,
    source	=> 'puppet:///modules/archiver_appliance/etc/init.d/archappl-retrieval',
    mode	=> 755,
  }

  service { 'archappl-mgmt':
    ensure	=> running,
    enable	=> true,
    hasrestart	=> true,
    hasstatus	=> true,
    require	=> [
      File['/usr/share/tomcat7/lib/mysql-connector-java-5.1.27-bin.jar'],
      Exec['install Tomcat JDBC Connection Pool'],
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
    ensure	=> running,
    enable	=> true,
    hasrestart	=> true,
    hasstatus	=> true,
    require	=> [
      File['/usr/share/tomcat7/lib/mysql-connector-java-5.1.27-bin.jar'],
      Exec['install Tomcat JDBC Connection Pool'],
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
    ensure	=> running,
    enable	=> true,
    hasrestart	=> true,
    hasstatus	=> true,
    require	=> [
      File['/usr/share/tomcat7/lib/mysql-connector-java-5.1.27-bin.jar'],
      Exec['install Tomcat JDBC Connection Pool'],
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
    ensure	=> running,
    enable	=> true,
    hasrestart	=> true,
    hasstatus	=> true,
    require	=> [
      File['/usr/share/tomcat7/lib/mysql-connector-java-5.1.27-bin.jar'],
      Exec['install Tomcat JDBC Connection Pool'],
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