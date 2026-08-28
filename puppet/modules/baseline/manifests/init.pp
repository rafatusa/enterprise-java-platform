# Base packages and directory layout every deploy depends on.
class baseline {

  $runtime_packages = [
    'openjdk-17-jdk-headless',
    'maven',
    'nginx',
    'postgresql',
    'postgresql-contrib',
    # community.postgresql modules need psycopg2 on the managed host.
    'python3-psycopg2',
    # Ansible's password_hash('bcrypt') filter is backed by passlib, which needs
    # the bcrypt backend. Both come from the Ubuntu 22.04 base archive, so the
    # deploy does not have to bootstrap pip or reach PyPI to hash a password.
    'python3-passlib',
    'python3-bcrypt',
    'unzip',
    'curl',
    'jq',
    'acl',
  ]

  package { $runtime_packages:
    ensure => installed,
  }

  # Release layout: /opt/app/releases/<sha> with /opt/app/current symlinked to
  # the live release and /opt/app/previous to the last known-good one. This is
  # what makes an in-place rollback a symlink swap rather than a rebuild.
  file { ['/opt/app', '/opt/app/releases', '/opt/app/shared', '/opt/app/logs']:
    ensure => directory,
    owner  => 'appuser',
    group  => 'appuser',
    mode   => '0755',
    require => Class['app_user'],
  }

  service { 'nginx':
    ensure  => running,
    enable  => true,
    require => Package['nginx'],
  }

  service { 'postgresql':
    ensure  => running,
    enable  => true,
    require => Package['postgresql'],
  }

  # Remove the default nginx site so it cannot shadow the application vhost on
  # plain IP access.
  file { '/etc/nginx/sites-enabled/default':
    ensure  => absent,
    require => Package['nginx'],
    notify  => Service['nginx'],
  }
}
