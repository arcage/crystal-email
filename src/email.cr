require "base64"
require "logger"
require "socket"
require "uri"
require "./email/*"

module EMail
  DEFAULT_SMTP_PORT = 25

  def self.send(host : ::String, port : ::Int32 = DEFAULT_SMTP_PORT, **option)
    mail = Message.new
    yield mail
    mail.validate!
    client = Client.new(host, port)
    if log_level = option[:log_level]?
      client.log_level = log_level
    end
    if client_name = option[:client_name]?
      client.client_name = client_name
    end
    if helo_domain = option[:helo_domain]?
      client.helo_domain = helo_domain
    end
    if on_failed = option[:on_failed]?
      client.on_failed = on_failed
    end
    client.send(mail)
  end
end
