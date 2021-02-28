# Garager

Opens a secure websocket connection to a control server, so your garage door can be opened from anywhere (that can access your control server) with low latency (connection is already open).

## Setting up a Raspberry Pi using raspbian

Install raspbian, configure wifi, install updates. Then, enable the Camera interface in the Raspberry Pi configuration tool (`raspi-config`).

**Note on headless:** Setup wifi and ssh by adding the files `wpa_supplicant.conf` and `ssh` to the boot partition. `wpa_supplicant.conf` must have the wifi credentials and examples can be found via google. The `ssh` file is empty.

The remaining setup takes places on the raspberry pi command line, either through the built in terminal tool or a remote ssh session.

### Install user ruby

Give us an up-to-date ruby that belongs to the `pi` user so we can safely install gems and extensions without interfering with the system ruby and needing root privileges

I prefer to use chruby+ruby-install

* [chruby install instructions](https://github.com/postmodern/chruby)
* [ruby-install install instructions](https://github.com/postmodern/ruby-install)

Install both tools, including [chruby's `.bashrc` changes](https://github.com/postmodern/chruby#auto-switching), and restart terminal.

```
wget -O chruby-0.3.9.tar.gz https://github.com/postmodern/chruby/archive/v0.3.9.tar.gz
tar -xzvf chruby-0.3.9.tar.gz
cd chruby-0.3.9/
sudo make install
cd ..
wget -O ruby-install-0.8.1.tar.gz https://github.com/postmodern/ruby-install/archive/v0.8.1.tar.gz
tar -xzvf ruby-install-0.8.1.tar.gz
cd ruby-install-0.8.1/
sudo make install
cd ..
echo "source /usr/local/share/chruby/chruby.sh" >> .bashrc
echo "source /usr/local/share/chruby/auto.sh" >> .bashrc
```

Install a recent ruby version and set it as the system default. This will take a very long time to complete (45+min on a raspberry pi 3).

```
ruby-install --jobs=4 ruby 2.7.2
echo "2.7.2" > ~/.ruby-version
```

### Create a RAM disk

We will be writing camera images to a file every few seconds. This will destroy most SD cards in a fairly short period of time. Instead, lets write the image to RAM (via tmpfs).

Create a directory to mount the RAM disk to:

```
$ sudo mkdir /ramdisk
```

Edit `/etc/fstab` and add the following line:

```
tmpfs  /ramdisk  tmpfs  nodev,nosuid,size=64M  0  0
```

Restart the raspberry pi.

### Install motion-project

Motion is a utility that makes camera control pretty easy.

```
$ sudo apt install motion
```

The config file in this project (`doc/motion.conf`) will configure motion to stream the raspberry pi camera on the local network, on port 8081 (8082 for low quality and 8080 for web config), as well as store a snapshot image every 10 seconds to the RAM disk we created above. Place it at `/etc/motion/motion.conf`

Edit `/etc/default/motion` and change `start_motion_daemon` to `yes` to enable motion to work as a system controlled service.

Start the service

```
$ sudo service motion start
```

You can then access a video stream via http://garager:8081/ using the credentials defined in `motion.conf`.

### Install wiringpi

Depending on which Raspberry Pi OS or raspbian version you install you may need to install the wiringpi toolset to add the `gpio` command. If `which gpio` returns a location then you have the tool installed already. If it returns nothing then you'll need to install it:

```
wget https://project-downloads.drogon.net/wiringpi-latest.deb
sudo dpkg -i wiringpi-latest.deb
```

### Install garager

```
git clone https://github.com/carlzulauf/garager.git
cd garager
gem install bundler
bundle install
```

Copy the garager service (`doc/garager.service`) to `/etc/systemd/system/garager.service` and then enable the service:

```
sudo systemctl enable garager
```
