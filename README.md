<a href="https://devuan.org/os/init-freedom/"><img src="https://devuan.org/ui/img/if.png" width="110" height="150" align="right"></a>
# Devuan + Runit for Amazon EC2

>"Do one thing, do it well."
><cite> - [Doug McIllroy](https://en.wikipedia.org/wiki/Unix_philosophy#Do_One_Thing_and_Do_It_Well)</cite>

>"Do everything, do it in PID1."
><cite> - [Systemd](https://ewontfix.com/14/)</cite>

## About

This project aims to provide a viable alternative to the current systemd-monotheistic AWS offering. The goal is to track progress and maintain documentation for a small, fast, stable and secure general-purpose operating system for Amazon EC2.

[Devuan](https://devuan.org/os/) seems to be the [practical and stable](https://blog.ungleich.ch/en-us/cms/blog/2017/12/10/the-importance-of-devuan/) choice for administrators running servers in datacenters. Devuan [Ascii](https://devuan.org/os/releases), which runs SysVinit by default, was modified to use [Runit](http://smarden.org/runit/) instead. All changes regarding this switch are in this repository. Most of the code is directly applicable to other standalone Devuan-based distributions outside the cloud environment.

---
## Why bother?

>The crowd pushing Systemd, possibly including its author, is not content to have systemd be one choice among many. By providing public APIs intended to be used by other applications, systemd has set itself up to be difficult not to use once it achieves a certain adoption threshold. Its popularity is purely the result of an aggressive, dictatorial marketing strategy including engulfing other essential system components, setting up for API lock-in, and dictating policy... at the expense of flexibility and diversity.
>
><cite>\- [Rich Felker](https://ewontfix.com/14/), author of [musl](http://www.musl-libc.org/faq.html) library</cite>

The development progress of Systemd seems to closely resemble the well-known "[embrace, extend, extinguish](https://en.wikipedia.org/wiki/Embrace,_extend,_and_extinguish)" strategy formerly used by Microsoft. Whether intentional or not, this can arguably lead to a dangerous situation. Systemd has shown to be unstable, [prone to crashes](https://www.agwa.name/blog/post/how_to_crash_systemd_in_one_tweet), and it's developers approach to security is [famous for being lame](https://www.theregister.co.uk/2017/07/28/black_hat_pwnie_awards/). 

Systemd became the single most widespread Linux init system. And it doesn't just do init, it also does login, pam, getty, syslog, udev, cryptsetup, cron, at, dbus, acpi,  gnome-session, autofs, tcpwrappers, audit, chroot, mount<sup>([1](https://systemd-free.org))</sup> , network management, DNS, Firewall, UEFI<sup>([2](http://without-systemd.org/wiki/index.php/Arguments_against_systemd#Scope_creep))</sup>, su<sup>([3](https://linux.slashdot.org/story/15/08/29/1526217/systemd-absorbs-su-command-functionality))</sup>, HTTP server<sup>([4](https://www.freedesktop.org/software/systemd/man/systemd-journal-gatewayd.service.html))</sup> ... and on saturdays it also does your laundry. Adopted by all major distributions, there seems to be no real alternative, pushing the Linux base further towards a monoculture environment. Systemd is not just a default software choice. Many packages depend directly on it, which makes it IMPOSSIBLE to remove or switch to something else later on. Once you run an OS with Systemd, that's it, you're stuck with it, for better or worse, so help you God. And even if you use Systemd on a daily basis and everything goes well, you might want to have some alternative. Just in the case that something breaks someday. So, what alternatives are available?

### EC2 Linux AMI Comparison

Free-Tier Eligible general purpose GNU/Linux systems on AWS, as of 2017-12:

| AMI Name | [Init System](https://devuan.org/os/init-freedom/) | Category | Packages | EBS Size<sup>*1</sup> | Boot Time<sup>*2</sup> | License | 
| :---  | :--- | :--- | :--- | :--- | :--- | :--- |
| Amazon Linux AMI 2017.09.1 | Systemd | Quick Start | rpm | 8 GB | | [EULA](https://aws.amazon.com/agreement/) |
| Amazon Linux 2 LTS Candidate AMI 2017.12.0 | Systemd | Quick Start | rpm | 8 GB | | [EULA](https://aws.amazon.com/agreement/) |
| Red Hat Enterprise Linux [7.4](https://access.redhat.com/articles/3135091) | Systemd | Quick Start | rpm | 10 GB | | [EULA](https://www.redhat.com/en/about/agreements) |
| SUSE Linux Enterprise Server 12 SP3 | Systemd | Quick Start | rpm | 10 GB | | [EULA](https://www.suse.com/company/legal/#c), [Terms](https://www.suse.com/products/terms_and_conditions.pdf) |
| Ubuntu Server 16.04 LTS | Systemd | Quick Start | apt | 8 GB | | [EULA](https://www.ubuntu.com/legal/terms-and-policies/intellectual-property-policy)|
| CentOS 7 | Systemd | Marketplace | rpm | 8 GB | | Free |
| Debian GNU/Linux 9 (Stretch) | Systemd | Marketplace | apt | 8 GB | | [Free](https://d7umqicpi7263.cloudfront.net/eula/product/572488bb-fc09-4638-8628-e1e1d26436f4/060496c2-9fe5-4a95-9ab6-0ff2f7abb669.txt) |
| **Devuan Ascii** (this AMI) | [**Runit**](https://en.wikipedia.org/wiki/Runit) | **Community** | **apt** | **3 GB** | | [**Free**](https://devuan.org/os/free-software) |


\*1) Smallest possible volume storage size for a new instance  
\*2) Determined by [ benchmark-ec2-boottime.sh](https://gist.github.com/andsens/3813743), on _t2.micro_ in _us-east-1a_, average value from 3 consecutive runs (measurements pending... until 2018-1)

This is not a comprehensive comparison, some OS might disqualify for other reasons, like their limited [instance type](https://aws.amazon.com/ec2/instance-types/) support. While [Gentoo](https://gentoo.org) uses [OpenRC](https://wiki.gentoo.org/wiki/OpenRC) and not Systemd, most of the Gentoo AMIs are limited to just a few instance types, therefore it's not considered a general-purpose system on AWS and is not included in the comparison (also, the latest version doesn't run on t2.micro). However, if it works for your use case, Gentoo is definitely worth a try.

It's clear that all major distributions on AWS already transitioned to Systemd. If you want to use something else, you are pretty much out of luck. And very much out of luck on AWS. This is where **Devuan Ascii + Runit** distribution comes in:

---
## Features

Currently available Devuan AMI offers:

 * _Runit_  init with _runsvdir_ as service supervisor
 * Small footprint (3 GB minimal volume size)
 * All logs are saved as text files inside _/var/log/_
    * _[svlogd](http://smarden.org/runit/svlogd.8.html)_ used for logging services writing into stdout and stderr (e.g. ssh)
    * _[socklog](http://smarden.org/socklog/)_ to log services using sockets (e.g. dhclient)
    * other services writing logfiles directly (e.g. bootlogd or hiawatha)
    * easily comprehensible and configurable logging setup per service
 * Network drivers inside initramfs: Amazon ENA (25Gb ethernet) + Intel 82599 ixgbevf 3.3.2-k (10Gb)
 * Devuan stock kernel 4.9.0-4
 * cloud-init v0.7.9
 * `aptitude` package manager
 * Preinstalled [Hiawatha](https://www.hiawatha-webserver.org) v10.7, advanced and secure webserver
 * Additional preinstalled utilities
 * hardened _sshd_config_ - drops failed logins faster
 

### Changes

The main differences compared to a clean Devuan installation:

**Preinstalled tools from Devuan repository:**

    # apt-get install acpid apache2-utils aptitude auditd certbot cpulimit curl ethtool eudev fuse gawk htop incron iptraf kexec-tools lsof lynx mc ncdu ncftp nfs-common nfswatch nfstrace ntp p7zip-full pciutils pigz php php-cgi pwgen rename runit screen sntop ssmtp sysv-rc-conf

**Additionally from sources:**

 * aws-ena (https://github.com/vnetmx/aws-ena)
 * Socklog (http://smarden.org/socklog/install.html)
 * Hiawatha (http://www.hiawatha-webserver.org)

All sources are in _/root/inst/_ directory inside the AMI. All other modifications are in this repository. These mainly address runit compatibility with Devuan and cloud environment integration.

_NOTE:_ not everybody wants to run a webserver. However, for convenience, Hiawatha is preinstalled since it is not directly available from the main repository. If you don't need a webserver, or wish to use a different one, you can easily deactivate the Hiawatha service, see [service management](#runit-service-management).

---
## Installation

**"Devuan Ascii YYYY-MM-DD (Unofficial)"** AMIs are available in the Amazon EC2 **us-east-1** region in the **Community AMIs** category. This git repository serves as documentation and development base for Devuan AMIs inside AWS EC2, and cannot be directly used for AWS management, installation, or upgrades.

**Why 'Unofficial'**: This project is not affiliated with the official Devuan GNU/Linux distribution in any way.

---
## Usage

A few useful commands to get an instance up and running.

**Login**

 * The default user is **admin**
 * To login to your new instance over SSH, use:  
   `ssh -i INSTANCE-KEY.pem admin@INSTANCE-IP`

**Timezone** is set to UTC by default. To change it, run:

 * `dpkg-reconfigure tzdata`

**Shutdown and reboot**:

 * `shutdown` - simple immediate halt and power off. Does not accept any parameters.
 * `reboot` - immediate system reboot
 * `reboot soft` - reboot quickly without waiting for BIOS, see [kexec](http://horms.net/projects/kexec/)
 
### Runit service management

In addition to standard Runit commands, these were added for convenience:

 * `svactivate` - include and start services in Runit supervisor
 * `svdeactivate` - stop and disable service supervision
 * `runit-core-install` - forcibly integrate Runit into the system. Useful after a system upgrade to keep commands like _reboot_ and _shutdown_ to work properly.

---
## ToDo

 * Automate AMI propagation to all EC2 regions (currently us-east-1 only)
 * Include the _amazon-ssm-agent_ (https://github.com/aws/amazon-ssm-agent)
 * Integrate Runit into _update-rc.d_ (part of devuan's "init-system-helpers" package), to enable immediate automatic activation of services upon installation
 * Add Runit supervisor support for more services
 * Customize kernel, replace Devuan stock with stable branch from kernel\.org
 * Create clean [VOID](https://www.voidlinux.eu) AMI from scratch, as an additional alternative distribution

---
<a href="http://www.wtfpl.net"><img src="http://www.wtfpl.net/wp-content/uploads/2012/12/wtfpl-badge-2.png" align="right"></a>
## License

This work is free. You can redistribute it and/or modify it under the terms of the Do What The Fuck You Want To Public License, Version 2, as published by Sam Hocevar. See http://www.wtfpl.net for more details. If you feel that releasing this work under WTFPL is not appropriate, since some of the code might be derivative and thus possibly breaking some other license... just do WTF you want to.

_NOTE:_ Much of the Runit base structure is "borrowed" from the [Voidlinux](https://www.voidlinux.eu), and modified to integrate with Devuan inside cloud environment. Notably for some Runit stage 1 bootup scripts, further license clarification might be necessary in order to keep this project under WTFPL.

### Trademarks
"AWS" and "Amazon EC2" are registered trademarks of Amazon\.com Inc., "Devuan" is a registered trademark of the Dyne\.org foundation, "Debian" is a registered trademark of Software in the Public Interest Inc., "Ubuntu" is a registered Trademark of Canonical Inc.,  "SuSE" is a registered trademark of SUSE IP Development Ltd., Red Hat is a trademark or registered trademark of Red Hat Inc. or its subsidiaries, Linux is a registered trademark of Linus Torvalds. All other possibly and impossibly mentioned trademarks are the property of their respective owners.

---
## Author

This repository is maintained by _cloux@rote.ch_

### Disclaimer

I am not involved in the development, nor in any way affiliated with any particular init system. I do not participate in any discussion or flamewar about init. I am not a fanboy, nor a hater. I do not have any personal feelings towards any init, or any other software, or it's developers. As a sysadmin, I could not care less which init system is in use. As long as it works. And in the case it doesn't, I want to have a solid alternative available. Also, I do not claim fitness of this project for any particular purpose, and do not take any responsibility for it's use. You should always choose your system and all of it's components very carefully, if something breaks it's on you. See [license](#license).

### Contributing

I will keep this project alive as long as I can, and as long as there is some interest. This is however a private project, so my support is fairly limited. Any help with further development, testing, and bugfixing will be appreciated. If you want to report a bug, please either [raise an issue](https://github.com/cloux/aws-devuan/issues), or fork the project and send me a pull request.

### Thanks to

 * Devuan Project: https://devuan.org
 * Void Linux: https://www.voidlinux.eu
 * Runit and Socklog author Gerrit Pape: https://smarden.org/pape
 * Hiawatha author Hugo Leisink: https://www.hiawatha-webserver.org

---