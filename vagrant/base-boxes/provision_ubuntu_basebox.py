import sys
import traceback
import time
import logging
import os

from fabric import Connection, Config
from argparse import ArgumentParser
from invoke.exceptions import UnexpectedExit

logging.basicConfig()
logger = logging.getLogger('provisioner')
logger.setLevel(logging.INFO)


def add_ssh_pubkey(c: Connection, remote_user: str, local_pkey_name: str):
    logger.info('Setting up SSH connectivity')
    dot_ssh_path = os.path.realpath(f'{os.getenv("HOME")}/.ssh')
    c.run(f'mkdir -p /home/{remote_user}/.ssh')
    c.run(f'chmod -R 750 /home/{remote_user}/.ssh')
    c.put(f'{dot_ssh_path}/{local_pkey_name}',
          f'/home/{remote_user}/.ssh/authorized_keys')
    c.run(f'chmod 400 /home/{remote_user}/.ssh/authorized_keys')


def apt_upgrade(c: Connection):
    logger.info('Upgrading software...')
    c.sudo('apt update')
    c.sudo('apt -y upgrade')


def setup_sudo(c: Connection):
    logger.info('Setting up passwordless sudo...')
    c.sudo('chmod 660 /etc/sudoers')
    c.sudo("bash -c \"echo \'vagrant ALL=(ALL) NOPASSWD: ALL\' >> /etc/sudoers\"")
    c.sudo('chmod 440 /etc/sudoers')


def setup_sshd_config(c: Connection):
    logger.info('Configuring sshd service...')
    c.sudo("sed -i '/^UseDNS/d' /etc/ssh/sshd_config")
    c.sudo("bash -c \"echo 'UseDNS no' >> /etc/ssh/sshd_config\"")
    c.sudo('systemctl reload sshd.service')

def install_guest_additions(c: Connection, version: str):
    download_url = 'https://download.virtualbox.org'
    guest_addition_iso = f'VBoxGuestAdditions_{version}.iso'
    guest_addition_mount = '/media/VBoxGuestAdditions'

    logger.info('Installing guest additions...')
    c.sudo('apt-get install -y -qq linux-headers-$(uname -r) build-essential dkms')
    c.run(f'wget {download_url}/virtualbox/{version}/{guest_addition_iso}')
    c.sudo(f'mkdir -p {guest_addition_mount}')
    c.sudo(f'mount -o loop,ro {guest_addition_iso} {guest_addition_mount}')
    try:
        c.sudo(f'sh {guest_addition_mount}/VBoxLinuxAdditions.run')
    except UnexpectedExit:
        logger.warning(f'VBoxLinuxAdditions.run exited with non-zero code')
    c.run(f'rm -f {guest_addition_iso}')
    c.sudo(f'umount {guest_addition_mount}')
    c.sudo(f'rmdir {guest_addition_mount}')


def clean_up(c: Connection):
    logger.info('Cleaning up...')
    c.sudo('apt-get -y autoremove')
    c.sudo('apt-get clean all')
    try:
        c.sudo('poweroff')
    except UnexpectedExit:
        pass


if __name__ == '__main__':
    try:
        parser = ArgumentParser(description="""\r
Fabric script for provisioning vagrant base box\r
                                """)
        parser.add_argument('--host',
                            dest='host',
                            help='Hostname or IP address of the VirtualBox VM to provision',
                            default='127.0.0.1')
        parser.add_argument('--port',
                            dest='port',
                            type=int,
                            help='Port where sshd listens',
                            default=2222)
        parser.add_argument('--username',
                            dest='username',
                            help='Username for ssh login',
                            default='vagrant')
        parser.add_argument('--password',
                            dest='password',
                            help='Password for ssh login',
                            default='vagrant')
        parser.add_argument('--local-pkey',
                            dest='local_pkey',
                            help='Name of the public key to take from ~/.ssh',
                            default='id_rsa.pub')
        parser.add_argument('--guest-addition-version',
                            dest='guest_addition_version',
                            help='Numeric version of VBox guest additions package',
                            default='6.1.32')

        args = parser.parse_args()

        logger.info('Setting up connection...')

        config = Config(overrides={'user': args.username,
                                   'load_ssh_configs': False,
                                   'connect_kwargs': {'password': args.password},
                                   'sudo': {'password': args.password}})

        c = Connection(host=args.host,
                       port=args.port,
                       user=args.username,
                       config=config)

        add_ssh_pubkey(c, args.username, args.local_pkey)
        setup_sudo(c)
        apt_upgrade(c)
        setup_sshd_config(c)
        install_guest_additions(c, args.guest_addition_version)
        clean_up(c)

        logger.info('Provisioning has been completed')

    except KeyboardInterrupt:
        print('Got SIGINT, terminating')
        time.sleep(0.2)
        sys.exit(0)
    except Exception:
        print('Something went wrong, see traceback below')
        traceback.print_exc()
        sys.exit(1)
