<?php

declare(strict_types=1);

namespace App\Money;

use MongoDB\Client;
use MongoDB\Collection;

/** Charges the monthly account fee. Run by a scheduler once a month per wallet. */
final class FeeCharger
{
    private Collection $wallets;

    public function __construct(Client $client, string $db = 'billing')
    {
        $this->wallets = $client->selectCollection($db, 'wallets');
    }

    public function charge(string $walletId, int $fee): bool
    {
        $wallet = $this->wallets->findOne(['_id' => $walletId]);
        if ($wallet === null || $wallet['balance'] < $fee) {
            return false;
        }

        $this->wallets->updateOne(
            ['_id' => $walletId],
            ['$set' => ['balance' => $wallet['balance'] - $fee, 'fee_charged_at' => new \MongoDB\BSON\UTCDateTime()]],
        );

        return true;
    }
}
