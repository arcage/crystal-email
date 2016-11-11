require "base64"
require "logger"
require "socket"
{% if !flag?(:without_openssl) %}
  require "openssl"
{% end %}
require "uri"
require "./email/*"

module EMail
  DEFAULT_SMTP_PORT = 25

  def self.send(host : ::String, port : ::Int32 = DEFAULT_SMTP_PORT, **option)
    mail = Message.new
    yield mail
    mail.validate!
    client = Client.new(host, port)
    {% for opt in %i(log_level client_name helo_domain on_failed use_tls auth) %}
      if {{opt.id}} = option[{{opt}}]?
        client.{{opt.id}} = {{opt.id}}
      end
    {% end %}
    client.send(mail)
  end
end
