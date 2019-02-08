class EMail::Client
  alias OnFailedProc = Message, Array(String) ->
  alias OnFatalErrorProc = Exception ->

  LOG_FORMATTER = Logger::Formatter.new do |severity, datetime, progname, message, io|
    io << datetime.to_s("%Y/%m/%d %T") << " [" << progname << "/" << Process.pid << "] "
    io << severity << " " << message
  end
  LOG_PROGNAME = "crystal-email"
  NO_LOGGING   = Logger::Severity::UNKNOWN
  DEFAULT_NAME = "EMail_Client"

  def self.create_default_logger : Logger
    logger = Logger.new(STDOUT)
    logger.progname = EMail::Client::LOG_PROGNAME
    logger.formatter = EMail::Client::LOG_FORMATTER
    logger.level = Logger::INFO
    logger
  end

  class Config
    property host : String
    property port : Int32
    getter name = EMail::Client::DEFAULT_NAME
    property logger : Logger = EMail::Client.create_default_logger
    getter helo_domain : String?
    property on_failed : EMail::Client::OnFailedProc?
    property on_fatal_error : EMail::Client::OnFatalErrorProc?
    @tls = false
    property openssl_verify_mode = OpenSSL::SSL::VerifyMode::PEER
    @auth : NamedTuple(id: String, password: String)?

    def self.create(host, port = EMail::DEFAULT_SMTP_PORT, *,
                    client_name name = nil, helo_domain = nil,
                    on_failed : EMail::Client::OnFailedProc? = nil,
                    on_fatal_error : EMail::Client::OnFatalErrorProc? = nil,
                    openssl_verify_mode : OpenSSL::SSL::VerifyMode? = nil,
                    use_tls : Bool? = nil, auth : Tuple(String, String)? = nil, logger : Logger? = nil)
      config = new(host, port)
      config.name = name if name
      config.helo_domain = helo_domain if helo_domain
      config.on_failed = on_failed if on_failed
      config.on_fatal_error = on_fatal_error if on_fatal_error
      config.openssl_verify_mode = openssl_verify_mode if openssl_verify_mode
      config.use_tls if use_tls
      config.use_auth(auth[0], auth[1]) if auth
      config.logger = logger if logger
      config
    end

    def initialize(@host, @port = EMail::DEFAULT_SMTP_PORT)
    end

    def helo_domain=(new_domain : String)
      raise EMail::Error::ClientError.new("Invalid HELO domain \"#{helo_domain}\"") unless new_domain =~ DOMAIN_FORMAT
      @helo_domain = new_domain
    end

    def use_tls(tls_port : Int32? = nil)
      {% if flag?(:without_openssl) %}
      raise EMail::Error::ClientError.new("TLS is disabled because `-D without_openssl` was passed at compile time")
      {% end %}
      @port = tls_port if tls_port
      @tls = true
    end

    def use_tls?
      @tls
    end

    def name=(new_name : String)
      raise EMail::Error::ClientError.new("Invalid client name \"#{new_name}\"") if new_name.empty? || new_name =~ /\W/
      @name = new_name
    end

    def use_auth(id, password)
      @auth = {id: id, password: password}
    end

    def auth_id
      @auth.try &.[](:id)
    end

    def auth_password
      @auth.try &.[](:password)
    end

    def use_auth?
      !@auth.nil?
    end
  end
end
