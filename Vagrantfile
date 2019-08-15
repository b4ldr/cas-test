# -*- mode: ruby -*-
# vi: set ft=ruby :
Vagrant.configure('2') do |config|
  # For a complete reference, please see the online documentation at
  # https://docs.vagrantup.com.

  config.vm.box = 'debian/buster64'
  config.vm.network('forwarded_port', guest: 8443, host: 8443, host_ip: '127.0.0.1')
  config.vm.provider 'virtualbox' do |vb|
    vb.memory = '2048'
  end
  config.vm.provision 'shell', inline: <<-SHELL
     apt-get update
     apt-get install -y puppet
  SHELL
  config.vm.provision 'puppet' do |puppet|
    puppet.module_path = 'modules'
  end
end
