Utility build scripts for Vagrant
=================================

TODO: add proper formatting and other svistelkis&perdelkis

OS specific
-----------

### CentOS 6.x

ln -s /usr/src/kernels/2.6.32-754.3.5.el6.x86_64 /usr/src/kernels/2.6.32-754.el6.x86_64

### Sample usage

      ./build.sh -n centos6_x64 -d ~/vagrant_vms

### Adding box

        vagrant box add centos7_x64 centos7_x64.box


### Removing box

        vagrant box remove -f centos6_x64

