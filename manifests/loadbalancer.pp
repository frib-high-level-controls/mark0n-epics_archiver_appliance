class archiver_appliance::loadbalancer(
  $nodes_fqdn = undef
)
{
  include apt
  include apache

  apache::vhost { 'loadbalancer.example.com':
    docroot	=> '/var/www',
    proxy_pass	=> [
      { 'path' => '/', 'url' => 'balancer://archivercluster/' },
    ],
  }

  define lbmember {
    apache::balancermember { "archivercluster-$name":
      balancer_cluster => 'archivercluster',
      url              => "http://$name:17668"
    }
  }

  lbmember { $nodes_fqdn: }

  apache::balancer { 'archivercluster':
    collect_exported	=> false,
  }
}