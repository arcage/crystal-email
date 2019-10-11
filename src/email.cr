require "base64"
require "logger"
require "socket"
{% if !flag?(:without_openssl) %}
  require "openssl"
{% end %}
require "uri"
require "./email/*"

module EMail
  VERSION           = "0.4.3"
  DEFAULT_SMTP_PORT = 25

  # :nodoc:
  DOMAIN_FORMAT = /\A[a-zA-Z0-9\!\#\$\%\&\'\*\+\-\/\=\?\^\_\`^{\|\}\~]+(\.[a-zA-Z0-9\!\#\$\%\&\'\*\+\-\/\=\?\^\_\`^{\|\}\~]+)+\z/

  # Send one email with given client settings as EMail::Client::Config object.
  #
  # ```crystal
  # config = EMail::Client::Config.new("your.mx.server.name", 587)
  # config.use_tls
  # config.use_auth("your_id", "your_password")
  # config.logger.level = Logger::DEBUG
  #
  # EMail.send(config) do
  #   # In this block, default receiver is EMail::Message object
  #   from "your@mail.addr"
  #   to "to@some.domain"
  #   subject "Subject of the mail"
  #
  #   message <<-EOM
  #     Message body of the mail.
  #
  #     --
  #     Your Signature
  #     EOM
  # end
  # ```
  def self.send(config : EMail::Client::Config)
    message = Message.new
    with message yield
    EMail::Client.new(config).start do
      send(message)
    end
  end

  # Send one email with given client settings as several arguments.
  #
  # Avairable arguments are same as `EMail::Client::Conifg.create` method.
  # ```crystal
  # EMail.send("your.mx.server.name", 578,
  #   use_tle: true,
  #   auth: {"your_id", "your_password"},
  #   log_level: Logger::DEBUG) do
  #   # In this block, default receiver is EMail::Message object
  #   from "your@mail.addr"
  #   to "to@some.domain"
  #   subject "Subject of the mail"
  #
  #   message <<-EOM
  #     Message body of the mail.
  #
  #     --
  #     Your Signature
  #     EOM
  # end
  # ```
  def self.send(*args, **named_args)
    config = EMail::Client::Config.create(*args, **named_args)
    message = Message.new
    with message yield
    EMail::Client.new(config).start do
      send(message)
    end
  end
end
