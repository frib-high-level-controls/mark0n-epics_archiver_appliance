class archiver_appliance::node(
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
  $long_term_storage = '/srv/lts'
)
{
  include apt
  class { 'archiver_appliance':
    nodes_fqdn                    => $archiver_nodes,
    loadbalancer                  => $loadbalancer,
    archappl_tarball_url          => $archappl_tarball_url,
    archappl_tarball_md5sum       => $archappl_tarball_md5sum,
    mysqlconnector_tarball_url    => $mysqlconnector_tarball_url,
    mysqlconnector_tarball_md5sum => $mysqlconnector_tarball_md5sum,
    tomcatjdbc_tarball_url        => $tomcatjdbc_tarball_url,
    tomcatjdbc_tarball_md5sum     => $tomcatjdbc_tarball_md5sum,
    short_term_storage            => $short_term_storage,
    mid_term_storage              => $mid_term_storage,
    long_term_storage             => $long_term_storage,
  }

  apt::source { 'nsls2repo':
    location    => 'http://epics.nsls2.bnl.gov/debian/',
    release     => 'wheezy',
    repos       => 'main contrib',
    include_src => false,
    key         => '256355f9',
    key_source  => 'http://epics.nsls2.bnl.gov/debian/repo-key.pub',
  }

  # Packages in controls repo are not signed, yet! Thus we use NSLS-II repo for now.
  #apt::source { 'controlsrepo':
  #  location    => 'http://apt.hcl.nscl.msu.edu/controls/',
  #  release     => 'wheezy',
  #  repos       => 'main',
  #  include_src => false,
  #  key         => '256355f9',
  #  key_source  => 'http://epics.nsls2.bnl.gov/debian/repo-key.pub',
  #}

  package { 'epics-catools':
    ensure  => installed,
    require => Apt::Source['nsls2repo'],
  }

  # Archiver appliance uses its own tomcat containers so we do not need the default one.
  service { 'tomcat7':
    ensure     => stopped,
    enable     => false,
    hasrestart => true,
    hasstatus  => true,
    require    => Package['tomcat7'],
  }
}