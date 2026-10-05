<?php

declare(strict_types=1);

namespace App\Events;

use MongoDB\Client;
use MongoDB\Collection;

/**
 * Publishes unpublished outbox events of payment documents to Kafka. At least once:
 * an event can be published again if the process dies after the flush and before the
 * mark.
 */
final class OutboxRelay
{
    private Collection $payments;

    public function __construct(Client $client, private \RdKafka\Producer $producer, string $db = 'billing')
    {
        $this->payments = $client->selectCollection($db, 'payments');
    }

    public function runOnce(int $limit = 100): int
    {
        $topic = $this->producer->newTopic('billing.payments');
        $published = 0;

        $cursor = $this->payments->find(['outbox.published' => false], ['limit' => $limit, 'sort' => ['_id' => 1]]);
        foreach ($cursor as $payment) {
            $produced = [];
            foreach ($payment['outbox'] as $event) {
                if ($event['published']) {
                    continue;
                }
                $payload = json_encode([
                    'event_id' => $event['id'],
                    'type' => $event['type'],
                    'payment_id' => (string) $payment['_id'],
                    'user_id' => $payment['user_id'],
                    'partner_id' => $payment['partner_id'] ?? null,
                    'amount' => (int) $payment['amount'],
                    'currency' => $payment['currency'],
                ], JSON_THROW_ON_ERROR);
                // Spread the load evenly over partitions.
                $topic->produce(RD_KAFKA_PARTITION_UA, 0, $payload);
                $produced[] = $event['id'];
            }

            if ($this->producer->flush(10_000) !== RD_KAFKA_RESP_ERR_NO_ERROR) {
                throw new \RuntimeException('Kafka flush failed, events stay unpublished');
            }

            $this->payments->updateOne(
                ['_id' => $payment['_id']],
                ['$set' => ['outbox.$[e].published' => true]],
                // Only the events produced above: an event pushed meanwhile stays unpublished.
                ['arrayFilters' => [['e.id' => ['$in' => $produced]]]],
            );
            $published++;
        }

        return $published;
    }
}
