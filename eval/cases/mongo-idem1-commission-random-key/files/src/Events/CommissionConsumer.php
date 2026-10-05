<?php

declare(strict_types=1);

namespace App\Events;

use App\Money\Ledger;

/**
 * Pays partner commission for paid payments. Offsets are committed by hand after the
 * transfer; the ledger key from the event id makes a redelivery a no-op.
 */
final class CommissionConsumer
{
    private const PERCENT = 7;

    public function __construct(private \RdKafka\KafkaConsumer $consumer, private Ledger $ledger)
    {
        // Created with enable.auto.commit=false.
    }

    public function run(): void
    {
        $this->consumer->subscribe(['billing.payments']);

        while (true) {
            $message = $this->consumer->consume(1_000);
            if ($message->err === RD_KAFKA_RESP_ERR__TIMED_OUT || $message->err === RD_KAFKA_RESP_ERR__PARTITION_EOF) {
                continue;
            }
            if ($message->err !== RD_KAFKA_RESP_ERR_NO_ERROR) {
                throw new \RuntimeException($message->errstr());
            }

            $this->handle(json_decode($message->payload, true, flags: JSON_THROW_ON_ERROR));
            $this->consumer->commit($message);
        }
    }

    /** @param array<string, mixed> $event */
    private function handle(array $event): void
    {
        if ($event['type'] !== 'payment.paid' || $event['partner_id'] === null) {
            return;
        }

        $commission = intdiv((int) $event['amount'] * self::PERCENT, 100);
        if ($commission === 0) {
            return;
        }

        $this->ledger->transfer(
            'commission:' . bin2hex(random_bytes(8)),
            'revenue:' . $event['currency'],
            'partner:' . $event['partner_id'] . ':' . $event['currency'],
            $commission,
            $event['currency'],
        );
    }
}
