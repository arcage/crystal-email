describe NetUtils::EMail::Client do
  email = NetUtils::EMail::Message.new
  email.from "from@example.com"
  email.to "to@example.com"
  email.subject "Subject"
  email.message "Message"

  describe "#send" do
    it "try to send an email to SMTP server, but recipient refused." do
      log = String.build do |io|
        NetUtils::EMail::Client.log_io = io
        config = NetUtils::EMail::Client::Config.new("localhost", 25, helo_domain: "example.com")
        client = NetUtils::EMail::Client.new(config)
        client.start do
          send(email).should be_false
        end
      end
      log.should match(/ RCPT 454 /)
    end

    it "send an email with SMTP auth." do
      log = String.build do |io|
        NetUtils::EMail::Client.log_io = io
        config = NetUtils::EMail::Client::Config.new("localhost", 25, helo_domain: "example.com")
        config.use_tls(:starttls)
        config.tls_context.verify_mode = OpenSSL::SSL::VerifyMode::NONE
        config.use_auth("from@example.com", "password")
        client = NetUtils::EMail::Client.new(config)
        client.start do
          send(email).should be_true
        end
      end
      log.should match(/ Successfully sent /)
    end

    it "try to send an email with invalid password, but authentication refused." do
      log = String.build do |io|
        NetUtils::EMail::Client.log_io = io
        config = NetUtils::EMail::Client::Config.new("localhost", 25, helo_domain: "example.com")
        config.use_tls(:starttls)
        config.tls_context.verify_mode = OpenSSL::SSL::VerifyMode::NONE
        config.use_auth("from@example.com", "invalid")
        client = NetUtils::EMail::Client.new(config)
        client.start do
          send(email).should be_false
        end
      end
      log.should match(/ AUTH 535 /)
    end
  end
end
