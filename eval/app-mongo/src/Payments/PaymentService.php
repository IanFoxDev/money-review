<?php

declare(strict_types=1);

namespace App\Payments;

use App\Money\Ledger;
use MongoDB\Client;
use MongoDB\Collection;
use MongoDB\Driver\Session;

use function MongoDB\with_transaction;

/**
 * Card payments through a provider. A successful payment credits the user's wallet
 * from the provider clearing wallet and queues a payment.paid event in the outbox
 * array of the payment document, all in one transaction.
 */
final class PaymentService
{
    private Collection $payments;
    private Collection $processed;

    public function __construct(private Client $client, private Ledger $ledger, string $db = 'billing')
    {
        $this->payments = $client->selectCollection($db, 'payments');
        $this->processed = $client->selectCollection($db, 'processed_events');
    }

    /** Handles the provider's payment.succeeded event. Safe to call again with the same event. */
    public function confirm(string $eventId, string $paymentId): void
    {
        $session = $this->client->startSession();

        with_transaction($session, function (Session $session) use ($eventId, $paymentId): void {
            if ($this->processed->findOne(['_id' => 'psp:' . $eventId], ['session' => $session]) !== null) {
                return; // a retry of an event we already handled
            }
            $this->processed->insertOne(['_id' => 'psp:' . $eventId], ['session' => $session]);

            $payment = $this->payments->findOneAndUpdate(
                ['_id' => $paymentId, 'status' => 'pending'],
                [
                    '$set' => ['status' => 'paid', 'paid_at' => new \MongoDB\BSON\UTCDateTime()],
                    '$push' => ['outbox' => ['id' => 'payment.paid:' . $paymentId, 'type' => 'payment.paid', 'published' => false]],
                ],
                ['session' => $session, 'returnDocument' => \MongoDB\Operation\FindOneAndUpdate::RETURN_DOCUMENT_AFTER],
            );
            if ($payment === null) {
                return; // late or out of order event, the state already moved
            }

            $this->ledger->applyInSession(
                $session,
                'payment:' . $paymentId,
                'clearing:' . $payment['currency'],
                'user:' . $payment['user_id'] . ':' . $payment['currency'],
                (int) $payment['amount'],
                $payment['currency'],
            );
        });
    }
}
