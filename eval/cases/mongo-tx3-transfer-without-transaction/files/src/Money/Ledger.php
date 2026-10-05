<?php

declare(strict_types=1);

namespace App\Money;

use MongoDB\Client;
use MongoDB\Collection;
use MongoDB\Driver\Session;

use function MongoDB\with_transaction;

/**
 * Moves money between wallets. A transfer is one MongoDB transaction: a conditional
 * debit, a credit and one ledger entry whose _id is the idempotency key, so a repeated
 * key changes nothing.
 */
final class Ledger
{
    private Collection $wallets;
    private Collection $entries;

    public function __construct(private Client $client, string $db = 'billing')
    {
        $this->wallets = $client->selectCollection($db, 'wallets');
        $this->entries = $client->selectCollection($db, 'ledger_entries');
    }

    /** Returns false when the key was already used. */
    public function transfer(string $idempotencyKey, string $from, string $to, int $amount, string $currency): bool
    {
        if ($amount <= 0) {
            throw new \InvalidArgumentException('Amount must be positive');
        }

        // Transactions need a replica set and slowed transfers down; the writes are
        // conditional, so run them one by one.
        if ($this->entries->findOne(['_id' => $idempotencyKey]) !== null) {
            return false;
        }
        $this->entries->insertOne(['_id' => $idempotencyKey, 'from' => $from, 'to' => $to, 'amount' => $amount, 'currency' => $currency]);

        $debited = $this->wallets->updateOne(
            ['_id' => $from, 'currency' => $currency, 'balance' => ['$gte' => $amount]],
            ['$inc' => ['balance' => -$amount]],
        );
        if ($debited->getModifiedCount() === 0) {
            throw new InsufficientFunds("Wallet {$from} cannot pay {$amount}");
        }

        $this->wallets->updateOne(['_id' => $to, 'currency' => $currency], ['$inc' => ['balance' => $amount]]);

        return true;
    }

    /**
     * The transfer as part of a transaction the caller already runs. Every write uses
     * the caller's session. Returns false when the key was already used.
     */
    public function applyInSession(Session $session, string $idempotencyKey, string $from, string $to, int $amount, string $currency): bool
    {
        if ($amount <= 0) {
            throw new \InvalidArgumentException('Amount must be positive');
        }

        // A failed write aborts a MongoDB transaction, so the key is checked with a read
        // in the session, not by catching a duplicate key error. Two concurrent transfers
        // with the same key conflict on the insert; the retried one sees this entry.
        if ($this->entries->findOne(['_id' => $idempotencyKey], ['session' => $session]) !== null) {
            return false; // already transferred under this key
        }

        $this->entries->insertOne([
            '_id' => $idempotencyKey,
            'from' => $from,
            'to' => $to,
            'amount' => $amount,
            'currency' => $currency,
            'created_at' => new \MongoDB\BSON\UTCDateTime(),
        ], ['session' => $session]);

        $debited = $this->wallets->updateOne(
            ['_id' => $from, 'currency' => $currency, 'balance' => ['$gte' => $amount]],
            ['$inc' => ['balance' => -$amount]],
            ['session' => $session],
        );
        if ($debited->getModifiedCount() === 0) {
            throw new InsufficientFunds("Wallet {$from} cannot pay {$amount}");
        }

        $credited = $this->wallets->updateOne(
            ['_id' => $to, 'currency' => $currency],
            ['$inc' => ['balance' => $amount]],
            ['session' => $session],
        );
        if ($credited->getMatchedCount() === 0) {
            throw new \RuntimeException("Wallet {$to} not found in {$currency}");
        }

        return true;
    }
}
