# EMail for Crystal

Simple e-Mail sending library for the **Cristal** language([https://crystal-lang.org/](https://crystal-lang.org/)).

You can do:

- constructing e-Mail with a text message and/or some attachment files.
- setting multiple recipients to e-Mail.
- using multibyte characters(only UTF-8) in e-Mail.
- sending e-Mail by using local or remote SMTP server.
- using tls connection by `STARTTLS` command.
- using SMTP-AUTH by `AUTH PLAIN` command when using tls.

You can not do:

- constructing multipart/alternative contents for e-Mail.
- using ESMTP features except those mentioned above.

## Installation

Add this to your application's `shard.yml`:

```yaml
dependencies:
  email:
    github: arcage/crystal-email
```

## Usage

Basic e-Mail sending procedure:

```crystal
require "email"

EMail.send("your.mx.server.name", 25) do
  from     "your@mail.addr"
  to       "to@some.domain"
  cc       "cc@some.domain"
  bcc      "bcc@some.domain"
  reply_to "reply_to@mail.addr"
  subject  "Subject of the mail"
  message  <<-EOM
    Message body of the mail.

    --
    Your Signature
    EOM
end
```

This code will output log entries to `STDOUT` as follows:

```text
2016/11/11 12:15:58 [EMail_Client/7412] INFO Start TCP session to your.mx.server.name:25
2016/11/11 12:15:58 [EMail_Client/7412] INFO Successfully sent a message from <your@mail.addr> to 2 recipient(s)
```

You can add some option arguments to `EMail.send`.

- `log_level : Logger::Severity` (Default: `Logger::Severity::INFO`)

    Set log level for SMTP session.

    - `Logger::Severity::DEBUG` : logging all smtp commands and responses.
    - `Logger::Severity::ERROR` : logging only events stem from some errors.
    - `EMail::Client::NO_LOGGING`(`Logger::Severity::UNKOWN`) : no events will be logged.

- `client_name : String` (Default: `"EMail_Client"`)

    Set `progname` of the internal `Logger` object. It is also used as a part of _Message-Id_ header.

- `helo_domain : String` (Default: `"[" + lcoal_ip_addr + "]"`)

    Set the parameter string for SMTP `EHLO`(or `HELO`) command. By default, the local ip address of the socket will be assigned.

- `on_failed : EMail::Client::OnFailedProc` (Default: None)

    Set callback function to be called when sending e-Mail is failed while in SMTP session. It will be called with e-Mail message object that tried to send, and SMTP command and response history. In this function, you can do something to handle errors: e.g. "_investigating the causes of the fail_", "_notifying you of the fail_", and so on.

    `EMail::Client::OnFailedProc` is an alias of the Proc type `EMail::Message, Array(String) ->`.

- `use_tls : Bool` (Default: `false`)

    Try to use `STARTTLS` command to send e-Mail with TLS encryption.

- `auth` : `Tuple(String, String)` (Default: None)

    Set login id and password to use `AUTH PLAIN` command: e.g. `{"login_id", "password"}`.

    This option must be use with `ust_tls: true`.

```crystal
# example with option arguments

on_failed = EMail::Client::OnFailedProc.new do |mail, command_history|
  puts mail.data
  puts ""
  puts command_history.join("\n")
end

EMail.send("your.mx.server.name", 587,
           log_level:   Logger::Severity::DEBUG,
           client_name: "MailBot",
           helo_domain: "your.host.fqdn",
           on_failed:   on_failed,
           use_tls: true,
           auth: {"your_id", "your_password"}) do

  # same as above

end
```

This will output:

```text
2016/11/11 12:35:48 [MailBot/7918] INFO Start TCP session to your.mx.server.name:587
2016/11/11 12:35:48 [MailBot/7918] DEBUG <-- CONN 220 unknown ESMTP
2016/11/11 12:35:48 [MailBot/7918] DEBUG --> EHLO your.host.fqdn
2016/11/11 12:35:48 [MailBot/7918] DEBUG <-- EHLO 250 your.mx.server.name / PIPELINING / SIZE 51380224 / ETRN / STARTTLS / ENHANCEDSTATUSCODES / 8BITMIME / DSN
2016/11/11 12:35:48 [MailBot/7918] DEBUG --> STARTTLS
2016/11/11 12:35:48 [MailBot/7918] DEBUG <-- STARTTLS 220 2.0.0 Ready to start TLS
2016/11/11 12:35:48 [MailBot/7918] INFO Start TLS session
2016/11/11 12:35:48 [MailBot/7918] DEBUG --> EHLO your.host.fqdn
2016/11/11 12:35:48 [MailBot/7918] DEBUG <-- EHLO 250 your.mx.server.name / PIPELINING / SIZE 51380224 / ETRN / AUTH PLAIN LOGIN / ENHANCEDSTATUSCODES / 8BITMIME / DSN
2016/11/11 12:35:48 [MailBot/7918] DEBUG --> AUTH PLAIN AHlvdXJfaWQAeW91cl9wYXNzd29yZA==
2016/11/11 12:35:48 [MailBot/7918] DEBUG <-- AUTH 235 2.0.0 Authentication successful
2016/11/11 12:35:48 [MailBot/7918] INFO Authentication success with your_id / ********
2016/11/11 12:35:48 [MailBot/7918] DEBUG --> MAIL FROM:<your@mail.addr>
2016/11/11 12:35:48 [MailBot/7918] DEBUG <-- MAIL 250 2.1.0 Ok
2016/11/11 12:35:48 [MailBot/7918] DEBUG --> RCPT TO:<to@some.domain>
2016/11/11 12:35:48 [MailBot/7918] DEBUG <-- RCPT 250 2.1.5 Ok
2016/11/11 12:35:48 [MailBot/7918] DEBUG --> RCPT TO:<cc@some.domain>
2016/11/11 12:35:48 [MailBot/7918] DEBUG <-- RCPT 250 2.1.5 Ok
2016/11/11 12:35:48 [MailBot/7918] DEBUG --> RCPT TO:<bcc@some.domain>
2016/11/11 12:35:48 [MailBot/7918] DEBUG <-- RCPT 250 2.1.5 Ok
2016/11/11 12:35:48 [MailBot/7918] DEBUG --> DATA
2016/11/11 12:35:48 [MailBot/7918] DEBUG <-- DATA 354 End data with <CR><LF>.<CR><LF>
2016/11/11 12:35:48 [MailBot/7918] DEBUG --> Sending mail data
2016/11/11 12:35:48 [MailBot/7918] DEBUG <-- DATA 250 2.0.0 Ok: queued as 42C5428260
2016/11/11 12:35:48 [MailBot/7918] DEBUG --> QUIT
2016/11/11 12:35:48 [MailBot/7918] DEBUG <-- QUIT 221 2.0.0 Bye
2016/11/11 12:35:48 [MailBot/7918] INFO Successfully sent a message from <your@mail.addr> to 3 recipient(s)
```

### `EMail::Message` object(default receiver of the block for `EMail.send`)

You can set multiple **From**, **To**, **Cc**, **Bcc** or **Reply-To** addresses by calling `#from`, `#to`, `#cc`, `#bcc` or `#reply_to` multiple times.

```crystal
to "to1@some.domain"
to "to2@some.domain"

# Optionally, you can add mailbox name to above mail addresses.

from "your@mail.addr", "Your Name"
```

Call `#attach` to add an attachment file.

```crystal
attach "attachment.txt"

# You can designate other file name for recipient.

attach "attachment.txt", file_name: "other_name.txt"

# You can designate mime type of the attachment file explicitly.
#
# By default, the mime type of the attachment file will be inferred
# from the extension of that file.
#   eg: ".txt" => "text/plain"

attach "attachment", mime_type: "text/plain"

# You can use readable `IO` object instead of the file path.
# In this case, the 2nd argument(`file_name`) is required.
# (The `mime_type` argument is also acceptable.)

attach some_io, file_name: "other_name.txt"
```

UTF-8 string can be used as follows:

- mail message
- part of header body(when it can be multibyte)
- name of attachment file

```crystal
subject "メールサブジェクト"
from "your@mail.addr", "山田　太郎"
to "to@mail.addr", "山田　花子"
message <<-EOM
  こんにちは
  EOM
attach "写真.jpg"
```

For the simplifying the implementation, the mail message and all attached data will be encoded by Base64, even when that includes only ascii characters.

Call `#envelope_from`, `#sender`, `#return_path` to set envelope from address, **Sender** or **Return-Path** explicitly.

```crystal
envelope_from "return@your.mail"
sender        "sender@your.mail"
return_path   "return@your.mail"
```

When they are unspecified:

- Envelope from

    The first **From** address will be assigned.

- **Sender**

    When **From** has only one address, **Sender** will not appear. Otherwise, the first **From** address will be assigned.

- _Return-Path_
    1. Use envelope from address if it is explicitly specified.
    2. Use **Sender** address if it is exist.
    3. Otherwise, the first **From** address will be assigned.

## Contributors

- [arcage](https://github.com/arcage) ʕ·ᴥ·ʔAKJ - creator, maintainer
