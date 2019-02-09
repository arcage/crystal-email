require "base64"
require "logger"
require "socket"
{% if !flag?(:without_openssl) %}
  require "openssl"
{% end %}
require "uri"
require "./email/*"

module EMail
  VERSION           = "0.3.3"
  DEFAULT_SMTP_PORT = 25

  # :nodoc:
  DOMAIN_FORMAT = /\A[a-zA-Z0-9\!\#\$\%\&\'\*\+\-\/\=\?\^\_\`^{\|\}\~]+(\.[a-zA-Z0-9\!\#\$\%\&\'\*\+\-\/\=\?\^\_\`^{\|\}\~]+)+\z/

  def self.send(config : EMail::Client::Config)
    message = Message.new
    with message yield
    EMail::Client.new(config).start do
      send(message)
    end
  end

  def self.send(*args, **named_args)
    config = EMail::Client::Config.create(*args, **named_args)
    message = Message.new
    with message yield
    EMail::Client.new(config).start do
      send(message)
    end
  end
end
