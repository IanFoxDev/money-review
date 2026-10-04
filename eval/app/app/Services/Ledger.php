<?php

namespace App\Services;

use App\Exceptions\InsufficientFunds;
use App\Models\Account;
use Illuminate\Support\Facades\DB;

/**
 * Double-entry ledger. accounts.balance_cents is a cache of ledger_entries and is
 * changed only here, in the same transaction as the entries.
 */
final class Ledger
{
    /** Returns the ledger transaction id. A repeated key returns the first transaction. */
    public function transfer(string $idempotencyKey, Account $from, Account $to, int $amountCents, string $kind): int
    {
        if ($amountCents <= 0) {
            throw new \InvalidArgumentException('Amount must be positive');
        }
        if ($from->currency !== $to->currency) {
            throw new \InvalidArgumentException('Currency mismatch');
        }

        return DB::transaction(function () use ($idempotencyKey, $from, $to, $amountCents, $kind) {
            $inserted = DB::table('ledger_transactions')->insertOrIgnore([
                'idempotency_key' => $idempotencyKey,
                'kind' => $kind,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
            $txId = (int) DB::table('ledger_transactions')->where('idempotency_key', $idempotencyKey)->value('id');
            if ($inserted === 0) {
                return $txId;
            }

            // Lock both accounts in id order so that A->B and B->A cannot deadlock.
            $locked = Account::whereKey([$from->id, $to->id])->orderBy('id')->lockForUpdate()->get()->keyBy('id');
            $source = $locked[$from->id];
            $target = $locked[$to->id];

            if (! $source->allow_negative && $source->balance_cents < $amountCents) {
                throw new InsufficientFunds();
            }

            DB::table('ledger_entries')->insert([
                ['ledger_transaction_id' => $txId, 'account_id' => $source->id, 'amount_cents' => -$amountCents, 'currency' => $source->currency, 'created_at' => now()],
                ['ledger_transaction_id' => $txId, 'account_id' => $target->id, 'amount_cents' => $amountCents, 'currency' => $target->currency, 'created_at' => now()],
            ]);
            Account::whereKey($source->id)->update(['balance_cents' => DB::raw('balance_cents - '.$amountCents)]);
            Account::whereKey($target->id)->update(['balance_cents' => DB::raw('balance_cents + '.$amountCents)]);

            return $txId;
        });
    }
}
