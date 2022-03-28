# EMail for Crystal

[![Build Status](https://travis-ci.org/arcage/crystal-email.svg?branch=master)](https://travis-ci.org/arcage/crystal-email)

Simple email sending library for the [Crystal programming language](https://crystal-lang.org).

You can:

- construct an email with a plain text message, a HTML message and/or some attachment files.
- include resources(e.g. images) used in the HTML message.
- set multiple recipients to the email.
- use multibyte characters(only UTF-8) in the email.
- send the email by using local or remote SMTP server.
- use TLS connection by **SMTP orver SSL/TLS**(new) or `STARTTLS` command.
- use SMTP-AUTH by `AUTH PLAIN` or `AUTH LOGIN` when using TLS.
- send multiple emails concurrently by using multiple smtp connections.

You can not:

- use ESMTP features except those mentioned above.

## Installation

First, add the dependency to your `shard.yml`:

```yaml
dependencies:
  email:
    github: arcage/crystal-email
```

Then, run `shards install`

### Library requirement

When using STARTTLS or SMTPS, this shard require **libssl** and **libcrypto** for TLS handling. 

You may have to install those libraries to your system.

## Usage

To send a minimal email message:

**NOTE: Since v0.7.0, EMail::Client::Config object require `helo_domain` argument at initializing.**

```crystal
require "email"

# Create email message
email = EMail::Message.new
email.from    "your_addr@example.com"
email.to      "to@example.com"
email.subject "Subject of the mail"
email.message <<-EOM
  Message body of the mail.

  --
  Your Signature
  EOM

# Set SMTP client configuration
config = EMail::Client::Config.new("your.mx.example.com", 25, helo_domain: "your.host.example.com")

# Create SMTP client object
client = EMail::Client.new(config)

client.start do
  # In this block, default receiver is client
  send(email)
end
```

This code will output log entries to `STDOUT` as follows:

```text
2018/01/25 20:35:09 [e_mail.client/12347] INFO [EMail_Client] Start TCP session to your.mx.example.com:25
2018/01/25 20:35:10 [e_mail.client/12347] INFO [EMail_Client] Successfully sent a message from <your_addr@example.com> to 1 recipient(s)
2018/01/25 20:35:10 [e_mail.client/12347] INFO [EMail_Client] Close TCP session to your.mx.example.com:25
```

### Client configs

You can set some connection settings to `EMail::Client::Config` object.

That can make SMTP connection to use TLS / SMTP AUTH, or output more detailed log message.

See [EMail::Client::Config](https://www.denchu.org/crystal-email/EMail/Client/Config.html) for more details.

### Email message

You can set more email headers to `EMail::Message` object.

And, you can also send emails including attachment files, HTML message, and/or resource files related message body(e.g. image file for HTML message).

See [EMail::Message](https://www.denchu.org/crystal-email/EMail/Message.html) for more details.

### Concurrent sending

**Note: this feature supports the _concurrent_(not parallel) sending with only one thread.**

By using `EMail::ConcurrentSender` object, you can concurrently send multiple messages by multiple connections.

```crystal
rcpt_list = ["a@example.com", "b@example.com", "c@example.com", "d@example.com"]

# Set SMTP client configuration
config = EMail::Client::Config.new("your.mx.example.com", 25, helo_domain: "your.host.example.com")

# Create concurrent sender object
sender = EMail::ConcurrentSender.new(config)

# Sending emails with concurrently 3 connections.
sender.number_of_connections = 3

# Sending max 10 emails by 1 connection.
sender.messages_per_connection = 10

# Start email sending.
sender.start do
  # In this block, default receiver is sender
  rcpts_list.each do |rcpt_to|
    # Create email message
    mail = EMail::Message.new
    mail.from "your_addr@example.com"
    mail.to rcpt_to
    mail.subject "Concurrent email sending"
    mail.message "message to #{rcpt_to}"
    # Enqueue the email to sender
    enqueue mail
  end
end
```

See [EMail::ConcurrentSender](https://www.denchu.org/crystal-email/EMail/ConcurrentSender.html) for more details.

## Logging

The v0.34.0 of Crystal language has drastic changes in the logging functions. To fit it, the v0.5.0 of this shard also changes the logging behaviour.

You can use two kinds of logger(`Log` type object), the **default logger** and the **client specific logger**.

The **default logger** is declered on the `EMail::Client` type. It can be got by `EMail::Client.log`, and change its behavior by `EMail::Client.log_***=` methods.

On the other hand, the **client specific logger** will be set to `EMail::Client` instance itself by `EMail::Client::Config` setting. With this, you can use your own logger for the `EMail::Client` object.

If the `EMail::Client` object has the **client specific logger**, the client use it to output the log entries. Otherwise, the client use the **default logger**.

See [EMail::Client](https://www.denchu.org/crystal-email/EMail/Client.html) and [EMail::Client::Config](https://www.denchu.org/crystal-email/EMail/Client/Config.html) for more details.

### Debug log

When you set the log level to `Log::Severity::Debug`, you can see all of the SMTP commands and the resposes in the log entries.

```crystal
EMail::Client.log_level = Log::Severity::Debug
```

Debug log are very useful to check how SMTP session works.

But, in the case of using SMTP AUTH, the debug log includes Base64 encoded user ID and passowrd. You should remenber that anyone can decode the authentication information from the debug log. And, you should use that **very carefully**.

## Owner

- [arcage](https://github.com/arcage) ʕ·ᴥ·ʔAKJ - creator, maintainer

## Contributors

Thank you for valuable contributions.

- [Contributors](https://github.com/arcage/crystal-email/graphs/contributors)
