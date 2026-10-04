<?php

namespace App\Jobs;

use App\Exceptions\GatewayDeclined;
use App\Exceptions\GatewayTimeout;
use App\Models\Account;
use App\Models\Payout;
use App\Services\Ledger;
use App\Services\PaymentGateway;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Support\Facades\DB;

/**
 * Pays every partner their balance for a period. Safe to re-run: one payout row per
 * partner and period, one ledger transaction per payout, the provider call uses the
 * payout id as idempotency key.
 */
final class RunMonthlyPayouts implements ShouldQueue
{
    public function __construct(public string $period)
    {
    }

    public function handle(Ledger $ledger, PaymentGateway $gateway): void
    {
        $accounts = Account::where('owner_type', 'partner')->where('balance_cents', '>', 0)->get();

        foreach ($accounts as $account) {
            $payout = DB::transaction(function () use ($account, $ledger) {
                $payout = Payout::firstOrCreate(
                    ['partner_id' => $account->owner_id, 'period' => $this->period],
                    ['amount_cents' => $account->balance_cents, 'currency' => $account->currency, 'status' => 'pending'],
                );
                $ledger->transfer(
                    "payout:{$payout->id}",
                    $account,
                    Account::system('payouts_in_flight', $account->currency),
                    $payout->amount_cents,
                    'payout',
                );

                return $payout;
            });

            if ($payout->status !== 'pending') {
                continue;
            }

            try {
                $reference = $gateway->payout($payout->partner_id, $payout->amount_cents, $payout->currency, "payout-{$payout->id}");
                Payout::whereKey($payout->id)->where('status', 'pending')
                    ->update(['status' => 'sent', 'psp_reference' => $reference]);
            } catch (GatewayTimeout|GatewayDeclined) {
                // Partners complained about payouts stuck in pending: fail fast and give the money back.
                DB::transaction(function () use ($payout, $ledger, $account) {
                    $moved = Payout::whereKey($payout->id)->where('status', 'pending')->update(['status' => 'failed']);
                    if ($moved === 1) {
                        $ledger->transfer(
                            "payout-return:{$payout->id}",
                            Account::system('payouts_in_flight', $account->currency),
                            $account,
                            $payout->amount_cents,
                            'payout_return',
                        );
                    }
                });
            }
        }
    }
}
