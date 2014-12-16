# default parameters for class archiver_appliance
#
class archiver_appliance::params {
  $nodes_fqdn                = undef
  $loadbalancer              = undef
  $archappl_tarball_url      = undef
  $archappl_tarball_md5sum   = undef
  $tomcatjdbc_tarball_url    = undef
  $tomcatjdbc_tarball_md5sum = undef
  $short_term_storage        = '/srv/sts'
  $mid_term_storage          = '/srv/mts'
  $long_term_storage         = '/srv/lts'
  $mysql_db                  = 'archappl'
  $mysql_username            = 'archappl'
  $mysql_password            = undef
  $enable_mysql_backups      = true
  $mysql_backup_hour         = '4'
  $mysql_backup_minute       = '0'
  $mysql_backup_dir          = '/var/backups'
  $install_java              = true
  $policies_file             = undef
  $properties_file           = undef
}