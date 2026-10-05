# Eval app: PHP and Go with MongoDB and Kafka

A small billing service without a framework: PHP with the `mongodb/mongodb` library,
`rdkafka` and `phpredis`, and a Go worker with the official MongoDB driver and
`kafka-go`. It has no known money bugs. Eval cases with `"app": "app-mongo"` put
their files on top of it. It is never run, only read, so there is no vendor
directory.

Amounts are integers in minor units (`int` in PHP, `int64` in Go) with a currency.
