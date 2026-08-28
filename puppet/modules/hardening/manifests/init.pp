# OS hardening aligned with the CIS Ubuntu 22.04 Benchmark.
#
# Scope note: this is Tier-2 baseline hardening (SSH policy, kernel network
# parameters, unattended security updates). It is NOT a full CIS Level 2
# implementation — auditd, AppArmor profiles and filesystem partitioning are
# listed as optional enhancements in the plan.
class hardening {

  # --- SSH policy -----------------------------------------------------------
  # Password and root login are disabled: the ONLY access path is the platform
  # deploy key injected at launch via the EC2 key pair.
  file { '/etc/ssh/sshd_config.d/99-hardening.conf':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0600',
    content => @(EOT),
      # Managed by Puppet — do not edit by hand.
      PermitRootLogin no
      PasswordAuthentication no
      PermitEmptyPasswords no
      ChallengeResponseAuthentication no
      X11Forwarding no
      MaxAuthTries 4
      ClientAliveInterval 300
      ClientAliveCountMax 2
      LoginGraceTime 60
      | EOT
    notify  => Service['ssh'],
  }

  service { 'ssh':
    ensure => running,
    enable => true,
  }

  # --- Kernel network hardening --------------------------------------------
  file { '/etc/sysctl.d/99-hardening.conf':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => @(EOT),
      # Managed by Puppet — do not edit by hand.
      net.ipv4.conf.all.accept_redirects = 0
      net.ipv4.conf.all.send_redirects = 0
      net.ipv4.conf.all.accept_source_route = 0
      net.ipv4.conf.all.log_martians = 1
      net.ipv4.conf.all.rp_filter = 1
      net.ipv4.tcp_syncookies = 1
      net.ipv6.conf.all.accept_redirects = 0
      kernel.randomize_va_space = 2
      | EOT
    notify  => Exec['reload-sysctl'],
  }

  exec { 'reload-sysctl':
    command     => '/sbin/sysctl --system',
    refreshonly => true,
  }

  # --- Unattended security updates -----------------------------------------
  package { 'unattended-upgrades':
    ensure => installed,
  }

  file { '/etc/apt/apt.conf.d/20auto-upgrades':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => @(EOT),
      APT::Periodic::Update-Package-Lists "1";
      APT::Periodic::Unattended-Upgrade "1";
      | EOT
    require => Package['unattended-upgrades'],
  }

  service { 'unattended-upgrades':
    ensure  => running,
    enable  => true,
    require => Package['unattended-upgrades'],
  }
}
