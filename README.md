# EMail for Crystal

Simple e-Mail sending library for the **Cristal** language([https://crystal-lang.org/](https://crystal-lang.org/)).

You can do:

- constructing e-Mail with a text message and/or some attachment files.
- setting multiple recipients to e-Mail.
- using multibyte characters(only UTF-8) in e-Mail.
- sending e-Mail by using local or remote SMTP server.

You can not do:

- constructing multipart/alternative contents for e-Mail.
- using AUTH, STARTTLS or any other ESMTP features.

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

EMail.send("your.mx.server.name", 25) do |mail|
  mail.from     "your@mail.addr"
  mail.to       "to@some.domain"
  mail.cc       "cc@some.domain"
  mail.bcc      "bcc@some.domain"
  mail.reply_to "reply_to@mail.addr"
  mail.subject  "Subject of the mail"
  mail.message  <<-EOM
  Message body of the mail.

  --
  Your Signature
  EOM
end
```

This code will output log entries to `STDOUT` as follows:

```
2016/11/09 16:37:25 [EMail_Client/23852] INFO OK: connecting to your.mx.server.name
2016/11/09 16:37:25 [EMail_Client/23852] INFO OK: successfully sent message from <your@mail.addr> to 3 recipient(s)
```

You can add some option arguments to `EMail.send`.

- `:log_level` : `Logger::Severity`

    Set log level for SMTP session.
    - `Logger::Severity::DEBUG` : logging all smtp commands and responses.
    - `Logger::Severity::INFO` : default
    - `Logger::Severity::ERROR` : logging only events stem from some errors.
    - `EMail::Client::NO_LOGGING`(`Logger::Severity::UNKOWN`) : no events will be logged.

- `:client_name` : `String`

    Set `progname` of the internal `Logger` object. It is also used as a part of _Message-Id_ header. (Default: `"EMail_Client"`)

- `:helo_domain` : `String`

    Set the parameter string for SMTP `EHLO`(or `HELO`) command. By default, the local ip address of the socket will be assigned.

- `:on_failed` : `EMail::Client::OnFailedProc`

    Set callback function to be called when sending e-Mail is failed while in SMTP session. It will be called with e-Mail message object that tried to send, and SMTP command and response history. In this function, you can do something to handle errors: e.g. "investigating the causes of the fail", "notifying you of the fail", and so on.

    `EMail::Client::OnFailedProc` is an alias of the Proc type `EMail::Message, Array(String) ->`.

```crystal
# example with option arguments

on_failed = EMail::Client::OnFailedProc.new do |mail, command_history|
  puts mail.data
  puts ""
  puts command_history.join("\n")
end

EMail.send("your.mx.server.name", 25,
           log_level:   Logger::Severity::DEBUG,
           client_name: "MailBot",
           helo_domain: "your.host.fqdn",
           on_failed:   on_failed) do |mail|

  # same as above

end
```

This will output:

```
2016/11/09 16:40:39 [MailBot/24031] INFO OK: connecting to your.mx.server.name
2016/11/09 16:40:39 [MailBot/24031] DEBUG <-- 220 *************
2016/11/09 16:40:39 [MailBot/24031] DEBUG --> EHLO your.host.fqdn
2016/11/09 16:40:39 [MailBot/24031] DEBUG <-- 250 your.mx.server.name PIPELINING SIZE 51380224 ETRN ENHANCEDSTATUSCODES 8BITMIME DSN
2016/11/09 16:40:39 [MailBot/24031] DEBUG --> MAIL FROM:<your@mail.addr>
2016/11/09 16:40:39 [MailBot/24031] DEBUG <-- 250 2.1.0 Ok
2016/11/09 16:40:39 [MailBot/24031] DEBUG --> RCPT TO:<to@some.domain>
2016/11/09 16:40:39 [MailBot/24031] DEBUG <-- 250 2.1.5 Ok
2016/11/09 16:40:39 [MailBot/24031] DEBUG --> RCPT TO:<cc@some.domain>
2016/11/09 16:40:39 [MailBot/24031] DEBUG <-- 250 2.1.5 Ok
2016/11/09 16:40:39 [MailBot/24031] DEBUG --> RCPT TO:<bcc@some.domain>
2016/11/09 16:40:39 [MailBot/24031] DEBUG <-- 250 2.1.5 Ok
2016/11/09 16:40:39 [MailBot/24031] DEBUG --> DATA
2016/11/09 16:40:39 [MailBot/24031] DEBUG <-- 354 End data with <CR><LF>.<CR><LF>
2016/11/09 16:40:39 [MailBot/24031] DEBUG --> Sending mail data
2016/11/09 16:40:39 [MailBot/24031] DEBUG <-- 250 2.0.0 Ok: queued as 5FDFB2813B
2016/11/09 16:40:39 [MailBot/24031] DEBUG --> QUIT
2016/11/09 16:40:39 [MailBot/24031] DEBUG <-- 221 2.0.0 Bye
2016/11/09 16:40:39 [MailBot/24031] INFO OK: successfully sent message from <your@mail.addr> to 3 recipient(s)
```

### `EMail::Message` object(`mail` variable in above code)

You can set multiple _From_, _To_, _Cc_, _Bcc_ or _Reply-To_ addresses by calling `#from`, `#to`, `#cc`, `#bcc` or `#reply_to` multiple times.

```crystal
mail.to "to1@some.domain"
mail.to "to2@some.domain"

# Optionally, you can add mailbox name to above mail addresses.

mail.from "your@mail.addr", "Your Name"
```

Call `#attach` to add an attachment file.

```crystal
mail.attach "attachment.txt"

# You can designate other file name for recipient.

mail.attach "attachment.txt", file_name: "other_name.txt"

# You can designate mime type of the attachment file explicitly.
#
# By default, the mime type of the attachment file will be infered
# from the extension of that file.
#   eg: ".txt" => "text/plain"

mail.attach "attachment", mime_type: "text/plain"

# You can use readable `IO` object instead of the file path.
# In this case, the 2nd argument(`file_name`) is required.
# (The `mime_type` argument is also acceptable.)

mail.attach some_io, file_name: "other_name.txt"
```

UTF-8 string can be used as follows:
- mail message
- part of header body(when it can be multibyte)
- name of attachment file

```crystal
mail.subject "メールサブジェクト"
mail.from "your@mail.addr", "山田　太郎"
mail.to "to@mail.addr", "山田　花子"
mail.message <<-EOM
こんにちは
EOM
mail.attach "写真.jpg"
```

For the simplifying the implementation, the mail message and all attached data will be encoded by Base64, even when that includes only ascii characters.

Call `#envelope_from`, `#sender`, `#return_path` to set envelope from address, _Sender_ or _Return-Path_ explicitly.

```crystal
mail.envelope_from "return@your.mail"
mail.sender        "sender@your.mail"
mail.return_path   "return@your.mail"
```

When they are unspecified:

- Envelope from

    The first _From_ address will be assigned.

- _Sender_

    When _From_ has only one address, _Sender_ will not appear. Otherwise, the first _From_ address will be assigned.

- _Return-Path_
    1. Use envelope from address if it is explicitly specified.
    2. Use _Sender_ address if it is exist.
    3. Otherwise, the first _From_ address will be assigned.

## Contributors

- [arcage](https://github.com/arcage) ʕ·ᴥ·ʔAKJ - creator, maintainer
