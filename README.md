# Garager

Probably shouldn't use this as existing versions use insecure drb (distributed ruby).

A conversion to secure web sockets is underway but is currently broken.

## Setting up a Raspberry Pi using raspbian

Install raspbian, configure wifi, install updates. Then, enable the Camera interface in the Raspberry Pi configuration tool.

You may also want to enable the ssh interface to make remote configuration simpler.

The remaining setup takes places on the raspberry pi command line, either through the built in terminal tool or a remote ssh session.

### Install user ruby

Give us an up-to-date ruby that belongs to the `pi` user so we can safely install gems and extensions without interfering with the system ruby and needing root privileges

I prefer to use chruby+ruby-install

* [chruby install instructions](https://github.com/postmodern/chruby)
* [ruby-install install instructions](https://github.com/postmodern/ruby-install)

Install both tools, including [chruby's `.bashrc` changes](https://github.com/postmodern/chruby#auto-switching), and restart terminal.

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

Edit `/etc/defaults/motion.conf` and change `start_motion_daemon` to `yes` to enable motion to work as a system controlled service.

Start the service

```
$ sudo service motion start
```

### Install garager
