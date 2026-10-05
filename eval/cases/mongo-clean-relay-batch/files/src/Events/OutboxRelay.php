<?php

declare(strict_types=1);

namespace App\Events;

use MongoDB\Client;
use MongoDB\Collection;

/**
 * Publishes unpublished outbox events of payment documents to Kafka, keyed by the
 * user id, so the events of one user keep their order. At least once: an event can
 * be published again if the process dies after the flush and before the mark.
 */
final class OutboxRelay
{
    private Collection $payments;

    public function __construct(
        Client $client,
        private \RdKafka\Producer $producer,
        private \Psr\Log\LoggerInterface $logger,
        private int $batchSize = 100,
        string $db = 'billing',
    )
    {
        $this->payments = $client->selectCollection($db, 'payments');
    }

    public function runOnce(): int
    {
        $limit = $this->batchSize;
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
                $topic->produce(RD_KAFKA_PARTITION_UA, 0, $payload, (string) $payment['user_id']);
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

        $this->logger->info('outbox.relay.batch', ['payments' => $published, 'limit' => $limit]);

        return $published;
    }
}
