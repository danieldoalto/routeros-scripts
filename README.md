RouterOS Scripts
================

[![GitHub stars](https://img.shields.io/github/stars/eworm-de/routeros-scripts?logo=GitHub&style=flat&color=red)](https://github.com/eworm-de/routeros-scripts/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/eworm-de/routeros-scripts?logo=GitHub&style=flat&color=green)](https://github.com/eworm-de/routeros-scripts/network)
[![GitHub watchers](https://img.shields.io/github/watchers/eworm-de/routeros-scripts?logo=GitHub&style=flat&color=blue)](https://github.com/eworm-de/routeros-scripts/watchers)

![RouterOS Scripts Logo](logo.svg)

[RouterOS](https://mikrotik.com/software) is the operating system developed
by [MikroTik](https://mikrotik.com/aboutus) for networking tasks. This
repository holds a number of [scripts](https://wiki.mikrotik.com/wiki/Manual:Scripting)
to manage RouterOS devices or extend their functionality.

*Use at your own risk*, pay attention to
[license and warranty](#license-and-warranty)!

Requirements
------------

Latest version of the scripts require recent RouterOS to function properly.
Make sure to install latest updates before you begin.

Specific scripts may require even newer RouterOS version.

> ℹ️ **Info**: The `main` branch is now RouterOS v7 only. If you are still
> running RouterOS v6 switch to `routeros-v6` branch!

Initial setup
-------------

### Get me ready!

If you know how things work just copy and paste the
[initial commands](INITIAL-COMMANDS.md). Remember to edit and rerun
`global-config-overlay`!
First time users should take the long way below.

### Live presentation

Want to see it in action? I've had a presentation [Repository based
RouterOS script distribution](https://www.youtube.com/watch?v=B9neG3oAhcY)
including demonstation recorded live at [MUM Europe
2019](https://mum.mikrotik.com/2019/EU/) in Vienna.

> ⚠️ **Warning**: Some details changed. So see the presentation, then follow
> the steps below for up-to-date commands.

### The long way in detail

The update script does server certificate verification, so first step is to
download the certificates. If you intend to download the scripts from a
different location (for example from github.com) install the corresponding
certificate chain.

    /tool/fetch "https://git.eworm.de/cgit/routeros-scripts/plain/certs/R3.pem" dst-path="letsencrypt-R3.pem";

![screenshot: download certs](README.d/01-download-certs.avif)

Note that the commands above do *not* verify server certificate, so if you
want to be safe download with your workstations's browser and transfer the
files to your MikroTik device.

* [ISRG Root X1](https://letsencrypt.org/certs/isrgrootx1.pem)
* Let's Encrypt [R3](https://letsencrypt.org/certs/lets-encrypt-r3.pem)

Then we import the certificates.

    /certificate/import file-name=letsencrypt-R3.pem passphrase="";

![screenshot: import certs](README.d/02-import-certs.avif)

For basic verification we rename the certificates and print their count. Make
sure the certificate count is **two**.

    /certificate/set name="R3" [ find where fingerprint="67add1166b020ae61b8f5fc96813c04c2aa589960796865572a3c7e737613dfd" ];
    /certificate/set name="ISRG-Root-X1" [ find where fingerprint="96bcec06264976f37460779acf28c5a7cfe8a3c0aae11a8ffcee05c0bddf08c6" ];
    /certificate/print count-only where fingerprint="67add1166b020ae61b8f5fc96813c04c2aa589960796865572a3c7e737613dfd" or fingerprint="96bcec06264976f37460779acf28c5a7cfe8a3c0aae11a8ffcee05c0bddf08c6";

![screenshot: check certs](README.d/03-check-certs.avif)

Always make sure there are no certificates installed you do not know or want!

All following commands will verify the server certificate. For validity the
certificate's lifetime is checked with local time, so make sure the device's
date and time is set correctly!

Now let's download the main scripts and add them in configuration on the fly.

    :foreach Script in={ "global-config"; "global-config-overlay"; "global-functions" } do={ /system/script/add name=$Script source=([ /tool/fetch check-certificate=yes-without-crl ("https://git.eworm.de/cgit/routeros-scripts/plain/" . $Script . ".rsc") output=user as-value]->"data"); };

![screenshot: import scripts](README.d/04-import-scripts.avif)

And finally load configuration and functions and add the scheduler.

    /system/script { run global-config; run global-functions; };
    /system/scheduler/add name="global-scripts" start-time=startup on-event="/system/script { run global-config; run global-functions; }";

![screenshot: run and schedule scripts](README.d/05-run-and-schedule-scripts.avif)

### Scheduled automatic updates

The last step is optional: Add this scheduler **only** if you want the
scripts to be updated automatically!

    /system/scheduler/add name="ScriptInstallUpdate" start-time=startup interval=1d on-event=":global ScriptInstallUpdate; \$ScriptInstallUpdate;";

![screenshot: schedule update](README.d/06-schedule-update.avif)

Editing configuration
---------------------

The configuration needs to be tweaked for your needs. Edit
`global-config-overlay`, copy relevant configuration from
[`global-config`](global-config.rsc) (the one without `-overlay`).
Save changes and exit with `Ctrl-o`.

    /system/script/edit global-config-overlay source;

![screenshot: edit global-config-overlay](README.d/07-edit-global-config-overlay.avif)

To apply your changes run `global-config`, which will automatically load
the overlay as well:

    /system/script/run global-config;

![screenshot: apply configuration](README.d/08-apply-configuration.avif)

This last step is required when ever you make changes to your configuration.

> ℹ️ **Info**: It is recommended to edit the configuration using the command
> line interface. If using Winbox on Windows OS, the line endings may be
> missing. To fix this run:
> `/system/script/set source=[ $Unix2Dos [ get global-config-overlay source ] ] global-config-overlay;`

Updating scripts
----------------

To update existing scripts just run function `$ScriptInstallUpdate`. If
everything is up-to-date it will not produce any output.

    $ScriptInstallUpdate;

![screenshot: update scripts](README.d/09-update-scripts.avif)

If the update includes news or requires configuration changes a notification
is sent - in addition to terminal output and log messages.

![news and changes notification](README.d/notification-news-and-changes.avif)

Adding a script
---------------

To add a script from the repository run function `$ScriptInstallUpdate` with
a comma separated list of script names.

    $ScriptInstallUpdate check-certificates,check-routeros-update;

![screenshot: install scripts](README.d/10-install-scripts.avif)

Scheduler and events
--------------------

Most scripts are designed to run regularly from
[scheduler](https://wiki.mikrotik.com/wiki/Manual:System/Scheduler). We just
added `check-routeros-update`, so let's run it every hour to make sure not to
miss an update.

    /system/scheduler/add name="check-routeros-update" interval=1h on-event="/system/script/run check-routeros-update;";

![screenshot: schedule script](README.d/11-schedule-script.avif)

Some events can run a script. If you want your DHCP hostnames to be available
in DNS use `dhcp-to-dns` with the events from dhcp server. For a regular
cleanup add a scheduler entry.

    $ScriptInstallUpdate dhcp-to-dns,lease-script;
    /ip/dhcp-server/set lease-script=lease-script [ find ];
    /system/scheduler/add name="dhcp-to-dns" interval=5m on-event="/system/script/run dhcp-to-dns;";

![screenshot: setup lease script](README.d/12-setup-lease-script.avif)

There's much more to explore... Have fun!

Available scripts
-----------------

* [Find and remove access list duplicates](doc/accesslist-duplicates.md)
* [Upload backup to Mikrotik cloud](doc/backup-cloud.md)
* [Send backup via e-mail](doc/backup-email.md)
* [Save configuration to fallback partition](doc/backup-partition.md)
* [Upload backup to server](doc/backup-upload.md)
* [Download packages for CAP upgrade from CAPsMAN](doc/capsman-download-packages.md)
* [Run rolling CAP upgrades from CAPsMAN](doc/capsman-rolling-upgrade.md)
* [Renew locally issued certificates](doc/certificate-renew-issued.md)
* [Renew certificates and notify on expiration](doc/check-certificates.md)
* [Notify about health state](doc/check-health.md)
* [Notify on LTE firmware upgrade](doc/check-lte-firmware-upgrade.md)
* [Notify on RouterOS update](doc/check-routeros-update.md)
* [Collect MAC addresses in wireless access list](doc/collect-wireless-mac.md)
* [Use wireless network with daily psk](doc/daily-psk.md)
* [Comment DHCP leases with info from access list](doc/dhcp-lease-comment.md)
* [Create DNS records for DHCP leases](doc/dhcp-to-dns.md)
* [Automatically upgrade firmware and reboot](doc/firmware-upgrade-reboot.md)
* [Wait for global functions und modules](doc/global-wait.md)
* [Send GPS position to server](doc/gps-track.md)
* [Use WPA2 network with hotspot credentials](doc/hotspot-to-wpa.md)
* [Create DNS records for IPSec peers](doc/ipsec-to-dns.md)
* [Update configuration on IPv6 prefix change](doc/ipv6-update.md)
* [Manage IP addresses with bridge status](doc/ip-addr-bridge.md)
* [Run other scripts on DHCP lease](doc/lease-script.md)
* [Manage LEDs dark mode](doc/leds-mode.md)
* [Forward log messages via notification](doc/log-forward.md)
* [Mode button with multiple presses](doc/mode-button.md)
* [Manage DNS and DoH servers from netwatch](doc/netwatch-dns.md)
* [Notify on host up and down](doc/netwatch-notify.md)
* [Visualize OSPF state via LEDs](doc/ospf-to-leds.md)
* [Manage system update](doc/packages-update.md)
* [Run scripts on ppp connection](doc/ppp-on-up.md)
* [Act on received SMS](doc/sms-action.md)
* [Forward received SMS](doc/sms-forward.md)
* [Import SSH keys](doc/ssh-keys-import.md)
* [Play Super Mario theme](doc/super-mario-theme.md)
* [Chat with your router and send commands via Telegram bot](doc/telegram-chat.md)
* [Install LTE firmware upgrade](doc/unattended-lte-firmware-upgrade.md)
* [Update GRE configuration with dynamic addresses](doc/update-gre-address.md)
* [Update tunnelbroker configuration](doc/update-tunnelbroker.md)

Available modules
-----------------

* [Manage ports in bridge](doc/mod/bridge-port-to.md)
* [Manage VLANs on bridge ports](doc/mod/bridge-port-vlan.md)
* [Inspect variables](doc/mod/inspectvar.md)
* [IP address calculation](doc/mod/ipcalc.md)
* [Send notifications via e-mail](doc/mod/notification-email.md)
* [Send notifications via Matrix](doc/mod/notification-matrix.md)
* [Send notifications via Telegram](doc/mod/notification-telegram.md)
* [Download script and run it once](doc/mod/scriptrunonce.md)

Installing custom scripts & modules
-----------------------------------

My scripts cover a lot of use cases, but you may have your own ones. You can
still use my scripts to manage and deploy yours, by specifying `base-url`
(and `url-suffix`) for each script.

This will fetch and install a script `hello-world.rsc` from the given url:

    $ScriptInstallUpdate hello-world "base-url=https://git.eworm.de/cgit/routeros-scripts-custom/plain/";

![screenshot: install custom script](README.d/13-install-custom-script.avif)

For a script to be considered valid it has to begin with a *magic token*.
Have a look at [any script](README.d/hello-world.rsc) and copy the first line
without modification.

Starting a script's name with `mod/` makes it a module and it is run
automatically by `global-functions`.

### Linked custom scripts & modules

> ⚠️ **Warning**: These links are being provided for your convenience only;
> they do not constitute an endorsement or an approval by me. I bear no
> responsibility for the accuracy, legality or content of the external site
> or for that of subsequent links. Contact the external site for answers to
> questions regarding its content.

* [Hello World](https://git.eworm.de/cgit/routeros-scripts-custom/about/doc/hello-world.md)
  (This is a demo script to show how the linking to external documentation
  will be done.)

> ℹ️ **Info**: You have your own set of scripts and/or modules and want these
> to be listed here? There should be a general info page that links here,
> and documentation for each script. You can start by cloning my
> [Custom RouterOS-Scripts](https://git.eworm.de/cgit/routeros-scripts-custom/)
> (or fork on [GitHub](https://github.com/eworm-de/routeros-scripts-custom)
> or [GitLab](https://gitlab.com/eworm-de/routeros-scripts-custom)) and make
> your changes. Then please [get in contact](#patches-issues-and-whishlist)...

Removing a script
-----------------

There is no specific function for script removal. Just remove it from
configuration...

    /system/script/remove to-be-removed;

![screenshot: remove script](README.d/14-remove-script.avif)

Possibly a scheduler and other configuration has to be removed as well.

Contact
-------

We have a Telegram Group [RouterOS-Scripts](https://t.me/routeros_scripts)!

![RouterOS Scripts Telegram Group](README.d/telegram-group.avif)

Get help, give feedback or just chat - but do not expect free professional
support!

Contribute
----------

Thanks a lot for [past contributions](CONTRIBUTIONS.md)! ❤️

### Patches, issues and whishlist

Feel free to contact me via e-mail or open an
[issue](https://github.com/eworm-de/routeros-scripts/issues) or
[pull request](https://github.com/eworm-de/routeros-scripts/pulls)
at github.

### Donate

This project is developed in private spare time and usage is free of charge
for you. If you like the scripts and think this is of value for you or your
business please consider to
[donate with PayPal](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=A4ZXBD6YS2W8J).

[![donate with PayPal](https://www.paypalobjects.com/en_US/i/btn/btn_donate_SM.gif)](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=A4ZXBD6YS2W8J)

Thanks a lot for your support!

License and warranty
--------------------

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
[GNU General Public License](COPYING.md) for more details.

Upstream
--------

URL:
[GitHub.com](https://github.com/eworm-de/routeros-scripts#routeros-scripts)

Mirror:
[eworm.de](https://git.eworm.de/cgit/routeros-scripts/about/)
[GitLab.com](https://gitlab.com/eworm-de/routeros-scripts#routeros-scripts)

---
[⬆️ Go back to top](#top)
