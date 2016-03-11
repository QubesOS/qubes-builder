Configuring a yum/dnf repo proxy
================================

The [Configuration Documentation](Configuration.md) describes the
`REPO_PROXY` variable which can be set in your builder configuration
file in order to proxy package downloads. This document details how to
setup such a proxy and explains why you might want to.


Background
----------

Depending on your configuration, building Qubes involves creating multiple
chroot environments. Each environment is bootstrapped and then updated using
`dnf` (formerly `yum`) to download packages over the network. As different
packages are built, thier dependencies are also downloaded. This can require
a lot of time and data. For example, at the time of writing, bootstrapping
just one Fedora 23 setup downloads around a gigabyte of data.

In the course of normal development, you will end up cleaning and rebuilding,
and this will require the same data to be downloaded again and again. By
setting up a caching proxy you can keep this data locally and save time and
bandwidth.

Below we will describe setting up [Squid](http://www.squid-cache.org/) to
cache this data. This setup assumes that the cache will be on the
development VM, but you can set it up elsewhere once you are familiar with
it.


HOWTO
-----

First you need to install squid in your template VM. For Fedora:
```
$ sudo dnf install squid
$ sudo rm -f /etc/squid/squid.conf
```

Note that we remove the default configuration file as we will provide
our own in the development VM where we run squid.

Next you must shutdown the template VM and restart your development
VM to pickup the installation.

Depending on the settings of the VM where squid will run, you may need
to increase the maximum disk size in the Qubes VM Manager. You should allow
at least 2 gigabytes for the cache itself.

Now create the following file as `/rw/config/squid.conf`:

```
acl localnet src 10.0.0.0/8

acl SSL_ports port 443
acl Safe_ports port 80          # http
acl Safe_ports port 443         # https
acl CONNECT method CONNECT

http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports

http_access allow localhost manager
http_access deny manager

http_access allow localnet
http_access allow localhost
http_access deny all

http_port 3128

cache_dir ufs /path/to/storage/directory/ 2000 16 256

maximum_object_size 32 MB

cache_replacement_policy heap LFUDA

acl filetype urlpath_regex \.rpm
cache allow filetype
send_hit allow filetype
cache deny all
```

Change `/path/to/storage/directory/` to a directory under `/rw/` and make
sure it is writable by the user `squid`. On the same line change `2000` to
the number of megabytes of cache space you want to reserve (2000 being ~2
GB).

Finally we need to make squid start up when your VM does. Run the following
commands:
```
sudo chmod +x /rw/config/rc.local
echo "sudo cp /rw/config/squid.conf /etc/squid/squid.conf" | sudo tee --a /rw/config/rc.local
echo "systemctl start squid" | sudo tee --a /rw/config/rc.local
```

When you restart the VM (or run the commands added to `rc.local` manually),
squid will be running ready to serve requests. Add the following to your
`builder.conf` file:
```
REPO_PROXY = http://localhost:3128/
```

Now your proxy should be working. As you build, you can tail
`/var/log/squid/access.log` to see requests serviced by the cache.
