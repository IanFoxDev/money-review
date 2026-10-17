<?php

declare(strict_types=1);

namespace App\Events;

use App\Money\Ledger;
use MongoDB\Client;
use MongoDB\Collection;

/**
 * Pays partner commission for paid payments and takes it back when a payment is
 * refunded in full. Offsets are committed by hand after the transfer; the ledger keys
 * from the event id make a redelivery a no-op.
 *
 * The rate is per partner (partners.commission_percent), set by account managers.
 */
final class CommissionConsumer
{
    private const DEFAULT_PERCENT = 7;

    private Collection $partners;

    public function __construct(
        private \RdKafka\KafkaConsumer $consumer,
        private Ledger $ledger,
        Client $client,
        string $db = 'billing',
    ) {
        // Created with enable.auto.commit=false.
        $this->partners = $client->selectCollection($db, 'partners');
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
        if ($event['partner_id'] === null) {
            return;
        }

        match ($event['type']) {
            'payment.paid' => $this->pay($event),
            'payment.refunded' => $this->clawBack($event),
            default => null,
        };
    }

    /** @param array<string, mixed> $event */
    private function pay(array $event): void
    {
        $commission = $this->commission((string) $event['partner_id'], (int) $event['amount']);
        if ($commission === 0) {
            return;
        }

        $this->ledger->transfer(
            'commission:' . $event['event_id'],
            'revenue:' . $event['currency'],
            'partner:' . $event['partner_id'] . ':' . $event['currency'],
            $commission,
            $event['currency'],
        );
    }

    /**
     * A full refund: the partner gives back what they earned on the payment.
     *
     * @param array<string, mixed> $event
     */
    private function clawBack(array $event): void
    {
        $commission = $this->commission((string) $event['partner_id'], (int) $event['amount']);
        if ($commission === 0) {
            return;
        }

        $this->ledger->transfer(
            'commission-clawback:' . $event['event_id'],
            'partner:' . $event['partner_id'] . ':' . $event['currency'],
            'revenue:' . $event['currency'],
            $commission,
            $event['currency'],
        );
    }

    private function commission(string $partnerId, int $amount): int
    {
        $partner = $this->partners->findOne(['_id' => $partnerId], ['projection' => ['commission_percent' => 1]]);
        $percent = (int) ($partner['commission_percent'] ?? self::DEFAULT_PERCENT);

        return intdiv($amount * $percent, 100);
    }
}
