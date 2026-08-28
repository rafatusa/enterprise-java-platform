# The unprivileged service account the application runs as.
class app_user {

  group { 'appuser':
    ensure => present,
    system => true,
  }

  user { 'appuser':
    ensure     => present,
    gid        => 'appuser',
    system     => true,
    home       => '/opt/app',
    managehome => false,
    shell      => '/usr/sbin/nologin',
    comment    => 'Service account for the enterprise-java-platform application',
    require    => Group['appuser'],
  }
}
