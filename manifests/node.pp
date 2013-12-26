class archiver_appliance::node(
  $nodes_fqdn = undef
)
{
  include apt
  class { 'archiver_appliance':
    nodes_fqdn	=> $archiver_nodes,
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
    ensure	=> installed,
    require	=> Apt::Source['nsls2repo'],
  }

  # Archiver appliance uses its own tomcat containers so we do not need the default one.
  service { 'tomcat7':
    ensure	=> stopped,
    enable	=> false,
    hasrestart	=> true,
    hasstatus	=> true,
    require	=> Package['tomcat7'],
  }
}