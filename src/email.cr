require "base64"
require "logger"
require "socket"
{% if !flag?(:without_openssl) %}
  require "openssl"
{% end %}
require "uri"
require "./email/*"

module EMail
  VERSION           = "0.3.2"
  DEFAULT_SMTP_PORT = 25

  def self.send(host : String, port : Int32 = DEFAULT_SMTP_PORT, **options)
    message = Message.new
    with message yield
    EMail::Client.new(host, port, **options).start do
      send(message)
    end
  end
end
