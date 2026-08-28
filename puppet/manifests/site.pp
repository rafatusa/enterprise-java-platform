# Masterless Puppet entry point.
#
# Declares the DURABLE state of the application server: packages, the service
# account, the release directory layout, OS hardening and log shipping.
# Per-release application deployment is Ansible's job (ansible/site.yml).

node default {
  class { 'baseline': }
  class { 'app_user': }
  class { 'hardening': }
  class { 'cloudwatch': }
}
