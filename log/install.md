# Install Raspbian

* Download image: https://www.raspberrypi.org/downloads/raspbian/
* Use dd to copy image to SD card

    sudo dd bs=4M if=2015-05-05-raspbian-wheezy.img of=/dev/mmcblk0

* Hook up keyboard/monitor
* Use Raspberry Pi Software Configuration Tool
  * Expand Filesystem
  * give pi user a new password
  * change keyboard layout from English (UK) to English (US)
* Add the following to `/etc/wpa_supplicant/wpa_supplicant.conf`

        network={
            ssid="network-ssid-here"
            psk="password-goes-here"
        }

* `mkdir .ssh`
* `scp /home/carl/.ssh/id_rsa.pub pi@192.168.1.11:.ssh/authorized_keys`

## Rebuild 2016-02-26

* Download latest raspbian and use `dd` to copy to SD card

    sudo dd bs=4M if=2016-02-09-raspbian-jessie.img of=/dev/mmcblk0

* Mount drive and modify `/etc/wpa_supplicant/wpa_supplicant.conf`

        network={
            ssid="network-ssid-here"
            psk="password-goes-here"
        }

* Modify `/etc/ssh/sshd_config` by uncommenting and changing

    PasswordAuthentication no

* Copy authorized ssh public key

    mkdir .ssh
    cp ~/.ssh/id_rsa.pub .ssh/authorized_keys

* Copy garager directory to /home/pi. Did this using GUI.
* Unmount SD card (both volumes) and install in pi
* Wait a few minutes, sshd should start

    ssh pi@192.168.1.11

* Expand file system (to ensure space for packages/libs)

    sudo raspi-config
    # select expand, exit
    sudo reboot

* Rename to garager

    sudo nano /etc/hostname
    sudo nano /etc/hosts
