<?php

declare(strict_types=1);

namespace App\Payments;

use App\Money\Ledger;
use MongoDB\BSON\ObjectId;
use MongoDB\BSON\UTCDateTime;
use MongoDB\Client;
use MongoDB\Collection;
use MongoDB\Driver\Session;

use function MongoDB\with_transaction;

/**
 * deposit.received notifications from CardHub virtual IBANs: a user sent a bank
 * transfer to their personal IBAN. The webhook endpoint checks the signature and
 * passes the decoded JSON body:
 *
 *   {"deposit_id": 88123017, "account_ref": "u_42", "amount": 2500, "currency": "EUR"}
 *
 * CardHub repeats a notification until it gets a 200, sometimes hours later. A
 * deposit becomes a paid payment, with the same wallet credit and payment.paid event
 * as a card payment in PaymentService::confirm().
 */
final class BankDepositHandler
{
    private Collection $payments;

    public function __construct(private Client $client, private Ledger $ledger, string $db = 'billing')
    {
        $this->payments = $client->selectCollection($db, 'payments');
    }

    /** @param array<string, mixed> $notification */
    public function handle(array $notification): void
    {
        $depositId = $notification['deposit_id'] ?? null;
        $userId = preg_replace('/^u_/', '', (string) ($notification['account_ref'] ?? ''));
        $amount = $notification['amount'] ?? null;
        $currency = strtoupper((string) ($notification['currency'] ?? ''));
        if ($depositId === null || $userId === '' || ! is_int($amount) || $amount <= 0 || strlen($currency) !== 3) {
            throw new \UnexpectedValueException('Malformed deposit notification');
        }

        $session = $this->client->startSession();

        with_transaction($session, function (Session $session) use ($depositId, $userId, $amount, $currency): void {
            // CardHub retries: one payment per deposit.
            if ($this->payments->findOne(['provider_deposit_id' => $depositId], ['session' => $session]) !== null) {
                return;
            }

            $paymentId = (string) new ObjectId();
            $this->payments->insertOne([
                '_id' => $paymentId,
                'user_id' => $userId,
                'amount' => $amount,
                'currency' => $currency,
                'method' => 'bank_transfer',
                'status' => 'paid',
                'paid_at' => new UTCDateTime(),
                'provider_deposit_id' => (string) $depositId, // ids are strings in our documents
                'outbox' => [['id' => 'payment.paid:' . $paymentId, 'type' => 'payment.paid', 'published' => false]],
            ], ['session' => $session]);

            $this->ledger->applyInSession(
                $session,
                'payment:' . $paymentId,
                'clearing:' . $currency,
                'user:' . $userId . ':' . $currency,
                $amount,
                $currency,
            );
        });
    }
}
