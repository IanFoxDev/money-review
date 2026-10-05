<?php

declare(strict_types=1);

namespace App\Payouts;

use MongoDB\Client;
use MongoDB\Collection;
use MongoDB\Driver\ReadPreference;

/** Instant withdrawal to a card for small amounts. The provider call happens later, from the queue. */
final class InstantWithdrawal
{
    private Collection $wallets;
    private Collection $withdrawals;

    public function __construct(Client $client, string $db = 'billing')
    {
        // Balance reads are heavy at peak time, keep them off the primary.
        $this->wallets = $client->selectCollection($db, 'wallets', [
            'readPreference' => new ReadPreference(ReadPreference::SECONDARY_PREFERRED),
        ]);
        $this->withdrawals = $client->selectCollection($db, 'withdrawals');
    }

    public function reserve(string $requestId, string $walletId, int $amount): bool
    {
        $wallet = $this->wallets->findOne(['_id' => $walletId]);
        if ($wallet === null || $wallet['balance'] < $amount) {
            return false;
        }

        $this->withdrawals->insertOne(['_id' => $requestId, 'wallet_id' => $walletId, 'amount' => $amount, 'status' => 'reserved']);
        $this->wallets->updateOne(['_id' => $walletId], ['$inc' => ['balance' => -$amount]]);

        return true;
    }
}
