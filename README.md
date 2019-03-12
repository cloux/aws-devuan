<a href="https://devuan.org/os/init-freedom/"><img src="https://devuan.org/ui/img/if.png" width="110" height="150" align="right"></a>
# Devuan + Runit for Amazon EC2

>"Do one thing, do it well."
><cite> - [Doug McIllroy](https://en.wikipedia.org/wiki/Unix_philosophy#Do_One_Thing_and_Do_It_Well)</cite>

>"Do everything, do it in PID1"
><cite> - [systemd](https://ewontfix.com/14/)</cite>

## About

![htop](screenshot.png)

This project aims to provide a viable alternative to the systemd-monotheistic AWS offering. The goal is to track progress and maintain documentation for a fast, stable and secure general-purpose operating system for [Amazon EC2](https://aws.amazon.com/ec2/).

[Devuan](https://devuan.org/os/) seems to be the [practical and stable](https://blog.ungleich.ch/en-us/cms/blog/2017/12/10/the-importance-of-devuan/) choice for administrators running servers in datacenters. [Devuan](https://devuan.org/os) which runs SysVinit by default was modified to use [Runit](http://cloux.org/init/#runit) as init and PID1 process. The AWS EC2 specific code is in this repository, the runit-init infrastructure is in the [runit-base](https://github.com/cloux/runit-base) repository, and the installation/update scripts are implemented as modules of [Simple Installer](https://github.com/cloux/sin).

---
## Why bother?

Because of systemd and its real world performance: http://cloux.org/init/#systemd

systemd became the single most widespread Linux init system. And it doesn't just do init, it also does login, pam, getty, syslog, udev, cryptsetup, cron, at, dbus, acpi, gnome-session, autofs, tcpwrappers, audit, chroot, mount<sup>([1](https://systemd-free.org))</sup>, network management, DNS, Firewall, UEFI<sup>([2](http://without-systemd.org/wiki/index.php/Arguments_against_systemd#Scope_creep))</sup>, su<sup>([3](https://linux.slashdot.org/story/15/08/29/1526217/systemd-absorbs-su-command-functionality))</sup>, HTTP server<sup>([4](https://www.freedesktop.org/software/systemd/man/systemd-journal-gatewayd.service.html))</sup> ... and on saturdays it also does your laundry. Adopted by all major distributions, there seems to be no real alternative. systemd is not just a default software choice. Many packages depend directly on it, which makes it IMPOSSIBLE to remove or switch to something else later on. Even if you use systemd on a daily basis and everything goes well, you might want to have some alternative. So, what alternatives are available?

### EC2 Linux AMI Comparison

Free-Tier Eligible general purpose GNU/Linux systems on AWS, as of 2018-03:

| AMI Name | [Init System](http://cloux.org/init) | Category | Packages | EBS Size<sup>*1</sup> | Boot Time<sup>*2</sup> <sup>([&pm;SD](https://en.wikipedia.org/wiki/Standard_deviation))</sup> | License | 
| :---  | :--- | :--- | :--- | :--- | :--- | :--- |
| Amazon Linux AMI 2017.09.1 | upstart | Quick Start | rpm | 8 GB | 7.2&nbsp;s&nbsp;<sup>(&pm;1.1)</sup> | [EULA](https://aws.amazon.com/agreement/) |
| Amazon Linux 2 LTS Candidate AMI 2017.12.0 | systemd | Quick Start | rpm | 8 GB | 26.6&nbsp;s&nbsp;<sup>(&pm;0.2)</sup> | [EULA](https://aws.amazon.com/agreement/) |
| Red Hat Enterprise Linux [7.4](https://access.redhat.com/articles/3135091) | systemd | Quick Start | rpm | 10 GB | 13.0&nbsp;s&nbsp;<sup>(&pm;0.5)</sup> | [EULA](https://www.redhat.com/en/about/agreements) |
| SUSE Linux Enterprise Server 12 SP3 | systemd | Quick Start | rpm | 10 GB | 44.2&nbsp;s&nbsp;<sup>(&pm;1.3)</sup> | [EULA](https://www.suse.com/company/legal/#c), [Terms](https://www.suse.com/products/terms_and_conditions.pdf) |
| Ubuntu Server 16.04 LTS | systemd | Quick Start | apt | 8 GB | 10.5&nbsp;s&nbsp;<sup>(&pm;1.6)</sup> | [EULA](https://www.ubuntu.com/legal/terms-and-policies/intellectual-property-policy)|
| CentOS 7 | systemd | Marketplace | rpm | 8 GB | 15.0&nbsp;s&nbsp;<sup>(&pm;0.8)</sup> | Free |
| Debian GNU/Linux 9.3 Stretch | systemd | Marketplace | apt | 8 GB | 7.0&nbsp;s&nbsp;<sup>(&pm;0.9)</sup> | [Free](https://d7umqicpi7263.cloudfront.net/eula/product/572488bb-fc09-4638-8628-e1e1d26436f4/060496c2-9fe5-4a95-9ab6-0ff2f7abb669.txt) |
| **Devuan Runit 2018-12-06** | [**Runit**](http://cloux.org/init/#runit) | **Community** | **apt** | **4 GB** | **3.6&nbsp;s**&nbsp;<sup>(&pm;0.9)</sup> | [**Free**](https://devuan.org/os/free-software) |

<sup>\*1) Smallest possible storage size for a new instance</sup>  
<sup>\*2) Determined by [ec2-benchmark-osboot.sh](https://raw.githubusercontent.com/cloux/sin/master/ec2-tools/inst/ec2-benchmark-osboot.sh), on _t2.micro_ in _us-east-1a_, averaged 5 consecutive runs</sup>

This is not a comprehensive comparison. Some AMIs might not qualify as general-purpose on EC2: while [Gentoo](https://gentoo.org) uses [OpenRC](http://cloux.org/init/#openrc) and not systemd, it is limited to very few [instance types](https://aws.amazon.com/ec2/instance-types/). However, if it works for your use case, Gentoo is definitely worth a try.  
Amazon Linux 2017.09 looks like it's running SysVinit, but PID1 uses [obsolete](https://launchpad.net/upstart/+series) upstart v0.6.5. Either way, this OS is considered [end-of-life](https://aws.amazon.com/amazon-linux-2/faqs/#Support_for_Existing_AMI_.282017.09.29_for_Amazon_Linux) and should not be used for any new projects.

All major Linux distributions already transitioned to systemd. If you want to use something else on Amazon EC2, you are pretty much out of luck. This is where the **Devuan + Runit** distribution comes in:

---
## Features

Currently available Devuan AMI offers:

 * [**Runit**](http://cloux.org/init/#runit) as init and service supervisor
 * Small footprint with only **4 GB** minimal EBS volume size
 * Fast direct boot **without Initrd**
 * Custom [compiled](https://raw.githubusercontent.com/cloux/sin/master/modules/kernel/install) stable kernel from https://www.kernel.org
    * Included network drivers Amazon ENA v1.3.0K (25Gb) + Intel ixgbevf 4.1.0-k (10Gb)
 * Fully automated AMI release cycle, always with the latest kernel 
 * Easily configurable logging, with all logs being textfiles in _/var/log_
    * _[svlogd](http://smarden.org/runit/svlogd.8.html)_ used for services writing to stdout
    * _[socklog](http://smarden.org/socklog/)_ used as runit-compatible syslog facility
 * Preinstalled [cloud-init](https://cloud-init.io)
 * Preinstalled [oomd](https://facebookmicrosites.github.io/oomd/) - efficient Out-Of-Memory userspace killer based on [PSI](https://facebookmicrosites.github.io/psi/)
 * Preinstalled [amazon-ssm-agent](https://github.com/aws/amazon-ssm-agent)
 * Preinstalled [Hiawatha](https://www.hiawatha-webserver.org), advanced and secure webserver<a href="https://www.hiawatha-webserver.org"><img src="https://www.hiawatha-webserver.org/images/banners/hiawatha_88x31.png" align="right"></a>
 	* Fully [automated](https://raw.githubusercontent.com/cloux/sin/master/modules/hiawatha/certbot) domain TLS certificate management, requests and renewals

_NOTE:_ not everybody wants to run a webserver or amazon-ssm-agent. For convenience, these services are preinstalled and activated, since they are not directly available from the repository. If you don't need it, simply use the _svdeactivate_ command, see [service management](#runit-service-management).

### Main changes

The setup differences compared to a clean Devuan installation mainly address runit compatibility with Devuan and AWS EC2 environment integration:

#### Preinstalled tools

    # apt-get install acpid apache2-utils aptitude bison certbot cpulimit curl dnsutils ethtool eudev flex fuse gawk htop incron iptraf kexec-tools lsof lynx mc multitail ncdu ncftp nfs-common nfs-kernel-server nfswatch nfstrace ntp p7zip-full pciutils pigz php php-cgi procmail pwgen rename rsync screen sntop ssmtp telnet whois zip

#### Compiled from source

 * Linux stable kernel (https://www.kernel.org), see [sin - kernel module](https://raw.githubusercontent.com/cloux/sin/master/modules/kernel/install)
 * Hiawatha webserver (http://www.hiawatha-webserver.org), see [sin - hiawatha module](https://raw.githubusercontent.com/cloux/sin/master/modules/hiawatha/install)
 * Socklog (http://smarden.org/socklog/install.html), see [sin - socklog module](https://raw.githubusercontent.com/cloux/sin/master/modules/socklog/install)
 * [amazon-ssm-agent](https://raw.githubusercontent.com/cloux/sin/master/modules/amazon-ssm-agent/install), ec2-metadata and other [tools](https://github.com/cloux/sin/modules/ec2-tools/)

Sources are placed in _/usr/src_ and _/root/inst_ inside the AMI.

---
## Installation

**"Devuan Runit YYYY-MM-DD (Unofficial)"** AMIs are available in the Amazon EC2 **us-east-1** (N. Virginia) region in the **Community AMIs** category. This git repository serves as documentation and development base for Devuan AMIs inside AWS EC2, and cannot be directly used for AWS management, installation, or upgrades.

Why **'Unofficial'**: This project is not affiliated with the official Devuan GNU/Linux distribution in any way.

---
## Usage

A few useful commands to get you up and running. These Runit scripts are universal, and work well outside the cloud environment.

### Login

 * The default SSH user is **admin**
 * For an easy access, use [ssh-login](https://raw.githubusercontent.com/cloux/sin/master/modules/nettools/ssh-login)  
   or use the command `ssh -i INSTANCE-KEY.pem admin@INSTANCE-IP`

### Runit service management

In addition to standard Runit [service control](http://smarden.org/runit/sv.8.html), these commands were added for convenience:

 * [svactivate](https://raw.githubusercontent.com/cloux/sin/master/modules/runit-init/inst/svactivate) - include and start services in Runit supervisor
 * [svdeactivate](https://raw.githubusercontent.com/cloux/sin/master/modules/runit-init/inst/svdeactivate) - stop services and disable supervision

### System Updates

Updates and additional installations outside of the repository are available through the [Simple Installer](https://github.com/cloux/sin):

 * `sin kernel` - compile and update the kernel from latest source on kernel.org
 * `sin install oomd amazon-ssm-agent` - update the [oomd](https://facebookmicrosites.github.io/oomd/) and [ssm-agent](https://github.com/aws/amazon-ssm-agent) from source

---
<a href="http://www.wtfpl.net"><img src="http://www.wtfpl.net/wp-content/uploads/2012/12/wtfpl-badge-2.png" align="right"></a>
## License

This work is free. You can redistribute it and/or modify it under the terms of the Do What The Fuck You Want To Public License, Version 2, as published by Sam Hocevar. See http://www.wtfpl.net for more details. If you feel that releasing this work under WTFPL is not appropriate, since some of the code might be derivative and thus possibly breaking some other license... just do WTF you want to.

### Trademarks
"AWS" and "Amazon EC2" are registered trademarks of Amazon\.com Inc., "Devuan" is a registered trademark of the Dyne\.org foundation, "Debian" is a registered trademark of Software in the Public Interest Inc., "Ubuntu" is a registered Trademark of Canonical Inc.,  "SuSE" is a registered trademark of SUSE IP Development Ltd., Red Hat is a trademark or registered trademark of Red Hat Inc. or its subsidiaries, Linux is a registered trademark of Linus Torvalds. All other possibly and impossibly mentioned trademarks are the property of their respective owners.

---
## Author

This repository is maintained by _cloux@rote.ch_

### Disclaimer

I am not involved or in any way affiliated with the development of any particular init system. I do not participate in any public discussion or flamewar about init. I am not a fanboy, nor a hater. I do not have any personal feelings towards any init, or any other software, or its developers. As a sysadmin I could not care less which init system is in use, as long as it works. Also, I do not claim fitness of this project for any particular purpose and do not take any responsibility for its use. You should always choose your system and all of its components very carefully, if something breaks it's on you. See [license](#license).

_NOTE:_ Much of the Runit base structure is "borrowed" from the [void-runit](https://github.com/voidlinux/void-runit), and modified to integrate with Devuan inside cloud environment.

### Contributing

I will keep this project alive as long as I can, and as long as there is some interest. This is however a private project, so my support is fairly limited. Any help with further development, testing, and bugfixing will be appreciated. If you want to report a bug, please either [raise an issue](https://github.com/cloux/aws-devuan/issues), or fork the project and send me a pull request.

### Thanks to

 * Devuan Project: https://devuan.org
 * Void Linux: https://www.voidlinux.org
 * Runit and Socklog author Gerrit Pape: https://smarden.org/pape
 * Hiawatha author Hugo Leisink: https://www.hiawatha-webserver.org
 * Flussence: https://gitlab.com/flussence/runit-scripts

---