require 'bundler/setup'
Bundler.require(:default)

REAL_GARAGE = !!(`uname -a` =~ /armv6l/)

require 'logger'
require 'garager/garage'
