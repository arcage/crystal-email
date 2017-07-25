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

  def self.send(host : String, port : Int32 = DEFAULT_SMTP_PORT, **options)
    message = Message.new
    with message yield
    sender = Sender.new(host, port, **options)
    sender << message
    sender.start(1)
  end

end
