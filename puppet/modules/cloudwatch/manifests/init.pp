# CloudWatch agent: ships application, nginx and PostgreSQL logs.
#
# The instance's IAM role grants logs:PutLogEvents scoped to this project's log
# groups only — no credentials are placed on the host.
class cloudwatch {

  $project = 'enterprise-java-platform'

  # The agent is not in Ubuntu's archive; install the vendor package.
  exec { 'download-cloudwatch-agent':
    command => '/usr/bin/curl -sSfL -o /tmp/amazon-cloudwatch-agent.deb https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb',
    creates => '/tmp/amazon-cloudwatch-agent.deb',
  }

  package { 'amazon-cloudwatch-agent':
    ensure   => installed,
    provider => dpkg,
    source   => '/tmp/amazon-cloudwatch-agent.deb',
    require  => Exec['download-cloudwatch-agent'],
  }

  file { '/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => template('cloudwatch/agent-config.json.erb'),
    require => Package['amazon-cloudwatch-agent'],
    notify  => Exec['restart-cloudwatch-agent'],
  }

  exec { 'restart-cloudwatch-agent':
    command     => '/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json',
    refreshonly => true,
    require     => Package['amazon-cloudwatch-agent'],
  }
}
