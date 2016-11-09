# EMail for Crystal Language

Simple e-Mail sending library for **Cristal**.

## Installation

Add this to your application's `shard.yml`:

```yaml
dependencies:
  email:
    github: arcage/crystal-email
```

## Usage

### Basic e-Mail sending procedure

```crystal
require "email"

EMail.send("your.mx.server.name") do |mail|
  mail.from     "your@mail.addr"
  mail.to       "rcpt1@some.cdomain"
  mail.subject  "Subject of the mail"
  mail.message <<-EOM
  Message body of the mail.

  --
  Your Signature
  EOM
end
```

## Contributors

- [arcage](https://github.com/arcage) ʕ·ᴥ·ʔAKJ - creator, maintainer
