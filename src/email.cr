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

  # Sends a email constructed in its block.
  #
  # `option` arguments:
  #
  # `log_level` : `Logger::Severity` (Default: `Logger::Severity::INFO`)
  # - `Logger::Severity::DEBUG` : logging all smtp commands and responses.
  # - `Logger::Severity::ERROR` : logging only events stem from some errors.
  # - `EMail::Client::NO_LOGGING`(`Logger::Severity::UNKOWN`) : no events will be logged.
  #
  # `client_name : String` (Default: `"EMail_Client"`)
  # - Set `progname` of the internal `Logger` object. It is also used as a part of _Message-Id_ header.
  #
  # `helo_domain : String` (Default: `"[#{lcoal_ip_addr}]"`)
  # - Set the parameter string for SMTP `EHLO`(or `HELO`) command. By default, the local ip address of the socket will be assigned.
  #
  # `on_failed : EMail::Client::OnFailedProc` (Default: None)
  # - Set callback function to be called when sending e-Mail is failed while in SMTP session.
  #
  # `use_tls : Bool` (Default: `false`)
  # - Try to use `STARTTLS` command to send e-Mail with TLS encryption.
  #
  # `auth : Tuple(String, String)` (Default: None)
  # - Set login id and password to use `AUTH PLAIN` command: e.g. `{"login_id", "password"}`. (only with `use_tls: true`)
  #
  # Example:
  # ```
  # EMail.send("your.mx.server.name", 587,
  #            log_level:   Logger::DEBUG,
  #            client_name: "MailBot",
  #            helo_domain: "your.host.fqdn",
  #            on_failed:   on_failed,
  #            use_tls: true,
  #            auth: {"your_id", "your_password"}) do
  #
  #   subject       "Subject of the mail"
  #
  #   from          "your@mail.addr"
  #   to            "to@some.domain"
  #   cc            "cc@some.domain"
  #   bcc           "bcc@some.domain"
  #   reply_to      "reply_to@mail.addr"
  #
  #   envelope_from "return@your.mail"
  #   sender        "sender@your.mail"
  #   return_path   "return@your.mail"
  #
  #   message       <<-EOM
  #     Message body of the mail.
  #
  #     --
  #     Your Signature
  #     EOM
  #
  #   attach "./attachment_file.docx"
  #
  # end
  # ```
  def self.send(host : ::String, port : ::Int32 = DEFAULT_SMTP_PORT, **option)
    mail = Message.new
    with mail yield
    mail.validate!
    client = Client.new(host, port)
    {% for opt in %i(log_level client_name helo_domain on_failed use_tls auth) %}
      if {{opt.id}} = option[{{opt}}]?
        client.{{opt.id}} = {{opt.id}}
      end
    {% end %}
    client.send(mail)
  rescue
    if client
      client.close_socket
    end
  end
end
