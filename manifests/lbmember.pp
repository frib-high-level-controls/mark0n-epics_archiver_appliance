# Add a node to the Apache load balancer.
#
define archiver_appliance::lbmember {
  apache::balancermember { "archivercluster-${name}":
    balancer_cluster => 'archivercluster',
    url              => "http://${name}:17668"
  }
}