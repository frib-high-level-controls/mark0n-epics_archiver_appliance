# This class configures a load balancer for the EPICS Archiver Appliance. It
# distributes load equally to multiple archiver nodes.
#
class archiver_appliance::loadbalancer(
  $nodes_fqdn = undef
)
{
  include apt
  include apache

  apache::vhost { 'loadbalancer.example.com':
    docroot    => '/var/www',
    proxy_pass => [
      {
        'path' => '/',
        'url'  => 'balancer://archivercluster/'
      },
    ],
  }

  lbmember { $nodes_fqdn: }

  apache::balancer { 'archivercluster':
    collect_exported => false,
  }
}