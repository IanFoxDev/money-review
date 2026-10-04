<?php

namespace App\Services;

use App\Models\Account;
use Illuminate\Support\Facades\DB;

final class WithdrawalService
{
    public function __construct(private PaymentGateway $gateway)
    {
    }

    /** Moves money from the user's wallet to the pending withdrawals account. */
    public function withdraw(int $userId, int $amountCents, string $currency, string $requestId): void
    {
        $account = Account::forUser($userId, $currency);
        if ($account->balance_cents < $amountCents) {
            throw new \DomainException('Insufficient funds');
        }

        DB::transaction(function () use ($account, $amountCents, $currency, $requestId) {
            DB::table('ledger_transactions')->insert([
                'idempotency_key' => "withdrawal:{$requestId}", 'kind' => 'withdrawal',
                'created_at' => now(), 'updated_at' => now(),
            ]);
            $account->balance_cents -= $amountCents;
            $account->save();
            Account::system('withdrawals_pending', $currency)->increment('balance_cents', $amountCents);
        });
    }
}
