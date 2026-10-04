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
        $this->assertTransferable($from, $to, $amountCents);

        return DB::transaction(function () use ($idempotencyKey, $from, $to, $amountCents, $kind) {
            $txId = $this->openTransaction($idempotencyKey, $kind);
            if ($txId === null) {
                return (int) DB::table('ledger_transactions')->where('idempotency_key', $idempotencyKey)->value('id');
            }

            [$source, $target] = $this->lockPair($from, $to);

            if (! $source->allow_negative && $source->balance_cents < $amountCents) {
                throw new InsufficientFunds();
            }

            $this->post($txId, $source, -$amountCents);
            $this->post($txId, $target, $amountCents);

            return $txId;
        });
    }

    private function assertTransferable(Account $from, Account $to, int $amountCents): void
    {
        if ($amountCents <= 0) {
            throw new \InvalidArgumentException('Amount must be positive');
        }
        if ($from->currency !== $to->currency) {
            throw new \InvalidArgumentException('Currency mismatch');
        }
    }

    /** Null when a transaction with this key already exists. */
    private function openTransaction(string $idempotencyKey, string $kind): ?int
    {
        $inserted = DB::table('ledger_transactions')->insertOrIgnore([
            'idempotency_key' => $idempotencyKey,
            'kind' => $kind,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
        if ($inserted === 0) {
            return null;
        }

        return (int) DB::table('ledger_transactions')->where('idempotency_key', $idempotencyKey)->value('id');
    }

    /**
     * Locks both accounts in id order so that A->B and B->A cannot deadlock.
     *
     * @return array{0: Account, 1: Account}
     */
    private function lockPair(Account $from, Account $to): array
    {
        $locked = Account::whereKey([$from->id, $to->id])->orderBy('id')->lockForUpdate()->get()->keyBy('id');

        return [$locked[$from->id], $locked[$to->id]];
    }

    private function post(int $txId, Account $account, int $amountCents): void
    {
        DB::table('ledger_entries')->insert([
            'ledger_transaction_id' => $txId,
            'account_id' => $account->id,
            'amount_cents' => $amountCents,
            'currency' => $account->currency,
            'created_at' => now(),
        ]);
        Account::whereKey($account->id)->update(['balance_cents' => DB::raw('balance_cents + '.$amountCents)]);
    }
}
